#!/bin/bash

CWD=$(pwd)

if [ ${CWD##*/} != 'dashman' ] || [ ! -e sync_dashman_to_github.sh ]; then
    echo ""
    echo "Usage: ./${0##*/}"
    echo ""
    echo "Update Dash Management Utilities from github."
    echo ""
    echo "Must be run from within dashman folder. Exiting."
    exit 1
fi

git fetch
git stash
git checkout master
git reset --hard origin/master

echo "Up to date."
