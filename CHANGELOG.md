
0.1.8 - Mon Sep 14 02:59:05 2015 +0000

    raspberry pi support - status command only
    integrated git branch switching for experimental branches
    added instructions for enabling masternode (conf edits) after install

    bugfix - better boolean test for reinstall mode
    bugfix - die if cannot determine latest-version from/retrieve dashpay downloads page
    bugfix - five second connect timeout for public port test

0.1.7 - Mon Sep 14 02:59:05 2015 +0000

    re-run after needed sync
    fix git-stash on uninitialized systems

0.1.6 - Tue Sep 8 07:07:57 2015 +0000

    added dashninja masternode visibility

0.1.5 - Thu Sep 10 21:34:29 2015 +0000

    added dashwhale, masternode.me polling

0.1.4 - Wed Sep 9 07:55:44 2015 +0000

    fix download file selection
    check for updates on all commands

0.1.3 - Wed Sep 9 05:02:29 2015 +0000

    added dashninja masternode visibility

0.1.2 - Tue Sep 8 07:07:57 2015 +0000

    chainz hung - use darkcoin.qa explorer api

0.1.1 - Mon Sep 7 00:12:24 2015 +0000

    added statua function, screencaps

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
