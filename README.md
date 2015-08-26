# dashman

DASH wallet/daemon management utilities

# Assumptions/Limitations

This script, for now, assumes your binaries live in your ~/.dash folder and
downloads/creates symlinks there. (By adding ~/.dash to your PATH you can
invoke dash-cli/dashd from any directory.)

It is currently only compatible with 32/64 bit linux.

A destination/install folder will be added in future versions.

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

<img src="https://masternode.me/downloads/dashman-screencap.png?_=1">

# Contact

Email me at moocowmoo@masternode.me or submit a pull request.
