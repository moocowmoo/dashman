#!/bin/bash

CACHE_DIR=/tmp/dashman_cache
mkdir -p $CACHE_DIR
FILE_HASH=$(echo $@| md5sum | awk '{print $1}')
CACHE_FILE=$CACHE_DIR/$FILE_HASH

#echo $CACHE_FILE >&2

find $CACHE_DIR -type f -cmin +5 -exec rm {} \; >/dev/null 2>&1

if [ -e $CACHE_FILE ];then
    cat $CACHE_FILE
    exit
fi

curl -k -s -L -m 4 -A dashman/$DASHMAN_VERSION $@ > $CACHE_FILE 2>/dev/null
if [ $? -gt 0 ];then
    #rm -f $CACHE_FILE
    exit
fi

if [ -e $CACHE_FILE ];then
    cat $CACHE_FILE
    exit
fi
