# Extract git HEAD hash as client version.
sed -i "/^return/d" ../src/shared/app/client_version.lua
echo "return \"$(git rev-parse HEAD)\"" >> ../src/shared/app/client_version.lua
