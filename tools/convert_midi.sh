#!/bin/bash

# Convert midi file to ogg using a soundfont (ex: tools/gm.sf2 Windows GM).
#
# parameters: <input path> <output path>
# env: SOUNDFONT_PATH

if [ -z "$1" ]
then
  echo "missing input path"
  exit 1
fi

if [ -z "$2" ]
then
  echo "missing output path"
  exit 1
fi

if [ -z "$SOUNDFONT_PATH" ]
then
  echo "missing soundfont path"
  exit 1
fi

fluidsynth -F "$2.wav" "$SOUNDFONT_PATH" "$1" >/dev/null 2>&1 && \
ffmpeg -y -i "$2.wav" -vn -c:a libvorbis -b:a 128k -filter:a loudnorm -ar 44100 "$2" >/dev/null 2>&1 && \
rm "$2.wav"
