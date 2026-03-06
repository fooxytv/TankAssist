#!/bin/bash

# Load .env file for all environments
if [ -f .env ]; then
    # Strip quotes and carriage returns from values when exporting
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        # Remove carriage returns, surrounding quotes
        key=$(echo "$key" | tr -d '\r')
        value=$(echo "$value" | tr -d '\r')
        value="${value%\"}"
        value="${value#\"}"
        # Validate key is a valid shell identifier before exporting
        if [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            export "$key=$value"
        fi
    done < .env
else
    echo "Error: .env file not found."
    exit 1
fi

# Locate .toc file in root directory only (not in libs subdirectories)
toc_file=$(find "$(pwd)" -maxdepth 1 -name "*.toc" | head -n 1)
if [ -z "$toc_file" ]; then
    echo "Error: No .toc file found in project root."
    exit 1
fi

addon_name=$(grep -oP '^## Title:\s*\K.*' "$toc_file" | tr -d '\r')
version=$(grep -oP '^## Version:\s*\K.*' "$toc_file" | tr -d '\r')

echo "Detected TOC file: $toc_file"
echo "Extracted Addon Name: '$addon_name'"
echo "Extracted Version: '$version'"

if [ -z "$addon_name" ] || [ -z "$version" ]; then
    echo "Error: Addon name or version not found in .toc file."
    exit 1
fi

./ci/scripts/package.sh

zip_file="ci/dist/${addon_name}-${version}.zip"
echo "Zip file will be: '$zip_file'"

retail_deploy() {
    if [ -z "$wow_addons_dir_retail" ]; then
        echo "Error: wow_addons_dir_retail is not set in .env file."
        exit 1
    fi
    echo "Deploying $zip_file to \"$wow_addons_dir_retail\"..."
    unzip -o "$zip_file" -d "$wow_addons_dir_retail"
    echo "Done."
}

ptr_deploy() {
    if [ -z "$wow_addons_dir_ptr" ]; then
        echo "Error: wow_addons_dir_ptr is not set in .env file."
        exit 1
    fi
    echo "Deploying $zip_file to \"$wow_addons_dir_ptr\"..."
    unzip -o "$zip_file" -d "$wow_addons_dir_ptr"
    echo "Done."
}

if [ "$1" == "retail" ] || [ "$1" == "local" ] || [ "$1" == "lcl" ]; then
    retail_deploy
elif [ "$1" == "ptr" ]; then
    ptr_deploy
else
    echo "Error: Invalid argument. Use 'retail', 'local', 'lcl', or 'ptr' to deploy."
    exit 1
fi
