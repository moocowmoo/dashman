# vim: set filetype=sh ts=4 sw=4 et

# dashman_functions.sh - common functions and variables

# Copyright (c) 2015-2019 moocowmoo - moocowmoo@masternode.me

# variables are for putting things in ----------------------------------------

C_RED=''
C_YELLOW=''
C_GREEN=''
C_PURPLE=''
C_CYAN=''
C_NORM=''
TPUT_EL=''

if [ -t 1 ] || [ ! -z "$FORCE_COLOR" ] ; then
    C_RED="\e[31m"
    C_YELLOW="\e[33m"
    C_GREEN="\e[32m"
    C_PURPLE="\e[35m"
    C_CYAN="\e[36m"
    C_NORM="\e[0m"
    TPUT_EL=$(tput el)
fi


GITHUB_API_DASH="https://api.github.com/repos/dashpay/dash"

DASHD_RUNNING=0
DASHD_RESPONDING=0
DASHMAN_VERSION=$(cat $DASHMAN_GITDIR/VERSION)
DASHMAN_CHECKOUT=$(GIT_DIR=$DASHMAN_GITDIR/.git GIT_WORK_TREE=$DASHMAN_GITDIR git describe --dirty | sed -e "s/^.*-\([0-9]\+-g\)/\1/" )
if [ "$DASHMAN_CHECKOUT" == "v"$DASHMAN_VERSION ]; then
    DASHMAN_CHECKOUT=""
else
    DASHMAN_CHECKOUT=" ("$DASHMAN_CHECKOUT")"
fi

[ -z "$CACHE_EXPIRE" ] && CACHE_EXPIRE=5
[ -z "$ENABLE_CACHE" ] && ENABLE_CACHE=0

CACHE_CMD=''
[ $ENABLE_CACHE -gt 0 ] && CACHE_CMD='cached_cmd'

CACHE_DIR=/tmp/dashman_cache
mkdir -p $CACHE_DIR
chmod 700 $CACHE_DIR

curl_cmd="timeout 7 curl -k -s -L -A dashman/$DASHMAN_VERSION"
function cached_cmd() {
    cmd=""
    whitespace="[[:space:]]"
    punctuation="&"
    for i in "$@"; do
        if [[ $i =~ $whitespace ]];then
            i=\'$i\'
        fi
        if [[ $i =~ $punctuation ]];then
            i=\'$i\'
        fi
        cmd="$cmd $i"
    done

    FILE_HASH=$(echo $cmd| md5sum | awk '{print $1}')
    CACHE_FILE=$CACHE_DIR/$FILE_HASH
    find $CACHE_DIR -type f \( -name '*.cached' -o -name '*.err' -o -name '*.cmd' \) -cmin +$CACHE_EXPIRE -exec rm {} \; >/dev/null 2>&1
    if [ -e $CACHE_FILE.cached ];then
        cat $CACHE_FILE.cached
        return
    fi
    echo $cmd > $CACHE_FILE.cmd
    eval $cmd > $CACHE_FILE.cached 2> $CACHE_FILE.err
    if [ $? -gt 0 ];then
        exit $?
    fi
    if [ -e $CACHE_FILE.cached ];then
        cat $CACHE_FILE.cached
        return
    fi
}
curl_cmd="$CACHE_CMD $curl_cmd"
wget_cmd='wget --no-check-certificate -q'


# (mostly) functioning functions -- lots of refactoring to do ----------------

pending(){ [[ $QUIET ]] || ( echo -en "$C_YELLOW$1$C_NORM$TPUT_EL" ); }

ok(){ [[ $QUIET ]] || echo -e "$C_GREEN$1$C_NORM" ; }

warn() { [[ $QUIET ]] || echo -e "$C_YELLOW$1$C_NORM" ; }
highlight() { [[ $QUIET ]] || echo -e "$C_PURPLE$1$C_NORM" ; }

err() { [[ $QUIET ]] || echo -e "$C_RED$1$C_NORM" ; }
die() { [[ $QUIET ]] || echo -e "$C_RED$1$C_NORM" ; exit 1 ; }

quit(){ [[ $QUIET ]] || echo -e "$C_GREEN${1:-${messages["exiting"]}}$C_NORM" ; echo ; exit 0 ; }

confirm() { read -r -p "$(echo -e "${1:-${messages["prompt_are_you_sure"]} [y/N]}")" ; [[ ${REPLY:0:1} = [Yy] ]]; }


up()     { echo -e "\e[${1:-1}A"; }
clear_n_lines(){ for n in $(seq ${1:-1}) ; do tput cuu 1; tput el; done ; }


usage(){
    cat<<EOF



    ${messages["usage"]}: ${0##*/} [command]

        ${messages["usage_title"]}

    ${messages["commands"]}

        install

            ${messages["usage_install_description"]}

        update

            ${messages["usage_update_description"]}

        reinstall

            ${messages["usage_reinstall_description"]}

        restart [now]

            ${messages["usage_restart_description"]}
                debug.log
                banlist.dat
                fee_estimates.dat
                governance.dat
                instantsend.dat
                mempool.dat
                mncache.dat
                mnpayments.dat
                netfulfilled.dat
                peers.dat
                sporks.dat

            ${messages["usage_restart_description_now"]}

        status

            ${messages["usage_status_description"]}

        vote

            ${messages["usage_vote_description"]}

        sync

            ${messages["usage_sync_description"]}

        branch

            ${messages["usage_branch_description"]}

        version

            ${messages["usage_version_description"]}

EOF
}

function cache_output(){
    # cached output
    FILE=$1
    # command to cache
    CMD=$2
    OLD=0
    CONTENTS=""
    # is cache older than 1 minute?
    if [ -e $FILE ]; then
        OLD=$(find $FILE -mmin +1 -ls | wc -l)
        CONTENTS=$(cat $FILE);
    fi
    # is cache empty or older than 1 minute? rebuild
    if [ -z "$CONTENTS" ] || [ "$OLD" -gt 0 ]; then
        CONTENTS=$(eval $CMD)
        echo "$CONTENTS" > $FILE
    fi
    echo "$CONTENTS"
}

_check_dependencies() {

    (which python 2>&1) >/dev/null || die "${messages["err_missing_dependency"]} python - sudo apt-get install python"

    DISTRO=$(/usr/bin/env python -mplatform | sed -e 's/.*with-//g')
    if [[ $DISTRO == *"Ubuntu"* ]] || [[ $DISTRO == *"debian"* ]]; then
        PKG_MANAGER=apt-get
    elif [[ $DISTRO == *"centos"* ]]; then
        PKG_MANAGER=yum
    fi

    if [ -z "$PKG_MANAGER" ]; then
        (which apt-get 2>&1) >/dev/null || \
            (which yum 2>&1) >/dev/null || \
            die ${messages["err_no_pkg_mgr"]}

    fi

    (which curl 2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}curl "
    (which perl 2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}perl "
    (which git  2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}git "

    MN_CONF_ENABLED=$( egrep -s '^[^#]*\s*masternodeblsprivkey\s*=' $HOME/.dash{,core}/dash.conf | wc -l 2>/dev/null)
    if [ $MN_CONF_ENABLED -gt 0 ] ; then
        (which unzip 2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}unzip "
        (which virtualenv 2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}python-virtualenv "
    fi

    if [ "$1" == "install" ]; then
        # only require unzip for install
        (which unzip 2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}unzip "
        (which pv   2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}pv "

        # only require python-virtualenv for sentinel
        if [ "$2" == "sentinel" ]; then
            (which virtualenv 2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}python-virtualenv "
        fi
    fi

    # make sure we have the right netcat version (-4,-6 flags)
    if [ ! -z "$(which nc)" ]; then
        (nc -z -4 8.8.8.8 53 2>&1) >/dev/null
        if [ $? -gt 0 ]; then
            MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}netcat6 "
        fi
    else
        MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}netcat "
    fi

    if [ ! -z "$MISSING_DEPENDENCIES" ]; then
        err "${messages["err_missing_dependency"]} $MISSING_DEPENDENCIES\n"
        sudo $PKG_MANAGER install $MISSING_DEPENDENCIES
    fi


}

# attempt to locate dash-cli executable.
# search current dir, ~/.dash, `which dash-cli` ($PATH), finally recursive
_find_dash_directory() {

    INSTALL_DIR=''

    # dash-cli in PATH

    if [ ! -z $(which dash-cli 2>/dev/null) ] ; then
        INSTALL_DIR=$(readlink -f `which dash-cli`)
        INSTALL_DIR=${INSTALL_DIR%%/dash-cli*};


        #TODO prompt for single-user or multi-user install


        # if copied to /usr/*
        if [[ $INSTALL_DIR =~ \/usr.* ]]; then
            LINK_TO_SYSTEM_DIR=$INSTALL_DIR

            # if not run as root
            if [ $EUID -ne 0 ] ; then
                die "\n${messages["exec_found_in_system_dir"]} $INSTALL_DIR${messages["run_dashman_as_root"]} ${messages["exiting"]}"
            fi
        fi

    # dash-cli not in PATH

        # check current directory
    elif [ -e ./dash-cli ] ; then
        INSTALL_DIR='.' ;

        # check ~/.dash directory
    elif [ -e $HOME/.dash/dash-cli ] ; then
        INSTALL_DIR="$HOME/.dash" ;

    elif [ -e $HOME/.dashcore/dash-cli ] ; then
        INSTALL_DIR="$HOME/.dashcore" ;

        # TODO try to find dash-cli with find
#    else
#        CANDIDATES=`find $HOME -name dash-cli`
    fi

    if [ ! -z "$INSTALL_DIR" ]; then
        INSTALL_DIR=$(readlink -f $INSTALL_DIR) 2>/dev/null
        if [ ! -e $INSTALL_DIR ]; then
            echo -e "${C_RED}${messages["dashcli_not_found_in_cwd"]}, ~/.dashcore, or \$PATH. -- ${messages["exiting"]}$C_NORM"
            exit 1
        fi
    else
        echo -e "${C_RED}${messages["dashcli_not_found_in_cwd"]}, ~/.dashcore, or \$PATH. -- ${messages["exiting"]}$C_NORM"
        exit 1
    fi

    DASH_CLI="$INSTALL_DIR/dash-cli"

    # check INSTALL_DIR has dashd and dash-cli
    if [ ! -e $INSTALL_DIR/dashd ]; then
        echo -e "${C_RED}${messages["dashd_not_found"]} $INSTALL_DIR -- ${messages["exiting"]}$C_NORM"
        exit 1
    fi

    if [ ! -e $DASH_CLI ]; then
        echo -e "${C_RED}${messages["dashcli_not_found"]} $INSTALL_DIR -- ${messages["exiting"]}$C_NORM"
        exit 1
    fi

    DASH_CLI="$CACHE_CMD $INSTALL_DIR/dash-cli"

}


_check_dashman_updates() {
    GITHUB_DASHMAN_VERSION=$( $curl_cmd https://raw.githubusercontent.com/moocowmoo/dashman/master/VERSION )
    if [ ! -z "$GITHUB_DASHMAN_VERSION" ] && [ "$DASHMAN_VERSION" != "$GITHUB_DASHMAN_VERSION" ]; then
        echo -e "\n"
        echo -e "${C_RED}${0##*/} ${messages["requires_updating"]} $C_GREEN$GITHUB_DASHMAN_VERSION$C_RED\n${messages["requires_sync"]}$C_NORM\n"

        pending "${messages["sync_to_github"]} "

        if confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
            echo $DASHMAN_VERSION > $DASHMAN_GITDIR/PREVIOUS_VERSION
            exec $DASHMAN_GITDIR/${0##*/} sync $COMMAND
        fi
        die "${messages["exiting"]}"
    fi
}

_get_platform_info() {
    PLATFORM=$(uname -m)
    case "$PLATFORM" in
        i[3-6]86)
            PLAT=i686-pc
            ;;
        x86_64)
            PLAT=x86_64
            ;;
        armv7l)
            PLAT=arm
            ARM=1
            BIGARM=$(grep -E "(BCM2709|Freescale i\\.MX6)" /proc/cpuinfo | wc -l)
            ;;
        aarch64)
            PLAT=aarch64
            ARM=1
            BIGARM=$(grep -E "(BCM2709|Freescale i\\.MX6)" /proc/cpuinfo | wc -l)
            ;;
        *)
            err "${messages["err_unknown_platform"]} $PLATFORM"
            err "${messages["err_dashman_supports"]}"
            die "${messages["exiting"]}"
            ;;
    esac
}

_get_versions() {
    _get_platform_info


    local IFS=' '
    DOWNLOAD_FOR='linux'
    if [ ! -z "$BIGARM" ]; then
        DOWNLOAD_FOR='RPi2'
    fi

    GITHUB_RELEASE_JSON="$($curl_cmd $GITHUB_API_DASH/releases/latest | python -mjson.tool)"
    CHECKSUM_URL=$(echo "$GITHUB_RELEASE_JSON" | grep browser_download | grep SUMS.asc | cut -d'"' -f4)
    CHECKSUM_FILE=$( $curl_cmd $CHECKSUM_URL )

    read -a DOWNLOAD_URLS <<< $( echo "$GITHUB_RELEASE_JSON" | grep browser_download | grep -v 'debug' | grep -v '.asc' | grep $DOWNLOAD_FOR | cut -d'"' -f4 | tr "\n" " ")
    #$(( <-- vim syntax highlighting fix

    LATEST_VERSION=$(echo "$GITHUB_RELEASE_JSON" | grep tag_name | cut -d'"' -f4 | tr -d 'v')
    TARDIR="dashcore-${LATEST_VERSION::-2}"
    if [ -z "$LATEST_VERSION" ]; then
        die "\n${messages["err_could_not_get_version"]} -- ${messages["exiting"]}"
    fi

    if [ -z "$DASH_CLI" ]; then DASH_CLI='echo'; fi
    CURRENT_VERSION=$( $DASH_CLI --version | perl -ne '/v([0-9.]+)/; print $1;' 2>/dev/null ) 2>/dev/null
    for url in "${DOWNLOAD_URLS[@]}"
    do
        if [[ $url =~ .*${PLAT}-linux.* ]] ; then
            DOWNLOAD_URL=$url
            DOWNLOAD_FILE=${DOWNLOAD_URL##*/}
        fi
    done
}


_check_dashd_state() {
    _get_dashd_proc_status
    DASHD_RUNNING=0
    DASHD_RESPONDING=0
    if [ $DASHD_HASPID -gt 0 ] && [ $DASHD_PID -gt 0 ]; then
        DASHD_RUNNING=1
    fi
    $DASH_CLI getinfo >/dev/null 2>&1
    if [ $? -eq 0 ] || [ $? -eq 28 ]; then
        DASHD_RESPONDING=1
    fi
}

restart_dashd(){

    if [ $DASHD_RUNNING == 1 ]; then
        pending " --> ${messages["stopping"]} dashd. ${messages["please_wait"]}"
        $DASH_CLI stop 2>&1 >/dev/null
        sleep 10
        killall -9 dashd dash-shutoff 2>/dev/null
        ok "${messages["done"]}"
        DASHD_RUNNING=0
    fi

    pending " --> ${messages["deleting_cache_files"]}"

    cd $INSTALL_DIR

    rm -f \
        debug.log \
        banlist.dat \
        fee_estimates.dat \
        governance.dat \
        instantsend.dat \
        mempool.dat \
        mncache.dat \
        mnpayments.dat \
        netfulfilled.dat \
        peers.dat \
        sporks.dat

    ok "${messages["done"]}"

    pending " --> ${messages["starting_dashd"]}"
    $INSTALL_DIR/dashd 2>&1 >/dev/null
    DASHD_RUNNING=1
    ok "${messages["done"]}"

    pending " --> ${messages["waiting_for_dashd_to_respond"]}"
    echo -en "${C_YELLOW}"
    DASHD_RESPONDING=0
    while [ $DASHD_RUNNING == 1 ] && [ $DASHD_RESPONDING == 0 ]; do
        echo -n "."
        _check_dashd_state
        sleep 2
    done
    if [ $DASHD_RUNNING == 0 ]; then
        die "\n - dashd unexpectedly quit. ${messages["exiting"]}"
    fi
    ok "${messages["done"]}"
    pending " --> dash-cli getinfo"
    echo
    $DASH_CLI getinfo
    echo

}


update_dashd(){

    if [ $LATEST_VERSION != $CURRENT_VERSION ] || [ ! -z "$REINSTALL" ] ; then
                    

        if [ ! -z "$REINSTALL" ];then
            echo -e ""
            echo -e "$C_GREEN*** ${messages["dash_version"]} $CURRENT_VERSION is up-to-date. ***$C_NORM"
            echo -e ""
            echo -en

            pending "${messages["reinstall_to"]} $INSTALL_DIR$C_NORM?"
        else
            echo -e ""
            echo -e "$C_RED*** ${messages["newer_dash_available"]} ***$C_NORM"
            echo -e ""
            echo -e "${messages["currnt_version"]} $C_RED$CURRENT_VERSION$C_NORM"
            echo -e "${messages["latest_version"]} $C_GREEN$LATEST_VERSION$C_NORM"
            echo -e ""
            if [ -z "$UNATTENDED" ] ; then
                pending "${messages["download"]} $DOWNLOAD_URL\n${messages["and_install_to"]} $INSTALL_DIR?"
            else
                echo -e "$C_GREEN*** UNATTENDED MODE ***$C_NORM"
            fi
        fi


        if [ -z "$UNATTENDED" ] ; then
            if ! confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
                echo -e "${C_RED}${messages["exiting"]}$C_NORM"
                echo ""
                exit 0
            fi
        fi

        # push it ----------------------------------------------------------------

        cd $INSTALL_DIR

        # pull it ----------------------------------------------------------------

        pending " --> ${messages["downloading"]} ${DOWNLOAD_URL}... "
        wget --no-check-certificate -q -r $DOWNLOAD_URL -O $DOWNLOAD_FILE
        wget --no-check-certificate -q -r https://github.com/dashpay/dash/releases/download/v$LATEST_VERSION/SHA256SUMS.asc -O ${DOWNLOAD_FILE}.DIGESTS.txt
        if [ ! -e $DOWNLOAD_FILE ] ; then
            echo -e "${C_RED}${messages["err_downloading_file"]}"
            echo -e "${messages["err_tried_to_get"]} $DOWNLOAD_URL$C_NORM"

            exit 1
        else
            ok "${messages["done"]}"
        fi

        # prove it ---------------------------------------------------------------

        pending " --> ${messages["checksumming"]} ${DOWNLOAD_FILE}... "
        SHA256SUM=$( sha256sum $DOWNLOAD_FILE )
        SHA256PASS=$( grep $SHA256SUM ${DOWNLOAD_FILE}.DIGESTS.txt | wc -l )
        if [ $SHA256PASS -lt 1 ] ; then
            echo -e " ${C_RED} SHA256 ${messages["checksum"]} ${messages["FAILED"]} ${messages["try_again_later"]} ${messages["exiting"]}$C_NORM"
            exit 1
        fi
        ok "${messages["done"]}"

        # produce it -------------------------------------------------------------

        pending " --> ${messages["unpacking"]} ${DOWNLOAD_FILE}... " && \
        tar zxf $DOWNLOAD_FILE && \
        ok "${messages["done"]}"

        # pummel it --------------------------------------------------------------

        if [ $DASHD_RUNNING == 1 ]; then
            pending " --> ${messages["stopping"]} dashd. ${messages["please_wait"]}"
            $DASH_CLI stop >/dev/null 2>&1
            sleep 15
            killall -9 dashd dash-shutoff >/dev/null 2>&1
            ok "${messages["done"]}"
        fi

        # prune it ---------------------------------------------------------------

        pending " --> ${messages["removing_old_version"]}"
        rm -rf \
            debug.log \
            banlist.dat \
            fee_estimates.dat \
            governance.dat \
            instantsend.dat \
            mempool.dat \
            mncache.dat \
            mnpayments.dat \
            netfulfilled.dat \
            peers.dat \
            sporks.dat \
            dashd \
            dashd-$CURRENT_VERSION \
            dash-qt \
            dash-qt-$CURRENT_VERSION \
            dash-cli \
            dash-cli-$CURRENT_VERSION \
            dashcore-${CURRENT_VERSION}*.gz*
        ok "${messages["done"]}"

        # place it ---------------------------------------------------------------

        mv $TARDIR/bin/dashd dashd-$LATEST_VERSION
        mv $TARDIR/bin/dash-cli dash-cli-$LATEST_VERSION
        if [ $PLATFORM != 'armv7l' ];then
            mv $TARDIR/bin/dash-qt dash-qt-$LATEST_VERSION
        fi
        ln -s dashd-$LATEST_VERSION dashd
        ln -s dash-cli-$LATEST_VERSION dash-cli
        if [ $PLATFORM != 'armv7l' ];then
            ln -s dash-qt-$LATEST_VERSION dash-qt
        fi

        # permission it ----------------------------------------------------------

        if [ ! -z "$SUDO_USER" ]; then
            chown -h $SUDO_USER:$SUDO_USER {$DOWNLOAD_FILE,${DOWNLOAD_FILE}.DIGESTS.txt,dash-cli,dashd,dash-qt,dash*$LATEST_VERSION}
        fi

        # purge it ---------------------------------------------------------------

        rm -rf dash-0.12.0
        rm -rf dashcore-0.12.1*
        rm -rf dashcore-0.12.2*
        rm -rf dashcore-0.12.3*
        rm -rf $TARDIR

        # punch it ---------------------------------------------------------------

        pending " --> ${messages["launching"]} dashd... "
        touch $INSTALL_DIR/dashd.pid
        $INSTALL_DIR/dashd > /dev/null
        ok "${messages["done"]}"

        # probe it ---------------------------------------------------------------

        pending " --> ${messages["waiting_for_dashd_to_respond"]}"
        echo -en "${C_YELLOW}"
        DASHD_RUNNING=1
        while [ $DASHD_RUNNING == 1 ] && [ $DASHD_RESPONDING == 0 ]; do
            echo -n "."
            _check_dashd_state
            sleep 1
        done
        if [ $DASHD_RUNNING == 0 ]; then
            die "\n - dashd unexpectedly quit. ${messages["exiting"]}"
        fi
        ok "${messages["done"]}"

        # poll it ----------------------------------------------------------------

        MN_CONF_ENABLED=$( egrep -s '^[^#]*\s*masternodeblsprivkey\s*=' $INSTALL_DIR/dash.conf | wc -l 2>/dev/null)
        if [ $MN_CONF_ENABLED -gt 0 ] ; then

            # populate it --------------------------------------------------------

            pending " --> updating sentinel... "
            cd sentinel
            git remote update >/dev/null 2>&1 
            git reset -q --hard origin/master
            cd ..
            ok "${messages["done"]}"

            # patch it -----------------------------------------------------------

            pending "  --> updating crontab... "
            (crontab -l 2>/dev/null | grep -v sentinel.py ; echo "* * * * * cd $INSTALL_DIR/sentinel && venv/bin/python bin/sentinel.py  2>&1 >> sentinel-cron.log") | crontab -
            ok "${messages["done"]}"

        fi

        # poll it ----------------------------------------------------------------

        LAST_VERSION=$CURRENT_VERSION

        _get_versions

        # pass or punt -----------------------------------------------------------

        if [ $LATEST_VERSION == $CURRENT_VERSION ]; then
            echo -e ""
            echo -e "${C_GREEN}${messages["successfully_upgraded"]} ${LATEST_VERSION}$C_NORM"
            echo -e ""
            echo -e "${C_GREEN}${messages["installed_in"]} ${INSTALL_DIR}$C_NORM"
            echo -e ""
            ls -l --color {$DOWNLOAD_FILE,${DOWNLOAD_FILE}.DIGESTS.txt,dash-cli,dashd,dash-qt,dash*$LATEST_VERSION}
            echo -e ""

            quit
        else
            echo -e "${C_RED}${messages["dash_version"]} $CURRENT_VERSION ${messages["is_not_uptodate"]} ($LATEST_VERSION) ${messages["exiting"]}$C_NORM"
        fi

    else
        echo -e ""
        echo -e "${C_GREEN}${messages["dash_version"]} $CURRENT_VERSION ${messages["is_uptodate"]} ${messages["exiting"]}$C_NORM"
    fi

    exit 0
}

install_dashd(){

    INSTALL_DIR=$HOME/.dashcore
    DASH_CLI="$INSTALL_DIR/dash-cli"

    if [ -e $INSTALL_DIR ] ; then
        die "\n - ${messages["preexisting_dir"]} $INSTALL_DIR ${messages["found"]} ${messages["run_reinstall"]} ${messages["exiting"]}"
    fi

    if [ -z "$UNATTENDED" ] ; then
        pending "${messages["download"]} $DOWNLOAD_URL\n${messages["and_install_to"]} $INSTALL_DIR?"
    else
        echo -e "$C_GREEN*** UNATTENDED MODE ***$C_NORM"
    fi

    if [ -z "$UNATTENDED" ] ; then
        if ! confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
            echo -e "${C_RED}${messages["exiting"]}$C_NORM"
            echo ""
            exit 0
        fi
    fi

    get_public_ips
    # prompt for ipv4 or ipv6 install
#    if [ ! -z "$PUBLIC_IPV6" ] && [ ! -z "$PUBLIC_IPV4" ]; then
#        pending " --- " ; echo
#        pending " - ${messages["prompt_ipv4_ipv6"]}"
#        if confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
#            USE_IPV6=1
#        fi
#    fi

    echo ""

    # prep it ----------------------------------------------------------------

    mkdir -p $INSTALL_DIR

    if [ ! -e $INSTALL_DIR/dash.conf ] ; then
        pending " --> ${messages["creating"]} dash.conf... "

        IPADDR=$PUBLIC_IPV4
#        if [ ! -z "$USE_IPV6" ]; then
#            IPADDR='['$PUBLIC_IPV6']'
#        fi
        RPCUSER=`echo $(dd if=/dev/urandom bs=32 count=1 2>/dev/null) | sha256sum | awk '{print $1}'`
        RPCPASS=`echo $(dd if=/dev/urandom bs=32 count=1 2>/dev/null) | sha256sum | awk '{print $1}'`
        while read; do
            eval echo "$REPLY"
        done < $DASHMAN_GITDIR/.dash.conf.template > $INSTALL_DIR/dash.conf
        ok "${messages["done"]}"
    fi

    # push it ----------------------------------------------------------------

    cd $INSTALL_DIR

    # pull it ----------------------------------------------------------------

    pending " --> ${messages["downloading"]} ${DOWNLOAD_URL}... "
    tput sc
    echo -e "$C_CYAN"
    $wget_cmd -O - $DOWNLOAD_URL | pv -trep -s28787607 -w80 -N wallet > $DOWNLOAD_FILE
    $wget_cmd -O - https://github.com/dashpay/dash/releases/download/v$LATEST_VERSION/SHA256SUMS.asc | pv -trep -w80 -N checksums > ${DOWNLOAD_FILE}.DIGESTS.txt
    echo -ne "$C_NORM"
    clear_n_lines 2
    tput rc
    clear_n_lines 3
    if [ ! -e $DOWNLOAD_FILE ] ; then
        echo -e "${C_RED}error ${messages["downloading"]} file"
        echo -e "tried to get $DOWNLOAD_URL$C_NORM"
        exit 1
    else
        ok ${messages["done"]}
    fi

    # prove it ---------------------------------------------------------------

    pending " --> ${messages["checksumming"]} ${DOWNLOAD_FILE}... "
    SHA256SUM=$( sha256sum $DOWNLOAD_FILE )
    #MD5SUM=$( md5sum $DOWNLOAD_FILE )
    SHA256PASS=$( grep $SHA256SUM ${DOWNLOAD_FILE}.DIGESTS.txt | wc -l )
    #MD5SUMPASS=$( grep $MD5SUM ${DOWNLOAD_FILE}.DIGESTS.txt | wc -l )
    if [ $SHA256PASS -lt 1 ] ; then
        echo -e " ${C_RED} SHA256 ${messages["checksum"]} ${messages["FAILED"]} ${messages["try_again_later"]} ${messages["exiting"]}$C_NORM"

        exit 1
    fi
    #if [ $MD5SUMPASS -lt 1 ] ; then
    #    echo -e " ${C_RED} MD5 ${messages["checksum"]} ${messages["FAILED"]} ${messages["try_again_later"]} ${messages["exiting"]}$C_NORM"
    #    exit 1
    #fi
    ok "${messages["done"]}"

    # produce it -------------------------------------------------------------

    pending " --> ${messages["unpacking"]} ${DOWNLOAD_FILE}... " && \
    tar zxf $DOWNLOAD_FILE && \
    ok "${messages["done"]}"

    # pummel it --------------------------------------------------------------

#    if [ $DASHD_RUNNING == 1 ]; then
#        pending " --> ${messages["stopping"]} dashd. ${messages["please_wait"]}"
#        $DASH_CLI stop >/dev/null 2>&1
#        sleep 15
#        killall -9 dashd dash-shutoff >/dev/null 2>&1
#        ok "${messages["done"]}"
#    fi

    # prune it ---------------------------------------------------------------

#    pending " --> ${messages["removing_old_version"]}"
#    rm -f \
#        banlist.dat \
#        budget.dat \
#        debug.log \
#        fee_estimates.dat \
#        governance.dat \
#        mncache.dat \
#        mnpayments.dat \
#        netfulfilled.dat \
#        peers.dat \
#        dashd \
#        dashd-$CURRENT_VERSION \
#        dash-qt \
#        dash-qt-$CURRENT_VERSION \
#        dash-cli \
#        dash-cli-$CURRENT_VERSION
#    ok "${messages["done"]}"

    # place it ---------------------------------------------------------------

    mv $TARDIR/bin/dashd dashd-$LATEST_VERSION
    mv $TARDIR/bin/dash-cli dash-cli-$LATEST_VERSION
    if [ $PLATFORM != 'armv7l' ];then
        mv $TARDIR/bin/dash-qt dash-qt-$LATEST_VERSION
    fi
    ln -s dashd-$LATEST_VERSION dashd
    ln -s dash-cli-$LATEST_VERSION dash-cli
    if [ $PLATFORM != 'armv7l' ];then
        ln -s dash-qt-$LATEST_VERSION dash-qt
    fi

    # permission it ----------------------------------------------------------

    if [ ! -z "$SUDO_USER" ]; then
        chown -h $SUDO_USER:$SUDO_USER {$DOWNLOAD_FILE,${DOWNLOAD_FILE}.DIGESTS.txt,dash-cli,dashd,dash-qt,dash*$LATEST_VERSION}
    fi

    # purge it ---------------------------------------------------------------

    rm -rf dash-0.12.0
    rm -rf dashcore-0.12.1*
    rm -rf dashcore-0.12.2*
    rm -rf dashcore-0.12.3*
    rm -rf $TARDIR

    # preload it -------------------------------------------------------------

    pending " --> ${messages["bootstrapping"]} blockchain. ${messages["please_wait"]}\n"
    pending "  --> ${messages["downloading"]} bootstrap... "
    BOOSTRAP_LINKS='https://raw.githubusercontent.com/UdjinM6/dash-bootstrap/master/links-mainnet.md'
    wget --no-check-certificate -q $BOOSTRAP_LINKS -O - | grep 'bootstrap\.dat\.zip' | grep 'sha256\.txt' > links.md
    MAINNET_BOOTSTRAP_FILE_1=$(head -1 links.md | awk '{print $9}' | sed 's/.*\(http.*\.zip\).*/\1/')
    MAINNET_BOOTSTRAP_FILE_1_SIZE=$(head -1 links.md | awk '{print $10}' | sed 's/[()]//g')
    MAINNET_BOOTSTRAP_FILE_1_SIZE_M=$(( $(echo $MAINNET_BOOTSTRAP_FILE_1_SIZE | sed -e 's/[^0-9]//g') * 100 ))
    MAINNET_BOOTSTRAP_FILE_2=$(head -3 links.md | tail -1 | awk '{print $9}' | sed 's/.*\(http.*\.zip\).*/\1/')
    pending " $MAINNET_BOOTSTRAP_FILE_1_SIZE... "
    tput sc
    echo -e "$C_CYAN"
    $wget_cmd -O - $MAINNET_BOOTSTRAP_FILE_1 | pv -trepa -s${MAINNET_BOOTSTRAP_FILE_1_SIZE_M}m -w80 -N bootstrap > ${MAINNET_BOOTSTRAP_FILE_1##*/}
    MAINNET_BOOTSTRAP_FILE=${MAINNET_BOOTSTRAP_FILE_1##*/}
    if [ ! -s $MAINNET_BOOTSTRAP_FILE ]; then
        rm $MAINNET_BOOTSTRAP_FILE
        $wget_cmd -O - $MAINNET_BOOTSTRAP_FILE_2 | pv -trepa -s${MAINNET_BOOTSTRAP_FILE_1_SIZE_M}m -w80 -N bootstrap > ${MAINNET_BOOTSTRAP_FILE_2##*/}
        MAINNET_BOOTSTRAP_FILE=${MAINNET_BOOTSTRAP_FILE_2##*/}
    fi
    echo -ne "$C_NORM"
    clear_n_lines 1
    tput rc
    tput cuu 2
    if [ ! -s $MAINNET_BOOTSTRAP_FILE ]; then
        # TODO i18n
        err " bootstrap download failed. skipping."
    else
        ok "${messages["done"]}"
        pending "  --> ${messages["unzipping"]} bootstrap... "
        tput sc
        echo -e "$C_CYAN"
        BOOTSTRAP_SIZE_M=$(( $(unzip -l ${MAINNET_BOOTSTRAP_FILE##*/} | grep -v zip | grep bootstrap.dat | awk '{print $1}') / 1024 / 1024 ))
        unzip -qp ${MAINNET_BOOTSTRAP_FILE##*/} | pv -trep -s${BOOTSTRAP_SIZE_M}m -w80 -N 'unpacking bootstrap' > bootstrap.dat
        echo -ne "$C_NORM"
        clear_n_lines 1
        tput rc
        tput cuu 2
        ok "${messages["done"]}"
        rm -f links.md bootstrap.dat*.zip
    fi

    # punch it ---------------------------------------------------------------

    pending " --> ${messages["launching"]} dashd... "
    $INSTALL_DIR/dashd > /dev/null
    DASHD_RUNNING=1
    ok "${messages["done"]}"

    # probe it ---------------------------------------------------------------

    pending " --> ${messages["waiting_for_dashd_to_respond"]}"
    echo -en "${C_YELLOW}"
    while [ $DASHD_RUNNING == 1 ] && [ $DASHD_RESPONDING == 0 ]; do
        echo -n "."
        _check_dashd_state
        sleep 2
    done
    if [ $DASHD_RUNNING == 0 ]; then
        die "\n - dashd unexpectedly quit. ${messages["exiting"]}"
    fi
    ok "${messages["done"]}"

    # path it ----------------------------------------------------------------

    pending " --> adding $INSTALL_DIR PATH to ~/.bash_aliases ... "
    if [ ! -f ~/.bash_aliases ]; then touch ~/.bash_aliases ; fi
    sed -i.bak -e '/dashman_env/d' ~/.bash_aliases
    echo "export PATH=$INSTALL_DIR:\$PATH ; # dashman_env" >> ~/.bash_aliases
    ok "${messages["done"]}"


    # poll it ----------------------------------------------------------------

    _get_versions

    # pass or punt -----------------------------------------------------------

    if [ $LATEST_VERSION == $CURRENT_VERSION ]; then
        echo -e ""
        echo -e "${C_GREEN}dash ${LATEST_VERSION} ${messages["successfully_installed"]}$C_NORM"

        echo -e ""
        echo -e "${C_GREEN}${messages["installed_in"]} ${INSTALL_DIR}$C_NORM"
        echo -e ""
        ls -l --color {$DOWNLOAD_FILE,${DOWNLOAD_FILE}.DIGESTS.txt,dash-cli,dashd,dash-qt,dash*$LATEST_VERSION}
        echo -e ""

        if [ ! -z "$SUDO_USER" ]; then
            echo -e "${C_GREEN}Symlinked to: ${LINK_TO_SYSTEM_DIR}$C_NORM"
            echo -e ""
            ls -l --color $LINK_TO_SYSTEM_DIR/{dashd,dash-cli}
            echo -e ""
        fi

    else
        echo -e "${C_RED}${messages["dash_version"]} $CURRENT_VERSION ${messages["is_not_uptodate"]} ($LATEST_VERSION) ${messages["exiting"]}$C_NORM"
        exit 1
    fi

}

_get_dashd_proc_status(){
    DASHD_HASPID=0
    if [ -e $INSTALL_DIR/dashd.pid ] ; then
        DASHD_HASPID=`ps --no-header \`cat $INSTALL_DIR/dashd.pid 2>/dev/null\` | wc -l`;
    else
        DASHD_HASPID=$(pidof dashd)
        if [ $? -gt 0 ]; then
            DASHD_HASPID=0
        fi
    fi
    DASHD_PID=$(pidof dashd)
}

get_dashd_status(){

    _get_dashd_proc_status

    DASHD_UPTIME=$(ps -p $DASHD_PID -o etime= 2>/dev/null | sed -e 's/ //g')
    DASHD_UPTIME_TIMES=$(echo "$DASHD_UPTIME" | perl -ne 'chomp ; s/-/:/ ; print join ":", reverse split /:/' 2>/dev/null )
    DASHD_UPTIME_SECS=$( echo "$DASHD_UPTIME_TIMES" | cut -d: -f1 )
    DASHD_UPTIME_MINS=$( echo "$DASHD_UPTIME_TIMES" | cut -d: -f2 )
    DASHD_UPTIME_HOURS=$( echo "$DASHD_UPTIME_TIMES" | cut -d: -f3 )
    DASHD_UPTIME_DAYS=$( echo "$DASHD_UPTIME_TIMES" | cut -d: -f4 )
    if [ -z "$DASHD_UPTIME_DAYS" ]; then DASHD_UPTIME_DAYS=0 ; fi
    if [ -z "$DASHD_UPTIME_HOURS" ]; then DASHD_UPTIME_HOURS=0 ; fi
    if [ -z "$DASHD_UPTIME_MINS" ]; then DASHD_UPTIME_MINS=0 ; fi
    if [ -z "$DASHD_UPTIME_SECS" ]; then DASHD_UPTIME_SECS=0 ; fi

    DASHD_LISTENING=`netstat -nat | grep LIST | grep 9999 | wc -l`;
    DASHD_CONNECTIONS=`netstat -nat | grep ESTA | grep 9999 | wc -l`;
    DASHD_CURRENT_BLOCK=`$DASH_CLI getblockcount 2>/dev/null`
    if [ -z "$DASHD_CURRENT_BLOCK" ] ; then DASHD_CURRENT_BLOCK=0 ; fi
    DASHD_GETINFO=`$DASH_CLI getinfo 2>/dev/null`;
    DASHD_DIFFICULTY=$(echo "$DASHD_GETINFO" | grep difficulty | awk '{print $2}' | sed -e 's/[",]//g')

    WEB_BLOCK_COUNT_CHAINZ=`$curl_cmd https://chainz.cryptoid.info/dash/api.dws?q=getblockcount`;
    if [ -z "$WEB_BLOCK_COUNT_CHAINZ" ]; then
        WEB_BLOCK_COUNT_CHAINZ=0
    fi

    WEB_BLOCK_COUNT_DQA=`$curl_cmd https://explorer.dash.org/chain/Dash/q/getblockcount`;
    if [ -z "$WEB_BLOCK_COUNT_DQA" ]; then
        WEB_BLOCK_COUNT_DQA=0
    fi

    WEB_DASHWHALE=`$curl_cmd https://www.dashcentral.org/api/v1/public`;
    if [ -z "$WEB_DASHWHALE" ]; then
        sleep 3
        WEB_DASHWHALE=`$curl_cmd https://www.dashcentral.org/api/v1/public`;
    fi

    WEB_DASHWHALE_JSON_TEXT=$(echo $WEB_DASHWHALE | python -m json.tool)
    WEB_BLOCK_COUNT_DWHALE=$(echo "$WEB_DASHWHALE_JSON_TEXT" | grep consensus_blockheight | awk '{print $2}' | sed -e 's/[",]//g')

    WEB_ME=`$curl_cmd https://www.masternode.me/data/block_state.txt 2>/dev/null`;
    if [[ -z "$WEB_ME" ]] || [[ $(echo "$WEB_ME" | grep cloudflare | wc -l) -gt 0 ]]; then
        WEB_ME=`$curl_cmd https://stats.masternode.me/data/block_state.txt 2>/dev/null`;
    fi
    WEB_BLOCK_COUNT_ME=$( echo $WEB_ME | awk '{print $1}')
    WEB_ME_FORK_DETECT=$( echo $WEB_ME | grep 'fork detected' | wc -l )

    WEB_ME=$(echo $WEB_ME | sed -s "s/no forks detected/${messages["no_forks_detected"]}/")

    CHECK_SYNC_AGAINST_HEIGHT=$(echo "$WEB_BLOCK_COUNT_CHAINZ $WEB_BLOCK_COUNT_ME $WEB_BLOCK_COUNT_DQA $WEB_BLOCK_COUNT_DWHALE" | tr " " "\n" | sort -rn | head -1)

    DASHD_SYNCED=0
    if [ $CHECK_SYNC_AGAINST_HEIGHT -ge $DASHD_CURRENT_BLOCK ] && [ $(($CHECK_SYNC_AGAINST_HEIGHT - 5)) -lt $DASHD_CURRENT_BLOCK ];then
        DASHD_SYNCED=1
    fi

    DASHD_CONNECTED=0
    if [ $DASHD_CONNECTIONS -gt 0 ]; then DASHD_CONNECTED=1 ; fi

    DASHD_UP_TO_DATE=0
    if [ $LATEST_VERSION == $CURRENT_VERSION ]; then
        DASHD_UP_TO_DATE=1
    fi

    get_public_ips

    MASTERNODE_BIND_IP=$PUBLIC_IPV4
    PUBLIC_PORT_CLOSED=$( timeout 2 nc -4 -z $PUBLIC_IPV4 9999 2>&1 >/dev/null; echo $? )
#    if [ $PUBLIC_PORT_CLOSED -ne 0 ] && [ ! -z "$PUBLIC_IPV6" ]; then
#        PUBLIC_PORT_CLOSED=$( timeout 2 nc -6 -z $PUBLIC_IPV6 9999 2>&1 >/dev/null; echo $? )
#        if [ $PUBLIC_PORT_CLOSED -eq 0 ]; then
#            MASTERNODE_BIND_IP=$PUBLIC_IPV6
#        fi
#    else
#        MASTERNODE_BIND_IP=$PUBLIC_IPV4
#    fi

    # masternode (remote!) specific

    MN_PROTX_RAW="$($DASH_CLI protx list valid 1 2>&1)"
    MN_PROTX_RECORD=`echo "$MN_PROTX_RAW" | grep -w -B6 -A19 $MASTERNODE_BIND_IP:9999 | sed -e 's/:9999/~9999/' -e 's/[":,{}]//g' -e 's/^ \+//' -e 's/ \+$//' -e 's/~9999/:9999/' -e '/^$/d' -e '/^[^ ]\+$/d'`
    MN_PROTX_QUEUE=`echo "$MN_PROTX_RAW" | egrep '(proTxHash|lastPaidHeight|PoSeRevivedHeight|registeredHeight)' | sed -e 's/[":,{}]//g' -e 's/^ \+//' -e 's/ \+$//' -e '/^$/d' -e '/^[^ ]\+$/d' | sed -e 'N;s/\n/ /' | sed -e 'N;s/\n/ /' | awk ' \
{
    if ($8 > $6) {
        print $8 " " $_
    }
    else if ($6 == 0) {
        print $4 " " $_
    }
    else {
        print $6 " " $_
    }
}' | sort -k1,1nr`
    MN_PROTX_QUEUE_LENGTH=$(echo "$MN_PROTX_QUEUE" | wc -l)

    MN_PROTX_HASH=''
    MN_PROTX_CONFIRMATIONS=''
    MN_PROTX_REGD_HEIGHT=''
    MN_PROTX_LAST_PAID_HEIGHT=''
    MN_PROTX_COLL_HASH=''
    MN_PROTX_COLL_IDX=''
    MN_PROTX_COLL_ADDY=''
    MN_PROTX_OPER_REWARD=''
    MN_PROTX_POSE_PENALTY=''
    MN_PROTX_POSE_REVIVED_HEIGHT=''
    MN_PROTX_POSE_BAN_HEIGHT=''
    MN_PROTX_SERVICE=''
    MN_PROTX_OWNER_ADDRESS=''
    MN_PROTX_VOTER_ADDRESS=''
    MN_PROTX_PAYOUT_ADDRESS=''
    MN_PROTX_OPER_PUBKEY=''
    MN_PROTX_QUEUE_POSITION=0
    MN_PROTX_SERVICE_VALID=0

    MN_CONF_ENABLED=$( egrep -s '^[^#]*\s*masternodeblsprivkey\s*=' $HOME/.dash{,core}/dash.conf | wc -l 2>/dev/null)
    #MN_STARTED=`$DASH_CLI masternode status 2>&1 | grep 'successfully started' | wc -l`
    MN_REGISTERED=0
    [[ -z "$MN_PROTX_RECORD" ]] || MN_REGISTERED=1

    if [ $MN_REGISTERED -gt 0 ]; then
        MN_PROTX_HASH=$(echo "$MN_PROTX_RECORD" | grep proTxHash | awk '{print $2}')
        MN_PROTX_CONFIRMATIONS=$(echo "$MN_PROTX_RECORD" | grep confirmations | awk '{print $2}')
        MN_PROTX_REGD_HEIGHT=$(echo "$MN_PROTX_RECORD" | grep registeredHeight | awk '{print $2}')
        MN_PROTX_LAST_PAID_HEIGHT=$(echo "$MN_PROTX_RECORD" | grep lastPaidHeight | awk '{print $2}')
        MN_PROTX_COLL_HASH=$(echo "$MN_PROTX_RECORD" | grep collateralHash | awk '{print $2}')
        MN_PROTX_COLL_IDX=$(echo "$MN_PROTX_RECORD" | grep collateralIndex | awk '{print $2}')
        MN_PROTX_COLL_ADDY=$(echo "$MN_PROTX_RECORD" | grep collateralAddress | awk '{print $2}')
        MN_PROTX_OPER_REWARD=$(echo "$MN_PROTX_RECORD" | grep operatorReward | awk '{print $2}')
        MN_PROTX_POSE_PENALTY=$(echo "$MN_PROTX_RECORD" | grep PoSePenalty | awk '{print $2}')
        MN_PROTX_POSE_REVIVED_HEIGHT=$(echo "$MN_PROTX_RECORD" | grep PoSeRevivedHeight | awk '{print $2}')
        MN_PROTX_POSE_BAN_HEIGHT=$(echo "$MN_PROTX_RECORD" | grep PoSeBanHeight | awk '{print $2}')
        MN_PROTX_SERVICE=$(echo "$MN_PROTX_RECORD" | grep service | awk '{print $2}')
        MN_PROTX_OWNER_ADDRESS=$(echo "$MN_PROTX_RECORD" | grep ownerAddress | awk '{print $2}')
        MN_PROTX_VOTER_ADDRESS=$(echo "$MN_PROTX_RECORD" | grep votingAddress | awk '{print $2}')
        MN_PROTX_PAYOUT_ADDRESS=$(echo "$MN_PROTX_RECORD" | grep payoutAddress | awk '{print $2}')
        MN_PROTX_OPER_PUBKEY=$(echo "$MN_PROTX_RECORD" | grep pubKeyOperator | awk '{print $2}')

        MN_PROTX_SERVICE_IP=$(echo "$MN_PROTX_SERVICE" | sed -e 's/:.*//' )

        if [ "$MASTERNODE_BIND_IP" == "$MN_PROTX_SERVICE_IP" ]; then
            MN_PROTX_SERVICE_VALID=1
        fi
        MN_PROTX_QUEUE_POSITION=$(echo "$MN_PROTX_QUEUE" | grep -A9999999 $MN_PROTX_HASH | wc -l)
    fi

    MN_QUEUE_IN_SELECTION=0
    MN_QUEUE_LENGTH=0
    MN_QUEUE_POSITION=0


    NOW=`date +%s`
    MN_LIST="$(cache_output /tmp/mnlist_cache '$DASH_CLI masternodelist full 2>/dev/null')"

    MN_STATUS=$( grep $MASTERNODE_BIND_IP /tmp/mnlist_cache | sed -e 's/"//g' | awk '{print $2}' )
    MN_VISIBLE=$( test "$MN_STATUS" && echo 1 || echo 0 )
    MN_ENABLED=$( cat /tmp/mnlist_cache | grep -c ENABLED )
    MN_UNHEALTHY=$( cat /tmp/mnlist_cache | grep -c EXPIRED )
    MN_TOTAL=$(( $MN_ENABLED + $MN_UNHEALTHY ))

    MN_SYNC_STATUS=$( $DASH_CLI mnsync status )
    MN_SYNC_ASSET=$(echo "$MN_SYNC_STATUS" | grep 'AssetName' | awk '{print $2}' | sed -e 's/[",]//g' )
    MN_SYNC_COMPLETE=$(echo "$MN_SYNC_STATUS" | grep 'IsSynced' | grep 'true' | wc -l)

    if [ $MN_VISIBLE -gt 0 ]; then
        MN_QUEUE_LENGTH=$MN_ENABLED
        MN_QUEUE_POSITION=$(echo "$SORTED_MN_LIST" | grep ENABLED | grep -A9999999 $MASTERNODE_BIND_IP | wc -l)
        if [ $MN_QUEUE_POSITION -gt 0 ]; then
            MN_QUEUE_IN_SELECTION=$(( $MN_QUEUE_POSITION <= $(( $MN_QUEUE_LENGTH / 10 )) ))
        fi
    fi

    # sentinel checks
    if [ -e $INSTALL_DIR/sentinel ]; then

        SENTINEL_INSTALLED=0
        SENTINEL_PYTEST=0
        SENTINEL_CRONTAB=0
        SENTINEL_LAUNCH_OUTPUT=""
        SENTINEL_LAUNCH_OK=-1

        cd $INSTALL_DIR/sentinel
        SENTINEL_INSTALLED=$( ls -l bin/sentinel.py | wc -l )
        SENTINEL_PYTEST=$( venv/bin/py.test test 2>&1 > /dev/null ; echo $? )
        SENTINEL_CRONTAB=$( crontab -l | grep sentinel | grep -v '^#' | wc -l )
        SENTINEL_LAUNCH_OUTPUT=$( venv/bin/python bin/sentinel.py 2>&1 )
        if [ -z "$SENTINEL_LAUNCH_OUTPUT" ] ; then
            SENTINEL_LAUNCH_OK=$?
        fi
        cd - > /dev/null
    fi

    if [ $MN_CONF_ENABLED -gt 0 ] ; then
        WEB_NINJA_API=$($curl_cmd "https://www.dashninja.pl/api/masternodes?ips=\[\"${MASTERNODE_BIND_IP}:9999\"\]&portcheck=1&balance=1")
        if [ -z "$WEB_NINJA_API" ]; then
            sleep 2
            # downgrade connection to support distros with stale nss libraries
            WEB_NINJA_API=$($curl_cmd --ciphers rsa_3des_sha "https://www.dashninja.pl/api/masternodes?ips=\[\"${MASTERNODE_BIND_IP}:9999\"\]&portcheck=1&balance=1")
        fi

        WEB_NINJA_JSON_TEXT=$(echo $WEB_NINJA_API | python -m json.tool)
        WEB_NINJA_SEES_OPEN=$(echo "$WEB_NINJA_JSON_TEXT" | grep '"Result"' | grep open | wc -l)
        WEB_NINJA_MN_ADDY=$(echo "$WEB_NINJA_JSON_TEXT" | grep MasternodePubkey | awk '{print $2}' | sed -e 's/[",]//g')
        WEB_NINJA_MN_VIN=$(echo "$WEB_NINJA_JSON_TEXT" | grep MasternodeOutputHash | awk '{print $2}' | sed -e 's/[",]//g')
        WEB_NINJA_MN_VIDX=$(echo "$WEB_NINJA_JSON_TEXT" | grep MasternodeOutputIndex | awk '{print $2}' | sed -e 's/[",]//g')
        WEB_NINJA_MN_BALANCE=$(echo "$WEB_NINJA_JSON_TEXT" | grep Value | awk '{print $2}' | sed -e 's/[",]//g')
        WEB_NINJA_MN_LAST_PAID_TIME_EPOCH=$(echo "$WEB_NINJA_JSON_TEXT" | grep MNLastPaidTime | awk '{print $2}' | sed -e 's/[",]//g')
        WEB_NINJA_MN_LAST_PAID_AMOUNT=$(echo "$WEB_NINJA_JSON_TEXT" | grep MNLastPaidAmount | awk '{print $2}' | sed -e 's/[",]//g')
        WEB_NINJA_MN_LAST_PAID_BLOCK=$(echo "$WEB_NINJA_JSON_TEXT" | grep MNLastPaidBlock | awk '{print $2}' | sed -e 's/[",]//g')

        WEB_NINJA_LAST_PAYMENT_TIME=$(date -d @${WEB_NINJA_MN_LAST_PAID_TIME_EPOCH} '+%m/%d/%Y %H:%M:%S' 2>/dev/null)

        if [ ! -z "$WEB_NINJA_LAST_PAYMENT_TIME" ]; then
            local daysago=$(dateDiff -d now "$WEB_NINJA_LAST_PAYMENT_TIME")
            local hoursago=$(dateDiff -h now "$WEB_NINJA_LAST_PAYMENT_TIME")
            hoursago=$(( hoursago - (24 * daysago) ))
            WEB_NINJA_LAST_PAYMENT_TIME="$WEB_NINJA_LAST_PAYMENT_TIME ($daysago ${messages["days"]}, $hoursago ${messages["hours"]}${messages["ago"]})"

        fi

        WEB_NINJA_API_OFFLINE=0
        if [[ $(echo "$WEB_NINJA_API" | grep '"status":"ERROR"' | wc -l) > 0 ]];then
            WEB_NINJA_API_OFFLINE=1
        fi

    fi

}

date2stamp () {
    date --utc --date "$1" +%s
}

stamp2date (){
    date --utc --date "1970-01-01 $1 sec" "+%Y-%m-%d %T"
}

dateDiff (){
    case $1 in
        -s)   sec=1;      shift;;
        -m)   sec=60;     shift;;
        -h)   sec=3600;   shift;;
        -d)   sec=86400;  shift;;
        *)    sec=86400;;
    esac
    dte1=$(date2stamp $1)
    dte2=$(date2stamp "$2")
    diffSec=$((dte2-dte1))
    if ((diffSec < 0)); then abs=-1; else abs=1; fi
    echo $((diffSec/sec*abs))
}

get_host_status(){
    HOST_LOAD_AVERAGE=$(cat /proc/loadavg | awk '{print $1" "$2" "$3}')
    uptime=$(</proc/uptime)
    uptime=${uptime%%.*}
    HOST_UPTIME_DAYS=$(( uptime/60/60/24 ))
    HOSTNAME=$(hostname -f)
}


print_status() {

    DASHD_UPTIME_STRING="$DASHD_UPTIME_DAYS ${messages["days"]}, $DASHD_UPTIME_HOURS ${messages["hours"]}, $DASHD_UPTIME_MINS ${messages["mins"]}, $DASHD_UPTIME_SECS ${messages["secs"]}"

    pending "${messages["status_hostnam"]}" ; ok "$HOSTNAME"
    pending "${messages["status_uptimeh"]}" ; ok "$HOST_UPTIME_DAYS ${messages["days"]}, $HOST_LOAD_AVERAGE"
    pending "${messages["status_dashdip"]}" ; [ $MASTERNODE_BIND_IP != 'none' ] && ok "$MASTERNODE_BIND_IP" || err "$MASTERNODE_BIND_IP"
    pending "${messages["status_dashdve"]}" ; ok "$CURRENT_VERSION"
    pending "${messages["status_uptodat"]}" ; [ $DASHD_UP_TO_DATE -gt 0 ] && ok "${messages["YES"]}" || err "${messages["NO"]}"
    pending "${messages["status_running"]}" ; [ $DASHD_HASPID     -gt 0 ] && ok "${messages["YES"]}" || err "${messages["NO"]}"
    pending "${messages["status_uptimed"]}" ; [ $DASHD_RUNNING    -gt 0 ] && ok "$DASHD_UPTIME_STRING" || err "$DASHD_UPTIME_STRING"
    pending "${messages["status_drespon"]}" ; [ $DASHD_RUNNING    -gt 0 ] && ok "${messages["YES"]}" || err "${messages["NO"]}"
    pending "${messages["status_dlisten"]}" ; [ $DASHD_LISTENING  -gt 0 ] && ok "${messages["YES"]}" || err "${messages["NO"]}"
    pending "${messages["status_dconnec"]}" ; [ $DASHD_CONNECTED  -gt 0 ] && ok "${messages["YES"]}" || err "${messages["NO"]}"
    pending "${messages["status_dportop"]}" ; [ $PUBLIC_PORT_CLOSED  -lt 1 ] && ok "${messages["YES"]}" || err "${messages["NO"]}"
    pending "${messages["status_dconcnt"]}" ; [ $DASHD_CONNECTIONS   -gt 0 ] && ok "$DASHD_CONNECTIONS" || err "$DASHD_CONNECTIONS"
    pending "${messages["status_dblsync"]}" ; [ $DASHD_SYNCED     -gt 0 ] && ok "${messages["YES"]}" || err "${messages["NO"]}"
    pending "${messages["status_dbllast"]}" ; [ $DASHD_SYNCED     -gt 0 ] && ok "$DASHD_CURRENT_BLOCK" || err "$DASHD_CURRENT_BLOCK"
    pending "${messages["status_webchai"]}" ; [ $WEB_BLOCK_COUNT_CHAINZ -gt 0 ] && ok "$WEB_BLOCK_COUNT_CHAINZ" || err "$WEB_BLOCK_COUNT_CHAINZ"
    pending "${messages["status_webdark"]}" ; [ $WEB_BLOCK_COUNT_DQA    -gt 0 ] && ok "$WEB_BLOCK_COUNT_DQA" || err "$WEB_BLOCK_COUNT_DQA"
    pending "${messages["status_webdash"]}" ; [ $WEB_BLOCK_COUNT_DWHALE -gt 0 ] && ok "$WEB_BLOCK_COUNT_DWHALE" || err "$WEB_BLOCK_COUNT_DWHALE"
    pending "${messages["status_webmast"]}" ; [ $WEB_ME_FORK_DETECT -gt 0 ] && err "$WEB_ME" || ok "$WEB_ME"
    pending "${messages["status_dcurdif"]}" ; ok "$DASHD_DIFFICULTY"
    if [ $DASHD_RUNNING -gt 0 ] && [ $MN_CONF_ENABLED -gt 0 ] ; then
    #pending "${messages["status_mnstart"]}" ; [ $MN_STARTED -gt 0  ] && ok "${messages["YES"]}" || err "${messages["NO"]}"
    pending "${messages["status_mnregis"]}" ; [ $MN_REGISTERED -gt 0 ] && ok "${messages["YES"]}" || err "${messages["NO"]}"
    pending "${messages["status_mnvislo"]}" ; [ $MN_VISIBLE -gt 0  ] && ok "${messages["YES"]}" || err "${messages["NO"]}"
        if [ $WEB_NINJA_API_OFFLINE -eq 0 ]; then
    pending "${messages["status_mnvisni"]}" ; [ $WEB_NINJA_SEES_OPEN -gt 0  ] && ok "${messages["YES"]}" || err "${messages["NO"]}"
    pending "${messages["status_mnaddre"]}" ; ok "$WEB_NINJA_MN_ADDY"
    pending "${messages["status_mnfundt"]}" ; ok "$WEB_NINJA_MN_VIN-$WEB_NINJA_MN_VIDX"
    pending "${messages["status_mnqueue"]}" ; ok "$MN_PROTX_QUEUE_POSITION/$MN_PROTX_QUEUE_LENGTH"
    pending "  masternode mnsync state    : " ; [ ! -z "$MN_SYNC_ASSET" ] && ok "$MN_SYNC_ASSET" || ""
    pending "  masternode network state   : " ; [ "$MN_STATUS" == "ENABLED" ] && ok "$MN_STATUS" || highlight "$MN_STATUS"

    pending "${messages["status_mnlastp"]}" ; [ ! -z "$WEB_NINJA_MN_LAST_PAID_AMOUNT" ] && \
        ok "$WEB_NINJA_MN_LAST_PAID_AMOUNT in $WEB_NINJA_MN_LAST_PAID_BLOCK on $WEB_NINJA_LAST_PAYMENT_TIME " || warn 'never'
    pending "${messages["status_mnbalan"]}" ; [ ! -z "$WEB_NINJA_MN_BALANCE" ] && ok "$WEB_NINJA_MN_BALANCE" || warn '0'

    pending "    sentinel installed       : " ; [ $SENTINEL_INSTALLED -gt 0  ] && ok "${messages["YES"]}" || err "${messages["NO"]}"
    pending "    sentinel tests passed    : " ; [ $SENTINEL_PYTEST    -eq 0  ] && ok "${messages["YES"]}" || err "${messages["NO"]}"
    pending "    sentinel crontab enabled : " ; [ $SENTINEL_CRONTAB   -gt 0  ] && ok "${messages["YES"]}" || err "${messages["NO"]}"
    pending "    sentinel online          : " ; [ $SENTINEL_LAUNCH_OK -eq 0  ] && ok "${messages["YES"]}" || ([ $MN_SYNC_COMPLETE -eq 0 ] && warn "${messages["NO"]} - sync incomplete") || err "${messages["NO"]}"

        else
    err     "  dashninja api offline        " ;
        fi
    if [ $MN_REGISTERED -gt 0 ] ; then
        pending " protx registration hash     : " ; ok "$MN_PROTX_HASH"
        pending " protx registered service    : " ; [ $MN_PROTX_SERVICE_VALID  -eq 1 ] && ok "$MN_PROTX_SERVICE" || err "$MN_PROTX_SERVICE"
        pending " protx registered address    : " ; ok "$MN_PROTX_COLL_ADDY"
        pending " protx registered collateral : " ; ok "$MN_PROTX_COLL_HASH-$MN_PROTX_COLL_IDX"
        pending " protx registered at block   : " ; ok "$MN_PROTX_REGD_HEIGHT"
        pending " protx confirmations         : " ; ok "$MN_PROTX_CONFIRMATIONS"
        pending " protx last paid block       : " ; ok "$MN_PROTX_LAST_PAID_HEIGHT"
        pending " protx owner address         : " ; ok "$MN_PROTX_OWNER_ADDRESS"
        pending " protx voter address         : " ; ok "$MN_PROTX_VOTER_ADDRESS"
        pending " protx payout address        : " ; ok "$MN_PROTX_PAYOUT_ADDRESS"
        pending " protx operator reward       : " ; ok "$MN_PROTX_OPER_REWARD"
        pending " protx operator pubkey       : " ; ok "$MN_PROTX_OPER_PUBKEY"
        pending " protx pose score            : " ; [ $MN_PROTX_POSE_PENALTY  -gt 0 ] && err "$MN_PROTX_POSE_PENALTY" || ok "$MN_PROTX_POSE_PENALTY"
        #    MN_PROTX_POSE_REVIVED_HEIGHT=$(echo "$MN_PROTX_RECORD" | grep PoSeRevivedHeight | awk '{print $2}')
        #    MN_PROTX_POSE_BAN_HEIGHT=$(echo "$MN_PROTX_RECORD" | grep PoSeBanHeight | awk '{print $2}')
    fi

    else
    pending "${messages["status_mncount"]}" ; [ $MN_TOTAL            -gt 0 ] && ok "$MN_TOTAL" || err "$MN_TOTAL"
    fi
}

show_message_configure() {
    echo
    ok "${messages["to_enable_masternode"]}"
    ok "${messages["uncomment_conf_lines"]}"
    echo
         pending "    $HOME/.dashcore/dash.conf" ; echo
    echo
    echo -e "$C_GREEN install sentinel$C_NORM"
    echo
    echo -e "    ${C_YELLOW}dashman install sentinel$C_NORM"
    echo
    echo -e "$C_GREEN ${messages["then_run"]}$C_NORM"
    echo
    echo -e "    ${C_YELLOW}dashman restart now$C_NORM"
    echo
}

get_public_ips() {
    PUBLIC_IPV4=$($curl_cmd -4 https://icanhazip.com/)
#    PUBLIC_IPV6=$($curl_cmd -6 https://icanhazip.com/)
#    if [ -z "$PUBLIC_IPV4" ] && [ -z "$PUBLIC_IPV6" ]; then
    if [ -z "$PUBLIC_IPV4" ]; then

        # try http
        PUBLIC_IPV4=$($curl_cmd -4 http://icanhazip.com/)
#        PUBLIC_IPV6=$($curl_cmd -6 http://icanhazip.com/)

#        if [ -z "$PUBLIC_IPV4" ] && [ -z "$PUBLIC_IPV6" ]; then
        if [ -z "$PUBLIC_IPV4" ]; then
            sleep 3
            err "  --> ${messages["err_failed_ip_resolve"]}"
            # try again
            get_public_ips
        fi

    fi
}

cat_until() {
    PATTERN=$1
    FILE=$2
    while read; do
        if [[ "$REPLY" =~ $PATTERN ]]; then
            return
        else
            echo "$REPLY"
        fi
    done < $FILE
}

install_sentinel() {



    # push it ----------------------------------------------------------------

    cd $INSTALL_DIR

    # pummel it --------------------------------------------------------------

    rm -rf sentinel

    # pull it ----------------------------------------------------------------

    pending "  --> ${messages["downloading"]} sentinel... "

    git clone -q https://github.com/dashpay/sentinel.git

    ok "${messages["done"]}"

    # prep it ----------------------------------------------------------------

    pending "  --> installing dependencies... "
    echo

    cd sentinel

    pending "   --> virtualenv init... "
    virtualenv venv 2>&1 > /dev/null;
    if [[ $? -gt 0 ]];then
        err "  --> virtualenv initialization failed"
        pending "  when running: " ; echo
        echo -e "    ${C_YELLOW}virtualvenv venv$C_NORM"
        quit
    fi
    ok "${messages["done"]}"

    pending "   --> pip modules... "
    venv/bin/pip install -r requirements.txt 2>&1 > /dev/null;
    if [[ $? -gt 0 ]];then
        err "  --> pip install failed"
        pending "  when running: " ; echo
        echo -e "    ${C_YELLOW}venv/bin/pip install -r requirements.txt$C_NORM"
        quit
    fi
    ok "${messages["done"]}"

    pending "  --> testing installation... "
    venv/bin/py.test ./test/ 2>&1>/dev/null; 
    if [[ $? -gt 0 ]];then
        err "  --> sentinel tests failed"
        pending "  when running: " ; echo
        echo -e "    ${C_YELLOW}venv/bin/py.test ./test/$C_NORM"
        quit
    fi
    ok "${messages["done"]}"

    pending "  --> installing crontab... "
    (crontab -l 2>/dev/null | grep -v sentinel.py ; echo "* * * * * cd $INSTALL_DIR/sentinel && venv/bin/python bin/sentinel.py  2>&1 >> sentinel-cron.log") | crontab -
    ok "${messages["done"]}"

    cd ..

}
