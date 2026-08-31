#!/bin/bash
#
# Usage example and description
# This script generates a list of .whl files in the wheelhouse directory.
# Usage: ./list_wheelfiles.sh <input_directory_path> <output_file_path>
# Example: ./list_wheelfiles.sh /path/to/directory /path/to/output/my-whl.list
# If no input directory is provided, the default directory is used.
# If no output file is provided, the default output file is used.
#
# location of inputs

export AURORA_PE_VERSION="26.181.0"
export AURORA_PE_FRAMEWORKS_SRC_DIR="/lus/tegu/projects/datasets/software/aurorasdk/input/frameworks/26.181.0"

[[ -z "${AURORA_PE_FRAMEWORKS_SRC_DIR:-}" ]] && AURORA_PE_FRAMEWORKS_SRC_DIR=/input/frameworks/${AURORA_PE_VERSION}
[[ -z "${AURORA_PE_FRAMEWORKS_INSTALL_DIR:-}" ]] && AURORA_PE_FRAMEWORKS_INSTALL_DIR=/opt/aurora/${AURORA_PE_VERSION}/frameworks

# Set default values
default_dir="${AURORA_PE_FRAMEWORKS_SRC_DIR}"
default_output_file="${default_dir}/manifests/test-all-whl.list"

echo "$default_dir"
echo "$default_output_file"

#exit

# Check if the user provided the directory path
if [[ -z "${1:-}" ]]; then
    echo "No directory path provided. Using default directory: $default_dir"
    input_dir="$default_dir"
else
    input_dir="$1"
fi

# Check if the user provided the output file name
if [[ -z "${2:-}" ]]; then
    echo "No output file name provided. Using default output file: $default_output_file"
    output_file="$default_output_file"
else
    output_file="$2"
fi

# Check if the directory exists
if [ ! -d "$input_dir" ]; then
    echo "Error: Directory '$input_dir' does not exist."
    exit 1
fi

# Define the wheelhouse directory
wheelhouse_dir="$input_dir/wheelhouse"

# Check if the wheelhouse directory exists
if [ ! -d "$wheelhouse_dir" ]; then
    echo "Error: 'wheelhouse' directory not found in '$input_dir'."
    exit 1
fi

# Ensure the output file is created or cleared
if [ -e "$output_file" ]; then
    # If the file exists, clear its contents
    echo "" > "$output_file"
else
    # If the file does not exist, create it
    touch "$output_file"
fi

# Find all .whl files in the wheelhouse directory and write their relative paths to the output file
find "$wheelhouse_dir" -type f -name "*.whl" | sed "s|$input_dir/||" >> "$output_file"

# Print success message
echo "List of .whl files with relative paths has been saved to '$output_file'."
