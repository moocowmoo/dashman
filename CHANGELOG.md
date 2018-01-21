0.1.26 -  Sun Jan 21 08:45:23 2018 +0000

    enh - add highlight color for selection pending and startup states

    compat - bootstrap path change
    compat - update dashd 12.2

    config - beautify changelog print
    config - colorize compat class commits
    config - match new links.md format
    config - useragent dashman/version

    Fix 12.2.2 compat
    bugfix - add failover url to block_state pull
    bugfix - bootstrap.dat, skip invalid uploads
    bugfix - fix progress/estimate remaining render
    bugfix - fix version command
    bugfix - masternodeaddr -> externalip
    bugfix - missing newline in status output
    bugfix - repair state display when PRE_ENABLED
    bugfix - dashvote - skip stale proposals

    style - dashvote - text edits


0.1.25 -  Sun Mar 26 05:00:38 2017 +0000

    enh - add .dashcore to path in .bash_aliases on install
    enh - better block sync check
    enh - better dashd running detection
    enh - better sentinel sync messaging
    enh - dashvote 12.1 compat - background delayed sends
    enh - invoke sudo install on missing dependencies
    enh - move versioned executibles to bin dir - fixes tab completion
    enh - show download progress bar + fancy terminal cleanup
    enh - unattended install

    config - cleanup
    config - remove ipv6 support
    config - remove tarball after install

0.1.24 -  Sat Mar 4 12:09:29 2017 +0000

    enh - adding simple sentinel checks
    bugfix - queue calc repair + 1m caching
    compat - odroid c2 platform

0.1.23 -  Fri Feb 24 15:44:20 2017 +0000

    config - new sentinel crontab on update

0.1.22 -  Mon Feb 20 10:23:49 2017 +0000

    config - patch update for 12.1.x -> 12.1.x

0.1.21 -  Wed Feb 8 09:21:00 2017 +0000

    enh - 12.1 update + sentinel install

0.1.20 -  Fri Sep 2 06:49:52 2016 +0000

    config - display bootstrap download size
    config - only require unzip for install (for bootstrap extraction)
    bugfix - fix ok/err display arity
    bugfix - dashvote - prune completed proposals
    bugfix - follow redirects - dashninja 301->www
    bugfix - proper queue position calculation for new nodes

0.1.19 -  Tue Jun 21 08:01:55 2016 +0000

    bugfix - extract binary versions from updated downloads page

0.1.18 -  Fri Jun 10 16:06:07 2016 +0000

    config - pull checksums from github - remove MD5 checksum check from install

0.1.17 -  Sat Jun 4 06:10:03 2016 +0000

    config - pull checksums from github

0.1.16 -  Tue Dec 29 05:41:43 2015 +0000

    bugfix - support dash.org downloads page shift to relative pathing

0.1.15 -  Thu Nov 26 02:57:45 2015 +0000

    update download url to dash.org
    bugfix - support stale nss lib - downgrade second dashninja attempt
    dashvote - monkey-patch subprocess.check_output for python <2.7

0.1.14 -  Sun Nov 1 03:57:56 2015 +0000

    added git checkout info to version header
    added few more lines in polish

    bugfix - ip-lookup failover to http if https fails (older distro cert issue)
    bugfix - support symlink invocation

    dashvote - added git checkout info to version header
    dashvote - added loading screen, previous vote detection, vim navigation binding
    dashvote - added vote-counts, turnout percentage
    dashvote - bugfix - use alias for vote display - added threshold coloring, sort vote display by block start
    dashvote - align count/percentage columns
    dashvote - display vote hash during voting
    dashvote - ignore unmapped keystrokes

0.1.13 -  Sun Oct 25 05:49:37 2015 +0000

    initial i18n support - adding polish (thanks tombtc!)
    enh - gather all missing dependencies before exiting

    bugfix - fail gracefully when dashninja api offline
    bugfix - proper api-down test logic, doh!
    bugfix - silence misconfigured locale perl errors

    config - added branch to usage
    config - added sync to usage
    config - adding hostname to output
    typo - switching
    updated status screencap

0.1.12 -  Tue Oct 20 21:14:51 2015 +0000

    added payment queue position display

    bugfix - detect netcat -4,-6 switch support before embarking, prompt to install appropriate package
    bugfix - hide stderr output during dependency tests
    bugfix - retry web pulls once on failure - retry public ip lookup on failure
    bugfix - status - fail gracefully if dashd not running
    bugfix - vote - dont crash when masternode votes exceeds screen height
    compat - fixes for older oses - stderr and git syntax

    initial platform detection code
    style - pep8 formatting
    style - space after sync prompt

0.1.11 -  Wed Oct 14 08:19:10 2015 +0000

    added balance display

    bugfix - proper sync exec when called from relative path
    bugfix - voting - fail gracefully when dash-cli not in path
    bugfix - use initial api pull values for last payment
    bugfix - proper ipv6 formatting for hot-node voting

    support multiple sync exec arguments
    moved scripts to bin directory
    style - unify all gathering messages

0.1.10 -  Tue Oct 13 07:18:29 2015 +0000

    added ipv6 support - use icanhazip for ipv4/6 polling
    added dashd uptime calculation
    added support for hot-node (Internet server) dash.conf voting
    added initial host metrics: uptime/load average
    added dependency check on launch
    added last masternode payment display

    style - consolidated output
    switch to using curl. much faster
    refactor wgets -- add 4 second timeout to pulls
    bugfix - make sure we have an ipv6 before attempting local connection

0.1.9 - Sun Oct 11 04:05:54 2015 +0000

    added dashvote - time-randomized voting, initial curses UI

    enh - display changelog output on sync update
    enh - remove stale local git tags on sync

    style - show local blocks red if not syncd

    bugfix - fail gracefully when block explorer(s) down
    bugfix - masternode.me pull, downgrade to http (gnutls issue) if needed

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
