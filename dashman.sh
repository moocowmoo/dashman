#!/bin/bash

# dashman - main executable
# installs, updates, and manages dash daemons and wallets

# Copyright (c) 2015 moocowmoo - moocowmoo@masternode.me

# parse any command line switches --------------------------------------------

# --quiet, --verbose don't do anything yet
i=0
until [ "$((i=$i+1))" -gt "$#" ]
do case "$1" in
    --help)    set -- "$@" "-h" ;;
    --quiet)   set -- "$@" "-q" ;;
    --verbose) set -- "$@" "-v" ;;
    --version) set -- "$@" "-V" ;;
    *)         set -- "$@" "$1" ;;
esac; shift; done
OPTIND=1
while getopts "hqvV" o ; do # set $o to the next passed option
  case "$o" in
    q) QUIET=1 ;;
    v) VERBOSE=1 ;;
    V) VERSION=1 ;;
    h) HELP=1 ;;
  esac
done
shift $(($OPTIND - 1))

# load common functions ------------------------------------------------------

DASHMAN_GITDIR=${0%%/${0##*/}}
source $DASHMAN_GITDIR/.dashman-functions.sh

# show help and exit if requested or no command supplied - TODO make command specific
[[ $HELP || -z $1 ]] && usage && exit 0

# show version and exit if requested
[[ $VERSION ]] && echo $DASHMAN_VERSION && exit 0


# have command, will travel... -----------------------------------------------

echo -e "${C_CYAN}${0##*/} version $DASHMAN_VERSION${C_NORM}"

# do awesome stuff -----------------------------------------------------------
COMMAND=''
case "$1" in
        restart)
            COMMAND=$1
            _find_dash_directory
            _check_dashd_running
            # TODO, show uptime: ps --no-header -o pid,etime $(cat $INSTALL_DIR/dash.pid) | awk '{print $2}'
            case "$2" in
                now)
                    restart_dashd
                    ;;
                *)
                    echo
                    pending "restart dashd? "
                    confirm "[${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN" && \
                        restart_dashd
                    ;;
            esac
            ;;
        update)
            COMMAND=$1
            if [ ! -z "$RPI" ];then die "not supported yet" ;fi
            pending "gathering info..."
            _check_dashman_updates
            _find_dash_directory
            _get_versions
            _check_dashd_running
            ok "DONE!"
            update_dashd
            ;;
        install)
            COMMAND=$1
            if [ ! -z "$RPI" ];then die "not supported yet" ;fi
            pending "gathering info..."
            _check_dashman_updates
            _get_versions
            ok "DONE!"
            install_dashd
            show_message_configure
            quit
            ;;
        reinstall)
            COMMAND=$1
            if [ ! -z "$RPI" ];then die "not supported yet" ;fi
            pending "gathering info..."
            _check_dashman_updates
            _find_dash_directory
            _get_versions
            _check_dashd_running
            REINSTALL=1
            update_dashd
            ok "DONE!"
            ;;
        sync)
            COMMAND=$1
            cd $DASHMAN_GITDIR
            git remote update -p
            if [ -z $(git config user.email) ] ; then
                git config user.email "dashmanuser"
                git config user.name "dashmanuser"
            fi
            git stash
            git checkout master
            git reset --hard origin/master
            if [ ! -z "$2" ]; then
                exec $DASHMAN_GITDIR/${0##*/} $2
            fi
            quit 'Up to date.'
            ;;
        branch)
            COMMAND=$1
            cd $DASHMAN_GITDIR
            git remote update -p
            if [ -z $(git config user.email) ] ; then
                git config user.email "dashmanuser"
                git config user.name "dashmanuser"
            fi
            BRANCH_OK=$(git for-each-ref --format='%(refname)' refs/remotes/origin | sed -e 's|refs/remotes/origin/||g' | grep "^${2}\$" | wc -l)
            if [ $BRANCH_OK -gt 0 ];then
                git stash
                pending "Switing to git branch "; ok $2
                git checkout $2
                git reset --hard origin/$2
            else
                die "Branch $2 not found. Exiting."
            fi
            ;;
        status)
            COMMAND=$1
            pending "gathering info, please wait..."
            _check_dashman_updates
            _find_dash_directory
            _get_versions
            _check_dashd_running
            get_dashd_status
            ok " DONE!"
            echo
            print_status
            quit 'Exiting.'
            ;;
        *)
            usage
            ;;
esac

quit
