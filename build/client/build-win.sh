#!/bin/bash

if [ -z "$1" ]
then
  echo "missing build name"
  exit 1
fi

if [ -z "$LOVE_PATH" ]
then
  echo "missing LOVE_PATH"
  exit 1
fi

# build directory
rsync -av --exclude "*.exe" --exclude "readme.txt" --exclude "changes.txt" $LOVE_PATH/ $1
cat $LOVE_PATH/love.exe game.love > $1/$1.exe
zip -r $1.zip $1
rm $1 -r
