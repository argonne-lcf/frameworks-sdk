#!/bin/bash

# Check if the user provided the input list file
if [[ -z "${1:-}" ]]; then
    echo "Usage: $0 <input_list_file>"
    exit 1
fi

# Get the input list file
input_file="$1"

# Check if the input file exists
if [ ! -f "$input_file" ]; then
    echo "Error: File '$input_file' does not exist."
    exit 1
fi

# Define output file names
output_without_whl="$(basename ${input_file})_without_whl.list"
output_with_whl="whl_from_$(basename ${input_file}).list"


# Ensure the output file is created or cleared
if [ -e "$output_without_whl" ]; then
    echo "" > "$output_without_whl"  # Clear the file if it already exists
else
    touch "$output_without_file"     # Create the file if it does not exist
    echo "" > "$output_without_whl" 
fi

# Ensure the output file is created or cleared
if [ -e "$output_with_whl" ]; then
    echo "" > "$output_with_whl"  # Clear the file if it already exists
else
    touch "$output_with_whl"     # Create the file if it does not exist
    echo "" > "$output_with_whl" 
fi



# Clear or create the output files
> "$output_without_whl"
> "$output_with_whl"

# Process the input file line by line
while IFS= read -r line; do
    line=${line%$'\r'}
    if [[ "$line" == *.whl ]]; then
        # If the line ends with .whl, write it to the "list_with_whl.txt"
        echo "$line" >> "$output_with_whl"
    else
        # Otherwise, write it to the "list_without_whl.txt"
        echo "$line" >> "$output_without_whl"
    fi
done < "$input_file"


# Lines ending with .whl
#sed -n '/\.whl[[:space:]]*$/p' "$input_file" > "$output_with_whl"

# Lines NOT ending with .whl
#sed '/\.whl[[:space:]]*$/d' "$input_file" > "$output_without_whl"

# Print success message
echo "Processing complete!"
echo "File without .whl entries: $output_without_whl"
echo "File with only .whl entries: $output_with_whl"
