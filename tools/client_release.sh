# will generate a version number into src/shared/client_version.lua
echo "return \"$(xxd -p -l 32 -c 32 /dev/urandom)\"" > ../src/shared/client_version.lua
