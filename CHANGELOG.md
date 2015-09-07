
0.1.0 - Mon Sep 7 00:12:24 2015 +0000

    created new top-level script 'dashman'

    takes command line arguments:

        install
            - install latest dash executables (fresh install)
        reinstall
            - reinstall latest dash executables (overwrite existing)
        update
            - update to latest dash executables (update existing)
        sync
            - sync with github (git fetch/reset)
        restart
            - restarts (or starts) dashd


0.0.8 - Thu Aug 27 07:57:15 2015 +0000

    added reinstall function
    added command line switches
        --reinstall
        -h, --help
        -v, --version
    sync_dashman_to_github.sh now pulls and sync's forced tags


0.0.7 - Thu Aug 27 07:57:15 2015 +0000

    beautify output -- added screencaps


0.0.6 - Thu Aug 27 04:50:21 2015 +0000

    first release working with alternate directories
