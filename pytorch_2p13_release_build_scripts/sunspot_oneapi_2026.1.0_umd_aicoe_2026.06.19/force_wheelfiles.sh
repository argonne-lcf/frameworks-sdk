#!/usr/bin/env bash

# This script takes 2 arguments
# 1 the path to the wheelhouse directory
# 2 the path to the requirements.txt file
#
# It will attempt to find all of the wheels mentioned in the requirement file
# that exist in the wheelhouse directory and replace any entries in the
# requirements.txt file to point to them.
#
# This is necessary because using --find-link does not gaurantee using
# locally built wheel files if the version numbers to not differ.

WHEELHOUSE_DIR="$1"
REQUIREMENTS_FILE="$2"

if [[ -z "$WHEELHOUSE_DIR" || -z "$REQUIREMENTS_FILE" ]]; then
    echo "Usage: $0 <wheelhouse_dir> <requirements_file>"
    exit 1
fi

TMP_REQUIREMENTS="${REQUIREMENTS_FILE}.tmp"
cp "$REQUIREMENTS_FILE" "$TMP_REQUIREMENTS"

for whl in ${WHEELHOUSE_DIR}/*.whl; do
    # Note we are converting from underscores to dashes because of
    # intel_extension_for_pytorch, which uses both of them in
    # different places
    name="$(bsdtar -O -xf $whl '*dist-info/METADATA' | sed '/^Name/!d; s/.*: //; s/_/-/g;')"
    sed -i " s|^$name==.*|$whl|g" "$TMP_REQUIREMENTS"
done
