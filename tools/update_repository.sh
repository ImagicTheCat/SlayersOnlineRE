#!/bin/bash
# To be executed in its directory.
# parameters: <project path> <repository path>
# env: SOUNDFONT_PATH
if [ -z "$1" ]
then
  echo "missing project path"
  exit 1
fi

if [ -z "$2" ]
then
  echo "missing repository path"
  exit 1
fi

echo "Update sounds: wav files..."
rsync -av "$1/Sound/" --include '*/' --include '*.wav' --exclude '*' "$2/audio/"
echo
echo "Update sounds: midi files..."
find "$1/Sound/" -type f -iname '*.mid' -printf '%P\n' | parallel "[[ \"$1\"/Sound/{} -nt \"$2\"/audio/{.}.ogg ]] && \
  echo Convert {}... && \
  mkdir -p \"$2\"/audio/{//} && \
  ./convert_midi.sh \"$1\"/Sound/{} \"$2\"/audio/{.}.ogg"
echo
echo "Update chipsets..."
find "$1/Chipset/" -type f -iname '*.png' -printf '%P\n' | parallel "[[ \"$1\"/Chipset/{} -nt \"$2\"/textures/sets/{} ]] && \
  echo Convert {}... && \
  mkdir -p \"$2\"/textures/sets/{//} && \
  luajit convert_png.lua \"$1\"/Chipset/{} \"$2\"/textures/sets/{}"
echo
echo "Update manifest..."

hash_entry(){
  hash=($(md5sum "$2"))
  echo "$1=$hash"
}
export -f hash_entry
find "$2" -type f -printf '%P\n' | parallel hash_entry "{}" "$2/{}" > "$2/repository.manifest"
echo "done."
