# vim: set filetype=sh

# .dashman.functions - common functions and variables

# Copyright (c) 2015 moocowmoo - moocowmoo@masternode.me

# variables are for putting things in ----------------------------------------

C_RED="\e[31m"
C_YELLOW="\e[33m"
C_GREEN="\e[32m"
C_CYAN="\e[36m"
C_NORM="\e[0m"

DOWNLOAD_PAGE='https://www.dashpay.io/downloads/'

DASHD_RUNNING=0
DASHMAN_VERSION=$(cat $DASHMAN_GITDIR/VERSION)

curl_cmd='timeout 7 curl -s'

# (mostly) functioning functions -- lots of refactoring to do ----------------

pending(){ [[ $QUIET ]] || echo -en "$C_YELLOW$1$C_NORM" ; }

ok(){ [[ $QUIET ]] || echo -e "$C_GREEN$1$C_NORM" ; }

warn() { [[ $QUIET ]] || echo -e "$C_YELLOW$1$C_NORM" ; }

err() { [[ $QUIET ]] || echo -e "$C_RED$1$C_NORM" ; }
die() { [[ $QUIET ]] || echo -e "$C_RED$1$C_NORM" ; exit 1 ; }

quit(){ [[ $QUIET ]] || echo -e "$C_GREEN${1:-Exiting.}$C_NORM" ; exit 0 ; }

confirm() { read -r -p "$(echo -e "${1:-Are you sure? [y/N]}")" ; [[ ${REPLY:0:1} = [Yy] ]]; }

usage(){
    cat<<EOF

    USAGE: ${0##*/} [command]

        installs, updates, and manages single-user dash daemons and wallets

    COMMANDS

        install

            creates a fresh dash installation and starts dashd

        update

            updates dash to latest version and restarts (see below)

        reinstall

            overwrites dash with latest version and restarts (see below)

        restart [now]

            restarts dashd and deletes:
                budget.dat
                debug.log
                fee_estimates.dat
                mncache.dat
                mnpayments.dat
                peers.dat

            will prompt user if not given the 'now' argument

        status

            polls local and web sources and displays current status

        vote

            cast masternode votes for distributed budget ballot items

        version

            prints dashmans version number and exit

EOF
}

_check_dependencies() {
    which curl >/dev/null || die 'missing dependency: curl - sudo apt-get install curl'
    which python >/dev/null || die 'missing dependency: python - sudo apt-get install python'
    which perl >/dev/null || die 'missing dependency: perl - sudo apt-get install perl'

    # make sure we have the right netcat version (-4,-6 flags)
    if [ ! -z "$(which nc)" ]; then
        nc -z -4 8.8.8.8 53 2>&1 >/dev/null
        if [ $? -gt 0 ]; then
            die 'missing dependency: netcat6 - sudo apt-get install netcat6'
        fi
    else
        die 'missing dependency: netcat - sudo apt-get install netcat'
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
                die "\ndash executables found in system dir $INSTALL_DIR. Run dashman as root (sudo dashman command) to continue. Exiting."
            fi

        fi

    # dash-cli not in PATH

        # check current directory
    elif [ -e ./dash-cli ] ; then
        INSTALL_DIR='.' ;

        # check ~/.dash directory
    elif [ -e $HOME/.dash/dash-cli ] ; then
        INSTALL_DIR="$HOME/.dash" ;

        # TODO try to find dash-cli with find
#    else
#        CANDIDATES=`find $HOME -name dash-cli`
    fi

    if [ ! -z "$INSTALL_DIR" ]; then
        INSTALL_DIR=$(readlink -f $INSTALL_DIR) 2>/dev/null
        if [ ! -e $INSTALL_DIR ]; then
            echo -e "${C_RED}cannot find dash-cli in current directory, ~/.dash, or \$PATH. -- Exiting.$C_NORM"
            exit 1
        fi
    else
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

}


_check_dashman_updates() {
    GITHUB_DASHMAN_VERSION=$( $curl_cmd https://raw.githubusercontent.com/moocowmoo/dashman/master/VERSION )
    if [ "$DASHMAN_VERSION" != "$GITHUB_DASHMAN_VERSION" ]; then
        echo -e "\n"
        echo -e "${C_RED}${0##*/} requires updating. Latest version is: $C_GREEN$GITHUB_DASHMAN_VERSION$C_RED\nDo 'dashman sync' manually, or choose yes below.$C_NORM\n"

        pending "sync dashman to github now? "

        if confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
            echo $DASHMAN_VERSION > $DASHMAN_GITDIR/PREVIOUS_VERSION
            exec $DASHMAN_GITDIR/${0##*/} sync $COMMAND
        fi
        die 'Exiting.'
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
        armv7l)
            BITS=32
            RPI=1
            ;;
        *)
            err "unknown platform: $PLATFORM"
            err "dashman currently only supports 32/64bit linux"
            die "Exiting."
            ;;
    esac
}

_get_versions() {
    _get_platform_info
    DOWNLOAD_HTML=$( $curl_cmd $DOWNLOAD_PAGE )
    local IFS=' '
    read -a DOWNLOAD_URLS <<< $( echo $DOWNLOAD_HTML | sed -e 's/ /\n/g' | grep binaries | grep Download | grep linux | perl -ne '/.*"([^"]+)".*/; print "$1 ";' 2>/dev/null )
    #$( <-- vim syntax highlighting fix
    LATEST_VERSION=$( echo ${DOWNLOAD_URLS[0]} | perl -ne '/dash-([0-9.]+)-/; print $1;' 2>/dev/null )
    if [ -z "$LATEST_VERSION" ]; then
        die "\nCould not find latest version from $DOWNLOAD_PAGE -- Exiting."
    fi

    if [ -z "$DASH_CLI" ]; then DASH_CLI='echo'; fi
    CURRENT_VERSION=$( $DASH_CLI --version | perl -ne '/v([0-9.]+)-/; print $1;' 2>/dev/null ) 2>/dev/null
    for url in "${DOWNLOAD_URLS[@]}"
    do
        if [[ $url =~ .*linux${BITS}.* ]] ; then
            DOWNLOAD_URL=$url
            DOWNLOAD_FILE=${DOWNLOAD_URL##*/}
        fi
    done
}


_check_dashd_running() {
    if [ $( $DASH_CLI help 2>/dev/null | wc -l ) -gt 0 ]; then
        DASHD_RUNNING=1
    fi
}

restart_dashd(){

    if [ $DASHD_RUNNING == 1 ]; then
        pending " --> Stopping dashd..."
        $DASH_CLI stop 2>&1 >/dev/null
        sleep 10
        killall -9 dashd dash-shutoff 2>/dev/null
        ok 'DONE!'
        DASHD_RUNNING=0
    fi

    pending ' --> Deleting cache files, debug.log...'
    cd $INSTALL_DIR
    rm -f budget.dat debug.log fee_estimates.dat mncache.dat mnpayments.dat peers.dat
    ok 'DONE!'

    pending ' --> Starting dashd...'
    $INSTALL_DIR/dashd 2>&1 >/dev/null
    ok 'DONE!'
    pending " --> Waiting for dashd to respond..."
    echo -en "${C_YELLOW}"
    while [ $DASHD_RUNNING == 0 ]; do
        echo -n "."
        _check_dashd_running
        sleep 5
    done
    ok "DONE!"
    pending " --> dash-cli getinfo"
    echo
    $DASH_CLI getinfo
    echo

}


update_dashd(){

    if [ $LATEST_VERSION != $CURRENT_VERSION ] || [ ! -z "$REINSTALL" ] ; then

        if [ ! -z "$REINSTALL" ];then
            echo -e ""
            echo -e "$C_GREEN*** dash version $CURRENT_VERSION is up-to-date. ***$C_NORM"
            echo -e ""
            echo -en
            pending "reinstall to $INSTALL_DIR$C_NORM?"
        else
            echo -e ""
            echo -e "$C_RED*** a newer version of dash is available. ***$C_NORM"
            echo -e ""
            echo -e "  current version: $C_RED$CURRENT_VERSION$C_NORM"
            echo -e "   latest version: $C_GREEN$LATEST_VERSION$C_NORM"
            echo -e ""
            pending "download $DOWNLOAD_URL\nand install to $INSTALL_DIR?"
        fi


        if ! confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
            echo -e "${C_RED}Exiting.$C_NORM"
            echo ""
            exit 0
        fi

        # prep it ----------------------------------------------------------------

        if [ ! -z $LINK_TO_SYSTEM_DIR ]; then

            # mv executables into ~/.dash
            mv $INSTALL_DIR/{dashd,dash-cli} $HOME/.dash
            chown $SUDO_USER $HOME/.dash/{dashd,dash-cli}

            # symlink to system dir
            ln -s $HOME/.dash/dashd $LINK_TO_SYSTEM_DIR
            ln -s $HOME/.dash/dash-cli $LINK_TO_SYSTEM_DIR

            INSTALL_DIR=$HOME/.dash

        fi


        # push it ----------------------------------------------------------------

        cd $INSTALL_DIR

        # pull it ----------------------------------------------------------------

        echo ""
        pending " --> downloading ${DOWNLOAD_URL}..."
        wget --no-check-certificate -q -r $DOWNLOAD_URL -O $DOWNLOAD_FILE
        wget --no-check-certificate -q -r ${DOWNLOAD_URL}.DIGESTS.txt -O ${DOWNLOAD_FILE}.DIGESTS.txt
        if [ ! -e $DOWNLOAD_FILE ] ; then
            echo -e "${C_RED}error downloading file"
            echo -e "tried to get $DOWNLOAD_URL$C_NORM"
            exit 1
        else
            ok "DONE!"
        fi

        # prove it ---------------------------------------------------------------

        pending " --> checksumming ${DOWNLOAD_FILE}..."
        SHA256SUM=$( sha256sum $DOWNLOAD_FILE )
        MD5SUM=$( md5sum $DOWNLOAD_FILE )
        SHA256PASS=$( grep $SHA256SUM ${DOWNLOAD_FILE}.DIGESTS.txt | wc -l )
        MD5SUMPASS=$( grep $MD5SUM ${DOWNLOAD_FILE}.DIGESTS.txt | wc -l )
        if [ $SHA256PASS -lt 1 ] ; then
            echo -e " ${C_RED} SHA256 checksum FAILED! Try again later. Exiting.$C_NORM"
            exit 1
        fi
        if [ $MD5SUMPASS -lt 1 ] ; then
            echo -e " ${C_RED} MD5 checksum FAILED! Try again later. Exiting.$C_NORM"
            exit 1
        fi
        ok "DONE!"

        # produce it -------------------------------------------------------------

        pending " --> unpacking ${DOWNLOAD_FILE}..." && \
        tar zxf $DOWNLOAD_FILE && \
        ok "DONE!"

        # pummel it --------------------------------------------------------------

        if [ $DASHD_RUNNING == 1 ]; then
            pending " --> stopping dashd. please wait..."
            $DASH_CLI stop >/dev/null 2>&1
            sleep 15
            killall -9 dashd dash-shutoff >/dev/null 2>&1
            ok "DONE!"
        fi

        # prune it ---------------------------------------------------------------

        pending " --> Removing old version..."
        rm -f \
            budget.dat \
            debug.log \
            fee_estimates.dat \
            mncache.dat \
            mnpayments.dat \
            peers.dat \
            dashd \
            dashd-$CURRENT_VERSION \
            dash-qt \
            dash-qt-$CURRENT_VERSION \
            dash-cli \
            dash-cli-$CURRENT_VERSION
        ok "DONE!"

        # place it ---------------------------------------------------------------

        mv dash-0.12.0/bin/dashd dashd-$LATEST_VERSION
        mv dash-0.12.0/bin/dash-cli dash-cli-$LATEST_VERSION
        mv dash-0.12.0/bin/dash-qt dash-qt-$LATEST_VERSION
        ln -s dashd-$LATEST_VERSION dashd
        ln -s dash-cli-$LATEST_VERSION dash-cli
        ln -s dash-qt-$LATEST_VERSION dash-qt

        # permission it ----------------------------------------------------------

        if [ ! -z "$SUDO_USER" ]; then
            chown -h $SUDO_USER:$SUDO_USER {$DOWNLOAD_FILE,${DOWNLOAD_FILE}.DIGESTS.txt,dash-cli,dashd,dash-qt,dash*$LATEST_VERSION}
        fi

        # purge it ---------------------------------------------------------------

        rm -rf dash-0.12.0

        # punch it ---------------------------------------------------------------

        pending " --> Launching dashd..."
        $INSTALL_DIR/dashd > /dev/null
        ok "DONE!"

        # probe it ---------------------------------------------------------------

        pending " --> Waiting for dashd to respond..."
        echo -en "${C_YELLOW}"
        while [ $DASHD_RUNNING == 0 ]; do
            echo -n "."
            _check_dashd_running
            sleep 5
        done
        ok "DONE!"

        # poll it ----------------------------------------------------------------

        _get_versions

        # pass or punt -----------------------------------------------------------

        if [ $LATEST_VERSION == $CURRENT_VERSION ]; then
            echo -e ""
            echo -e "${C_GREEN}dash successfully upgraded to version ${LATEST_VERSION}$C_NORM"
            echo -e ""
            echo -e "${C_GREEN}Installed in ${INSTALL_DIR}$C_NORM"
            echo -e ""
            ls -l --color {$DOWNLOAD_FILE,${DOWNLOAD_FILE}.DIGESTS.txt,dash-cli,dashd,dash-qt,dash*$LATEST_VERSION}
            echo -e ""

            if [ ! -z "$SUDO_USER" ]; then
                echo -e "${C_GREEN}Symlinked to: ${LINK_TO_SYSTEM_DIR}$C_NORM"
                echo -e ""
                ls -l --color $LINK_TO_SYSTEM_DIR/{dashd,dash-cli}
                echo -e ""
            fi

            quit
        else
            echo -e "${C_RED}dash version $CURRENT_VERSION is not up to date. ($LATEST_VERSION) Exiting.$C_NORM"
        fi

    else
        echo -e ""
        echo -e "${C_GREEN}dash version $CURRENT_VERSION is up to date. Exiting.$C_NORM"
    fi

    exit 0
}

install_dashd(){

    INSTALL_DIR=$HOME/.dash
    DASH_CLI="$INSTALL_DIR/dash-cli"

    if [ -e $INSTALL_DIR ] ; then
        die "\n - pre-existing directory $INSTALL_DIR found. Run 'dashman reinstall' to overwrite. Exiting."
    fi

    pending " - download $DOWNLOAD_URL\n - and install to $INSTALL_DIR?"

    if ! confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
        echo -e "${C_RED}Exiting.$C_NORM"
        echo ""
        exit 0
    fi

    get_public_ips
    # prompt for ipv4 or ipv6 install
    if [ ! -z "$PUBLIC_IPV6" ] && [ ! -z "$PUBLIC_IPV4" ]; then
        pending " --- " ; echo
        pending " - Host has both ipv4 and ipv6 addresses.\n - Use ipv6 for install?"
        if confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
            USE_IPV6=1
        fi
    fi

    echo ""

    # prep it ----------------------------------------------------------------

    mkdir -p $INSTALL_DIR

    if [ ! -e $INSTALL_DIR/dash.conf ] ; then
        pending " --> creating dash.conf..."

        IPADDR=$PUBLIC_IPV4
        if [ ! -z "$USE_IPV6" ]; then
            IPADDR='['$PUBLIC_IPV6']'
        fi
        RPCUSER=`echo $(dd if=/dev/urandom bs=128 count=1 2>/dev/null) | sha256sum | awk '{print $1}'`
        RPCPASS=`echo $(dd if=/dev/urandom bs=128 count=1 2>/dev/null) | sha256sum | awk '{print $1}'`
        while read; do
            eval echo "$REPLY"
        done < $DASHMAN_GITDIR/.dash.conf.template > $INSTALL_DIR/dash.conf
        ok 'DONE!'
    fi

    # push it ----------------------------------------------------------------

    cd $INSTALL_DIR

    # pull it ----------------------------------------------------------------

    pending " --> downloading ${DOWNLOAD_URL}..."
    wget --no-check-certificate -q -r $DOWNLOAD_URL -O $DOWNLOAD_FILE
    wget --no-check-certificate -q -r ${DOWNLOAD_URL}.DIGESTS.txt -O ${DOWNLOAD_FILE}.DIGESTS.txt
    if [ ! -e $DOWNLOAD_FILE ] ; then
        echo -e "${C_RED}error downloading file"
        echo -e "tried to get $DOWNLOAD_URL$C_NORM"
        exit 1
    else
        ok "DONE!"
    fi

    # prove it ---------------------------------------------------------------

    pending " --> checksumming ${DOWNLOAD_FILE}..."
    SHA256SUM=$( sha256sum $DOWNLOAD_FILE )
    MD5SUM=$( md5sum $DOWNLOAD_FILE )
    SHA256PASS=$( grep $SHA256SUM ${DOWNLOAD_FILE}.DIGESTS.txt | wc -l )
    MD5SUMPASS=$( grep $MD5SUM ${DOWNLOAD_FILE}.DIGESTS.txt | wc -l )
    if [ $SHA256PASS -lt 1 ] ; then
        echo -e " ${C_RED} SHA256 checksum FAILED! Try again later. Exiting.$C_NORM"
        exit 1
    fi
    if [ $MD5SUMPASS -lt 1 ] ; then
        echo -e " ${C_RED} MD5 checksum FAILED! Try again later. Exiting.$C_NORM"
        exit 1
    fi
    ok "DONE!"

    # produce it -------------------------------------------------------------

    pending " --> unpacking ${DOWNLOAD_FILE}..." && \
    tar zxf $DOWNLOAD_FILE && \
    ok "DONE!"

    # pummel it --------------------------------------------------------------

    if [ $DASHD_RUNNING == 1 ]; then
        pending " --> stopping dashd. please wait..."
        $DASH_CLI stop >/dev/null 2>&1
        sleep 15
        killall -9 dashd dash-shutoff >/dev/null 2>&1
        ok "DONE!"
    fi

    # prune it ---------------------------------------------------------------

    pending " --> Removing old version..."
    rm -f \
        budget.dat \
        debug.log \
        fee_estimates.dat \
        mncache.dat \
        mnpayments.dat \
        peers.dat \
        dashd \
        dashd-$CURRENT_VERSION \
        dash-qt \
        dash-qt-$CURRENT_VERSION \
        dash-cli \
        dash-cli-$CURRENT_VERSION
    ok "DONE!"

    # place it ---------------------------------------------------------------

    mv dash-0.12.0/bin/dashd dashd-$LATEST_VERSION
    mv dash-0.12.0/bin/dash-cli dash-cli-$LATEST_VERSION
    mv dash-0.12.0/bin/dash-qt dash-qt-$LATEST_VERSION
    ln -s dashd-$LATEST_VERSION dashd
    ln -s dash-cli-$LATEST_VERSION dash-cli
    ln -s dash-qt-$LATEST_VERSION dash-qt

    # permission it ----------------------------------------------------------

    if [ ! -z "$SUDO_USER" ]; then
        chown -h $SUDO_USER:$SUDO_USER {$DOWNLOAD_FILE,${DOWNLOAD_FILE}.DIGESTS.txt,dash-cli,dashd,dash-qt,dash*$LATEST_VERSION}
    fi

    # purge it ---------------------------------------------------------------

    rm -rf dash-0.12.0

    # punch it ---------------------------------------------------------------

    pending " --> Launching dashd..."
    $INSTALL_DIR/dashd > /dev/null
    ok "DONE!"

    # probe it ---------------------------------------------------------------

    pending " --> Waiting for dashd to respond..."
    echo -en "${C_YELLOW}"
    while [ $DASHD_RUNNING == 0 ]; do
        echo -n "."
        _check_dashd_running
        sleep 5
    done
    ok "DONE!"

    # poll it ----------------------------------------------------------------

    _get_versions

    # pass or punt -----------------------------------------------------------

    if [ $LATEST_VERSION == $CURRENT_VERSION ]; then
        echo -e ""
        echo -e "${C_GREEN}dash ${LATEST_VERSION} successfully installed!$C_NORM"
        echo -e ""
        echo -e "${C_GREEN}Installed in ${INSTALL_DIR}$C_NORM"
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
        echo -e "${C_RED}dash version $CURRENT_VERSION is not up to date. ($LATEST_VERSION) Exiting.$C_NORM"
        exit 1
    fi

}

get_dashd_status(){

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
    DASHD_UPTIME=$(ps -p $DASHD_PID -o etime= 2>/dev/null | sed -e 's/ //g')
    DASHD_UPTIME_TIMES=$(echo "$DASHD_UPTIME" | perl -ne 'chomp ; s/-/:/ ; print join ":", reverse split /:/')
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

    WEB_BLOCK_COUNT_CHAINZ=`$curl_cmd https://chainz.cryptoid.info/dash/api.dws?q=getblockcount`;
    if [ -z "$WEB_BLOCK_COUNT_CHAINZ" ]; then
        WEB_BLOCK_COUNT_CHAINZ=0
    fi

    WEB_BLOCK_COUNT_DQA=`$curl_cmd http://explorer.darkcoin.qa/chain/Dash/q/getblockcount`;
    if [ -z "$WEB_BLOCK_COUNT_DQA" ]; then
        WEB_BLOCK_COUNT_DQA=0
    fi

    WEB_DASHWHALE=`$curl_cmd https://www.dashwhale.org/api/v1/public`;
    WEB_DASHWHALE_JSON_TEXT=$(echo $WEB_DASHWHALE | python -m json.tool)
    WEB_BLOCK_COUNT_DWHALE=$(echo "$WEB_DASHWHALE_JSON_TEXT" | grep consensus_blockheight | awk '{print $2}' | sed -e 's/[",]//g')

    WEB_ME=`$curl_cmd https://www.masternode.me/data/block_state.txt 2>/dev/null`;
    if [ -z "$WEB_ME" ]; then
        WEB_ME=`$curl_cmd http://www.masternode.me/data/block_state.txt 2>/dev/null`;
    fi
    WEB_ME_BLOCK_COUNT=$( echo $WEB_ME_BLOCK_COUNT | awk '{print $1}')
    WEB_ME_FORK_DETECT=$( echo $WEB_ME_BLOCK_COUNT | awk '{print $3}' | grep 'fork detected' | wc -l )

    DASHD_SYNCED=0
    if [ $(($WEB_BLOCK_COUNT_CHAINZ - 2)) -lt $DASHD_CURRENT_BLOCK ]; then DASHD_SYNCED=1 ; fi

    DASHD_CONNECTED=0
    if [ $DASHD_CONNECTIONS -gt 0 ]; then DASHD_CONNECTED=1 ; fi

    DASHD_UP_TO_DATE=0
    if [ $LATEST_VERSION == $CURRENT_VERSION ]; then
        DASHD_UP_TO_DATE=1
    fi

    get_public_ips

    MASTERNODE_BIND_IP='none'
    PUBLIC_PORT_CLOSED=$( timeout 2 nc -4 -z $PUBLIC_IPV4 9999 2>&1 >/dev/null; echo $? )
    if [ $PUBLIC_PORT_CLOSED -ne 0 ] && [ ! -z "$PUBLIC_IPV6" ]; then
        PUBLIC_PORT_CLOSED=$( timeout 2 nc -6 -z $PUBLIC_IPV6 9999 2>&1 >/dev/null; echo $? )
        if [ $PUBLIC_PORT_CLOSED -eq 0 ]; then
            MASTERNODE_BIND_IP=$PUBLIC_IPV6
        fi
    else
        MASTERNODE_BIND_IP=$PUBLIC_IPV4
    fi

    # masternode specific

    MN_CONF_ENABLED=$( egrep '^[^#]*\s*masternode\s*=\s*1' $HOME/.dash/dash.conf | wc -l 2>/dev/null)
    MN_STARTED=`$DASH_CLI masternode debug 2>&1 | grep 'successfully started' | wc -l`
    MN_LIST=`$DASH_CLI masternode list full 2>/dev/null`
    MN_VISIBLE=$(  echo "$MN_LIST" | grep $MASTERNODE_BIND_IP | wc -l)
    MN_ENABLED=$(  echo "$MN_LIST" | grep -c ENABLED)
    MN_UNHEALTHY=$(echo "$MN_LIST" | grep -c POS_ERROR)
    MN_EXPIRED=$(  echo "$MN_LIST" | grep -c EXPIRED)
    MN_TOTAL=$(( $MN_ENABLED + $MN_UNHEALTHY ))

    if [ $MN_CONF_ENABLED -gt 0 ] ; then
        WEB_NINJA_API=$($curl_cmd "https://dashninja.pl/api/masternodes?ips=\[\"${MASTERNODE_BIND_IP}:9999\"\]&portcheck=1&balance=1")
        WEB_NINJA_JSON_TEXT=$(echo $WEB_NINJA_API | python -m json.tool)
        WEB_NINJA_SEES_OPEN=$(echo "$WEB_NINJA_JSON_TEXT" | grep '"Result"' | grep open | wc -l)
        WEB_NINJA_MN_ADDY=$(echo "$WEB_NINJA_JSON_TEXT" | grep MasternodePubkey | awk '{print $2}' | sed -e 's/[",]//g')
        WEB_NINJA_MN_VIN=$(echo "$WEB_NINJA_JSON_TEXT" | grep MasternodeOutputHash | awk '{print $2}' | sed -e 's/[",]//g')
        WEB_NINJA_MN_VIDX=$(echo "$WEB_NINJA_JSON_TEXT" | grep MasternodeOutputIndex | awk '{print $2}' | sed -e 's/[",]//g')
        WEB_NINJA_MN_BALANCE=$(echo "$WEB_NINJA_JSON_TEXT" | grep Value | awk '{print $2}' | sed -e 's/[",]//g')
        WEB_NINJA_MN_LAST_PAID_TIME_EPOCH=$(echo "$WEB_NINJA_JSON_TEXT" | grep MNLastPaidTime | awk '{print $2}' | sed -e 's/[",]//g')
        WEB_NINJA_MN_LAST_PAID_AMOUNT=$(echo "$WEB_NINJA_JSON_TEXT" | grep MNLastPaidAmount | awk '{print $2}' | sed -e 's/[",]//g')
        WEB_NINJA_MN_LAST_PAID_BLOCK=$(echo "$WEB_NINJA_JSON_TEXT" | grep MNLastPaidBlock | awk '{print $2}' | sed -e 's/[",]//g')

        WEB_NINJA_LAST_PAYMENT_TIME=$(date -d @${WEB_NINJA_MN_LAST_PAID_TIME_EPOCH} '+%m/%d/%Y %H:%M:%S')

        if [ ! -z "$WEB_NINJA_LAST_PAYMENT_TIME" ]; then
            local daysago=$(dateDiff -d now "$WEB_NINJA_LAST_PAYMENT_TIME")
            local hoursago=$(dateDiff -h now "$WEB_NINJA_LAST_PAYMENT_TIME")
            hoursago=$(( hoursago - (24 * daysago) ))
            WEB_NINJA_LAST_PAYMENT_TIME="$WEB_NINJA_LAST_PAYMENT_TIME ($daysago days, $hoursago hours ago)"
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
    dte2=$(date2stamp $2)
    diffSec=$((dte2-dte1))
    if ((diffSec < 0)); then abs=-1; else abs=1; fi
    echo $((diffSec/sec*abs))
}

get_host_status(){
    HOST_LOAD_AVERAGE=$(cat /proc/loadavg | awk '{print $1" "$2" "$3}')
    uptime=$(</proc/uptime)
    uptime=${uptime%%.*}
    HOST_UPTIME_DAYS=$(( uptime/60/60/24 ))
}


print_status() {
    pending "  host uptime/load average   : " ; ok "$HOST_UPTIME_DAYS days, $HOST_LOAD_AVERAGE"
    pending "  dashd bind ip address      : " ; [ $MASTERNODE_BIND_IP != 'none' ] && ok $MASTERNODE_BIND_IP || err $MASTERNODE_BIND_IP
    pending "  dashd version              : " ; ok "$CURRENT_VERSION"
    pending "  dashd up-to-date           : " ; [ $DASHD_UP_TO_DATE -gt 0 ] && ok 'YES' || err 'NO'
    pending "  dashd running              : " ; [ $DASHD_HASPID     -gt 0 ] && ok 'YES' || err 'NO'
    pending "  dashd uptime               : " ; ok "$DASHD_UPTIME_DAYS days, $DASHD_UPTIME_HOURS hours, $DASHD_UPTIME_MINS mins, $DASHD_UPTIME_SECS secs"
    pending "  dashd responding (rpc)     : " ; [ $DASHD_RUNNING    -gt 0 ] && ok 'YES' || err 'NO'
    pending "  dashd listening  (ip)      : " ; [ $DASHD_LISTENING  -gt 0 ] && ok 'YES' || err 'NO'
    pending "  dashd connecting (peers)   : " ; [ $DASHD_CONNECTED  -gt 0 ] && ok 'YES' || err 'NO'
    pending "  dashd port open            : " ; [ $PUBLIC_PORT_CLOSED  -lt 1 ] && ok 'YES' || err 'NO'
    pending "  dashd connection count     : " ; [ $DASHD_CONNECTIONS   -gt 0 ] && ok $DASHD_CONNECTIONS || err $DASHD_CONNECTIONS
    pending "  dashd blocks synced        : " ; [ $DASHD_SYNCED     -gt 0 ] && ok 'YES' || err 'NO'
    pending "  last block (local dashd)   : " ; [ $DASHD_SYNCED     -gt 0 ] && ok $DASHD_CURRENT_BLOCK || err $DASHD_CURRENT_BLOCK
    pending "             (chainz)        : " ; [ $WEB_BLOCK_COUNT_CHAINZ -gt 0 ] && ok $WEB_BLOCK_COUNT_CHAINZ || err $WEB_BLOCK_COUNT_CHAINZ
    pending "             (darkcoin.qa)   : " ; [ $WEB_BLOCK_COUNT_DQA    -gt 0 ] && ok $WEB_BLOCK_COUNT_DQA || err $WEB_BLOCK_COUNT_DQA
    pending "             (dashwhale)     : " ; [ $WEB_BLOCK_COUNT_DWHALE -gt 0 ] && ok $WEB_BLOCK_COUNT_DWHALE || err $WEB_BLOCK_COUNT_DWHALE
    pending "             (masternode.me) : " ; [ $WEB_ME_FORK_DETECT -gt 0 ] && err "$WEB_ME" || ok "$WEB_ME"
    pending "  masternode count           : " ; [ $MN_TOTAL            -gt 0 ] && ok $MN_TOTAL || err $MN_TOTAL
    if [ $DASHD_RUNNING -gt 0 ] && [ $MN_CONF_ENABLED -gt 0 ] ; then
    pending "  masternode started         : " ; [ $MN_STARTED -gt 0  ] && ok 'YES' || err 'NO'
    pending "  masternode visible (local) : " ; [ $MN_VISIBLE -gt 0  ] && ok 'YES' || err 'NO'
    pending "  masternode visible (ninja) : " ; [ $WEB_NINJA_SEES_OPEN -gt 0  ] && ok 'YES' || err 'NO'
    pending "  masternode address         : " ; ok $WEB_NINJA_MN_ADDY
    pending "  masternode funding txn     : " ; ok "$WEB_NINJA_MN_VIN-$WEB_NINJA_MN_VIDX"
    pending "  masternode last payment    : " ; [ ! -z "$WEB_NINJA_MN_LAST_PAID_AMOUNT" ] && \
        ok "$WEB_NINJA_MN_LAST_PAID_AMOUNT in $WEB_NINJA_MN_LAST_PAID_BLOCK on $WEB_NINJA_LAST_PAYMENT_TIME " || warn 'never'
    pending "  masternode balance         : " ; [ ! -z "$WEB_NINJA_MN_BALANCE" ] && ok "$WEB_NINJA_MN_BALANCE" || warn '0'

    fi

}

show_message_configure() {
    echo
    ok "To enable your masternode,"
    ok "uncomment and configure the masternode lines in:"
    echo
         pending "    $HOME/.dash/dash.conf" ; echo
    echo
    echo -e "$C_GREEN then run:$C_NORM"
    echo
    echo -e "    ${C_YELLOW}dashman restart now$C_NORM"
    echo
}

get_public_ips() {
    PUBLIC_IPV4=$($curl_cmd -4 https://icanhazip.com/)
    PUBLIC_IPV6=$($curl_cmd -6 https://icanhazip.com/)
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

# scrap, ignore --------------------------------------------------------------

#cmd_prompt() {
#    DASHMAN_PROMPT='dashman> '
#    echo -en $DASHMAN_PROMPT
#    read command
#    exec $DASHMAN_GITDIR/dashman $command

#usage(){
#    cat<<EOF
#    usage: ${0##*/} [-hqvV] [command]
#
#    switches:
#
#        -q, --quiet
#
#            suppresses all output
#
#        -h, --help
#
#            this help text
#
#        -v, --verbose
#
#            extra logging to screen
#
#        -V, --version
#
#            show dashman version
#
#    commands: restart install reinstall
#
#        restart [now]
#
#            will restart dashd and delete:
#                budget.dat, debug.log, fee_estimates.dat, mncache.dat,
#                mnpayments.dat, peers.dat
#
#            will prompt user if not given the 'now' argument
#
#        install
#
#            blah
#
#        reinstall
#
#            blah
#
#EOF
#}
#        status)
#            dashman_status
#            ;;
#        autoupdate)
#            ok 'update. --auto'
#            ;;
#        check)
#            ok 'check.'
#            ;;
#        update)
#            ok 'update'
#            ;;
#        die)
#            die 'Exiting.'
#            ;;
#        interactive)
#            cmd_prompt
#            ;;

#variants:
#
#    multi-user install
#        installed in system dir
#        installed in other dir?
#        runas root
#        runas sudo
#        single daemon
#        multiple daemons
#
#    single-user install
#        installed in system dir
#        installed in other dir
#        runas root
#        runas sudo
#        single daemon
#        multiple daemons?
