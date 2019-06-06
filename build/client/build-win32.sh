#!/bin/bash

./build-love.sh

# build win32 directory
love=love-11.2.0-win32
rm win32 -r
rsync -av --exclude "lovec.exe" $love/ win32
cat $love/love.exe game.love > win32/love.exe
