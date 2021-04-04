#!/bin/bash

# Convert all midi files to ogg using a soundfont (ex: tools/gm.sf2 Windows GM)
# from the current directory to the target directory (lazily).
#
# parameters: <target directory> <soundfont path>

if [ -z "$1" ]
then
  echo "missing target directory"
  exit 1
fi

if [ -z "$2" ]
then
  echo "missing soundfont path"
  exit 1
fi

target=$1
soundfont=$2

find . -type f -name '*.mid' -printf '%P\n' | parallel "[[ ! -f $target/{/.}.ogg ]] && \
  echo Convert {}... && \
  fluidsynth -F $target/{/.}.wav \"$soundfont\" {/.}.mid 2> /dev/null && \
  ffmpeg -y -i $target/{/.}.wav -vn -c:a libvorbis -b:a 128k -filter:a loudnorm -ar 44100 $target/{/.}.ogg && \
  rm $target/{/.}.wav"

# Old code using xargs.
# find . -type f -name '*.mid' -printf '%P\n' | sed -e 's/^\(.\+\)\.mid$/\1/g' | xargs -d '\n' -P $(nproc) -n 1 -I % bash -c "[[ ! -f '$target/%.ogg' ]] && fluidsynth -F \"$target/%.wav\" \"$soundfont\" \"%.mid\" 2> /dev/null && ffmpeg -y -i \"$target/%.wav\" -vn -c:a libvorbis -b:a 128k -filter:a loudnorm -ar 44100 \"$target/%.ogg\" && rm \"$target/%.wav\""
