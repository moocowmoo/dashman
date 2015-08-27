# dashman

DASH wallet/daemon management utilities

# Limitations

* This script searches for your dashd/dash-cli executibles in the current
directory, ~/.dash, and $PATH.  It will prompt to install in the first
directory found containing both dashd and dash-cli.  Multiple wallet
directories are not supported. The script assumes the host runs a single
instance of dashd.
* It is currently only compatible with 32/64 bit linux.

# Files

* sync_dashman_to_github.sh -- safe git commands to get everything up to date
* update_dashd.sh -- An easy to use update script for 32/64 bit linux

# Dependencies

* dashd - version 12 or greater
* dash-cli
* wget
* perl

# Install/Usage

To update your 32/64bit linux daemon to the latest dashd, do:

    sudo apt-get install git
    git clone https://github.com/moocowmoo/dashman.git
    cd dashman
    ./update_dashd.sh

# Screencap

<img src="https://raw.githubusercontent.com/moocowmoo/dashman/master/screencap.png">

# Contact

Email me at moocowmoo@masternode.me or submit a pull request.
