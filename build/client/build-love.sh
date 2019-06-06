#!/bin/bash


./build.sh

# build .love file
rm game.love
(cd raw && zip -r ../game.love *)
