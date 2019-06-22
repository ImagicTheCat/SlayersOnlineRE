#!/bin/bash
# convert all midi files in the current directory to ogg using a soundfont (ex: tools/gm.sf2 Windows GM)
# parameters: <soundfont path>

if [ -z "$1" ]
then
  echo "missing soundfont path"
  exit 1
fi

path=$1

find . -type f -name '*.mid' | sed -e 's/^\(.\+\)\.mid$/\1/g' | xargs -d '\n' -P $(nproc) -n 1 -I % bash -c "fluidsynth -F \"%.wav\" \"$path\" \"%.mid\" 2> /dev/null && ffmpeg -y -i \"%.wav\" -vn -c:a libvorbis -b:a 128k -filter:a loudnorm -ar 44100 \"%.ogg\" && rm \"%.wav\""
