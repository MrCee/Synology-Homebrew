#!/bin/bash

# Function to perform sed operation in a portable way
# Arguments:
#   $1 - Sed expression
#   $2 - Input file
func_sed() {
    # Define a temporary file for storing the modified content
    local tmp_file=$(mktemp)

    # Perform the sed operation and capture the output and exit code
    sed_output=$(sed -E "$1" "$2" > "$tmp_file" 2>&1)
    sed_exit_code=$?

    if [ $sed_exit_code -eq 0 ]; then
        # Check if any changes were made
        if cmp -s "$2" "$tmp_file"; then
            echo "No changes needed in '$2'."
        else
            # Replace the original file with the modified content
            mv "$tmp_file" "$2"
            echo "Fix applied in '$2' :: '$1'"
        fi
    else
        # Print an error message if the sed operation failed
        echo "Error: Sed operation failed - $sed_output"
        return $sed_exit_code
    fi

    # Clean up the temporary file if it still exists
    [ -f "$tmp_file" ] && rm "$tmp_file"
}

