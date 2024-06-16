# functions.sh


# # Function to perform sed operation in a portable way
# Arguments:
#   $1 - Sed expression
#   $2 - Input file
funct_sed() {
    # Define a temporary file for storing the modified content
    local tmp_file=$(mktemp)

    # Perform the sed operation
    sed -E "$1" "$2" > "$tmp_file"
    mv "$tmp_file" "$2"
}
