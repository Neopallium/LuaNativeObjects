#!/bin/sh
#
DIR=`realpath $0`
DIR=`dirname $DIR`

if [ -z "$LUA_PATH" ] ; then
	export LUA_PATH="$DIR/?.lua;;"
else
	export LUA_PATH="$DIR/?.lua;$LUA_PATH"
fi
exec lua "$DIR/native_objects.lua" "$@"

