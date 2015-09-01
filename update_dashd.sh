#!/bin/bash

# update_dashd.sh
# interactively update your local linux dashd to latest distributed version

# dependencies:
#     wget
#     perl
#     dashd - version 12 or greater
#     dash-cli

# ----------------------------------------------------------------------------

C_RED="\e[31m"
C_YELLOW="\e[33m"
C_GREEN="\e[32m"
C_CYAN="\e[36m"
C_NORM="\e[0m"

SCRIPT_VERSION=0.0.8

DOWNLOAD_PAGE='https://www.dashpay.io/downloads/'

# ----------------------------------------------------------------------------

# attempt to locate dash-cli executable
INSTALL_DIR=''
if   [ -e ./dash-cli ];            then INSTALL_DIR='.' ;
elif [ -e $HOME/.dash/dash-cli ] ; then INSTALL_DIR="$HOME/.dash" ;
elif [ ! -z $(which dash-cli) ] ;  then INSTALL_DIR=$(which dash-cli);
    INSTALL_DIR=${INSTALL_DIR%%/dash-cli};
fi
INSTALL_DIR=$(readlink -f $INSTALL_DIR)
if [ ! -e $INSTALL_DIR ]; then
    echo -e "${C_RED}cannot find dash-cli in current directory, ~/.dash, or \$PATH. -- Exiting.$C_NORM"
    exit 1
fi

DASH_CLI="$INSTALL_DIR/dash-cli"

# check INSTALL_DIR has dashd and dash-cli
if [ ! -e $INSTALL_DIR/dashd ]; then
    echo -e "${C_RED}dashd not found in $INSTALL_DIR -- Exiting.$C_NORM"
    exit 1
fi

if [ ! -e $DASH_CLI ]; then
    echo -e "${C_RED}dash-cli not found in $INSTALL_DIR -- Exiting.$C_NORM"
    exit 1
fi

# ----------------------------------------------------------------------------

usage() {
    echo ""
    echo -e "${C_NORM}usage: ${0##*/} [-h|--help -v|--version --reinstall]"
    echo "-h --help"
    echo "   This help."
    echo "-v"
    echo "   print script version"
    echo "--version"
    echo "   print script name and version"
    echo "--reinstall "
    echo "   re-download and overwrite dash executables"
}

confirm() { read -r -p "${1:-Are you sure? [y/N]} "; [[ ${REPLY:0:1} = [Yy] ]]; }

_check_script_updates() {
    GITHUB_SCRIPT_VERSION=$( wget --no-check-certificate -q https://raw.githubusercontent.com/moocowmoo/dashman/master/VERSION -O - )
    if [ "$SCRIPT_VERSION" != "$GITHUB_SCRIPT_VERSION" ]; then
        echo -e "\n"
        echo -e "${C_RED}${0##*/} requires updating. Latest version is: $C_GREEN$GITHUB_SCRIPT_VERSION$C_RED\nIn dashman directory, do './sync_dashman_to_github.sh' and try again. Exiting.$C_NORM\n"
        exit 1
    fi
}

_get_versions() {
    DOWNLOAD_HTML=$( wget --no-check-certificate -q $DOWNLOAD_PAGE -O - )
    local IFS=' '
    read -a DOWNLOAD_URLS <<< $( echo $DOWNLOAD_HTML | sed -e 's/ /\n/g' | grep binaries | grep Download | grep linux | perl -ne '/.*"([^"]+)".*/; print "$1 ";' 2>/dev/null )
    LATEST_VERSION=$( echo ${DOWNLOAD_URLS[0]} | perl -ne '/dash-([0-9.]+)-/; print $1;' 2>/dev/null )
    CURRENT_VERSION=$( $DASH_CLI --version | perl -ne '/v([0-9.]+)-/; print $1;' 2>/dev/null )
}

_check_dashd_running() {
    DASHD_RUNNING=0
    if [ $( $DASH_CLI help 2>/dev/null | wc -l ) -gt 0 ]; then
        DASHD_RUNNING=1
    fi
}

_get_platform_info() {
    PLATFORM=$(uname -m)
    case "$PLATFORM" in
        i[3-6]86)  
            BITS=32
            ;;
        x86_64)
            BITS=64
            ;;
        *)
            echo "unknown platform: $PLATFORM"
            echo "script currently only supports 32/64bit linux"
            echo "-- Exiting."
            exit 1
            ;;
    esac
}

_get_download_url(){
    for url in "${DOWNLOAD_URLS[@]}"
    do
        if [[ $url =~ .*linux${BITS}.* ]] ; then
            DOWNLOAD_URL=$url
            DOWNLOAD_FILE=${DOWNLOAD_URL##*/}
        fi
    done
}

# ----------------------------------------------------------------------------

while getopts ":hv-:" optchar; do
    case "${optchar}" in
        -)
            case "${OPTARG}" in
                reinstall)
                    REINSTALL=1
                ;;
                version)
                    echo -e "${0##*/} version $SCRIPT_VERSION"
                    exit 0
                ;;
                help)
                    usage
                    exit 0
                ;;
                *)
                if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                    echo "Unknown option --${OPTARG}" >&2
                fi
                ;;
            esac;;
        h)
            usage
            exit 0
            ;;
        v)
            echo -e "$SCRIPT_VERSION"
            exit 0
            ;;
        *)
            echo "Unknown option --${OPTARG}" >&2
        ;;
    esac
done

echo ""
echo -e "${C_CYAN}${0##*/} version $SCRIPT_VERSION"
echo -en "${C_YELLOW}gathering info..."
_check_script_updates
_get_platform_info
_get_versions
_check_dashd_running
_get_download_url
echo -e " ${C_GREEN}DONE!$C_NORM"

if [ $LATEST_VERSION != $CURRENT_VERSION ] || [ $REINSTALL ] ; then

    if [ $REINSTALL ];then
        echo -e ""
        echo -e "$C_GREEN*** current version of dashd is up-to-date. ***$C_NORM"
        echo -e ""
        echo -en "${C_YELLOW}reinstall to $INSTALL_DIR$C_NORM?"
    else
        echo -e ""
        echo -e "$C_RED*** a newer version of dashd is available. ***$C_NORM"
        echo -e ""
        echo -e "  current version: $C_RED$CURRENT_VERSION$C_NORM"
        echo -e "   latest version: $C_GREEN$LATEST_VERSION$C_NORM"
        echo -e ""
        echo -en "download $DOWNLOAD_URL\n"
        echo -en "and ${C_YELLOW}install to $INSTALL_DIR$C_NORM?"
    fi


    if ! confirm " [y/N]"; then
        echo -e "${C_RED}Exiting.$C_NORM"
        echo ""
        exit 0
    fi

    # push it ----------------------------------------------------------------

    cd $INSTALL_DIR

    # pull it ----------------------------------------------------------------

    echo ""
    for DOWNLOAD_URL in $DOWNLOAD_URL ${DOWNLOAD_URL}.DIGESTS.txt ; do
        download_file=${DOWNLOAD_URL##*/}
        if [ ! -e $download_file ] ; then
            echo -en "${C_YELLOW} --> downloading ${DOWNLOAD_URL}..."
            wget --no-check-certificate -q -r $DOWNLOAD_URL -O $download_file
            if [ ! -e $download_file ] ; then
                echo -e ""
                echo -e ""
                echo -e "${C_RED}error downloading file"
                echo -e "tried to get $DOWNLOAD_URL$C_NORM"
                exit 1
            fi
            echo -e " ${C_GREEN}DONE!$C_NORM"
        else
            echo -e "${C_YELLOW} --> using existing local file: ${download_file}"
        fi
    done

    # prove it ---------------------------------------------------------------

    echo -en "${C_YELLOW} --> checksumming ${DOWNLOAD_FILE}..."
    SHA256SUM=$( sha256sum $DOWNLOAD_FILE )
    MD5SUM=$( md5sum $DOWNLOAD_FILE )
    SHA256PASS=$( grep $SHA256SUM ${DOWNLOAD_FILE}.DIGESTS.txt | wc -l )
    MD5SUMPASS=$( grep $MD5SUM ${DOWNLOAD_FILE}.DIGESTS.txt | wc -l )
    if [ $SHA256PASS -lt 1 ] ; then
        mv ${DOWNLOAD_FILE}{,.invalid}
        mv ${DOWNLOAD_FILE}.DIGESTS.txt{,.invalid}
        echo -e " ${C_RED} SHA256 checksum FAILED! Downloaded files renamed. Try again later. Exiting.$C_NORM"
        exit 1
    fi
    if [ $MD5SUMPASS -lt 1 ] ; then
        mv ${DOWNLOAD_FILE}{,.invalid}
        mv ${DOWNLOAD_FILE}.DIGESTS.txt{,.invalid}
        echo -e " ${C_RED} MD5 checksum FAILED! Downloaded files renamed Try again later. Exiting.$C_NORM"
        exit 1
    fi
    echo -e " ${C_GREEN}DONE!$C_NORM"

    # produce it -------------------------------------------------------------

    echo -en "${C_YELLOW} --> unpacking ${DOWNLOAD_FILE}..." && \
    tar zxf $DOWNLOAD_FILE && \
    echo -e " ${C_GREEN}DONE!$C_NORM" && \

    # pummel it --------------------------------------------------------------

    if [ $DASHD_RUNNING == 1 ]; then 
        echo -en "${C_YELLOW} --> stopping dashd. please wait..."
        $DASH_CLI stop >/dev/null 2>&1
        sleep 15
        killall -9 dashd dash-shutoff >/dev/null 2>&1
        echo -e " ${C_GREEN}DONE!$C_NORM"
    fi

    # prune it ---------------------------------------------------------------

    echo -en "${C_YELLOW} --> Removing old version..." && \
    rm -f \
        debug.log \
        mncache.dat \
        peers.dat \
        dashd \
        dashd-$CURRENT_VERSION \
        dash-qt \
        dash-qt-$CURRENT_VERSION \
        dash-cli \
        dash-cli-$CURRENT_VERSION
    echo -e " ${C_GREEN}DONE!$C_NORM"

    # place it ---------------------------------------------------------------

    mv dash-0.12.0/bin/dashd dashd-$LATEST_VERSION
    mv dash-0.12.0/bin/dash-cli dash-cli-$LATEST_VERSION
    mv dash-0.12.0/bin/dash-qt dash-qt-$LATEST_VERSION
    ln -s dashd-$LATEST_VERSION dashd
    ln -s dash-cli-$LATEST_VERSION dash-cli
    ln -s dash-qt-$LATEST_VERSION dash-qt

    # purge it ---------------------------------------------------------------

    rm -rf dash-0.12.0

    # punch it ---------------------------------------------------------------

    echo -en "${C_YELLOW} --> Launching dashd..."
    $INSTALL_DIR/dashd > /dev/null
    echo -e " ${C_GREEN}DONE!$C_NORM"

    # probe it ---------------------------------------------------------------

    echo -en "${C_YELLOW} --> Waiting for dashd to respond..."
    while [ $DASHD_RUNNING == 0 ]; do
        echo -n "."
        _check_dashd_running
        sleep 5
    done
    echo -e " ${C_GREEN}DONE!$C_NORM"

    # poll it ----------------------------------------------------------------

    _get_versions

    # pass or punt -----------------------------------------------------------

    if [ $LATEST_VERSION == $CURRENT_VERSION ]; then
        echo -e ""
        echo -e "${C_GREEN}dashd successfully upgraded to version ${LATEST_VERSION}$C_NORM"
        echo -e ""
        echo -e "${C_GREEN}Installed in ${INSTALL_DIR}$C_NORM"
        echo -e ""
        ls -l --color {$DOWNLOAD_FILE,${DOWNLOAD_FILE}.DIGESTS.txt,dash-cli,dashd,dash-qt,dash*$LATEST_VERSION}
        echo -e ""
        echo -e "${C_GREEN}Exiting.$C_NORM"
    else
        echo -e "${C_RED}dashd version $CURRENT_VERSION is not up to date. ($LATEST_VERSION) Exiting.$C_NORM"
    fi

else
    echo -e ""
    echo -e "${C_GREEN}dashd version $CURRENT_VERSION is up to date. Exiting.$C_NORM"
fi

exit 0
