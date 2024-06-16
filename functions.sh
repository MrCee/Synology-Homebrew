#!/bin/bash

# Check if the script is being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This file should not be run directly, it should be sourced from main script."
    exit 1
fi

# Function to perform sed operation in a portable way
# Arguments:
#   $1 - Sed expression
#   $2 - Input file
func_sed() {
    local tmp_file=$(mktemp)
    sed_output=$(sed -E "$1" "$2" > "$tmp_file" 2>&1)
    sed_exit_code=$?

    if [ $sed_exit_code -eq 0 ]; then
        if cmp -s "$2" "$tmp_file"; then
            echo "No changes needed in '$2'."
        else
            mv "$tmp_file" "$2"
            echo "Fix applied in '$2' :: '$1'"
        fi
    else
        echo "Error: Sed operation failed - $sed_output"
        return $sed_exit_code
    fi
    
    [[ -f "$tmp_file" ]] && rm "$tmp_file"
}

