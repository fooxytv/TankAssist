#!/bin/bash

# Automatically detect the addon directory by finding the .toc file
ADDON_DIR=$(dirname $(find . -maxdepth 1 -name "*.toc" | head -n 1))

if [ -z "$ADDON_DIR" ] || [ "$ADDON_DIR" == "." ]; then
    ADDON_DIR="."
fi

# Check if luacheck is installed
if ! command -v luacheck &> /dev/null
then
    echo -e "\033[31mError: luacheck is not installed. Please install luacheck manually.\033[0m"
    echo "Install with: luarocks install luacheck"
    exit 1
fi

# Run luacheck with quiet mode and capture its output
echo "Running Lua lint checks on directory: $(pwd)"

# Ignore common WoW addon globals:
# 111 - setting an undefined global variable
# 112 - mutating an undefined global variable
# 113 - accessing an undefined global variable
# 211 - unused local variable
# 212 - unused argument
# 432 - shadowing upvalue argument
# 631 - line is too long

luacheck "$ADDON_DIR" \
    --std max \
    --codes \
    --ignore 111 \
    --ignore 112 \
    --ignore 113 \
    --ignore 211 \
    --ignore 212 \
    --ignore 432 \
    --ignore 631 \
    --exclude-files "**/Libs/**"

exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    echo -e "\033[32mLua linting passed!\033[0m"
elif [[ $exit_code -eq 1 ]]; then
    echo -e "\033[33mLua linting completed with warnings.\033[0m"
else
    echo -e "\033[31mLua linting found errors. Please fix them.\033[0m"
    exit 1
fi
