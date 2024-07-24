#!/bin/bash

# Obtain the path to the primary script
SCRIPT_DIR=$(
    cd "$(dirname "$0")" || exit
    pwd
)
MER_CORE=$SCRIPT_DIR"/merger_core.sh"

# Show usage
function usage() {
    cat <<_EOT_
Usage:
  $0 <INPUT_PCD_DIR> <OUTPUT_PCD> <CONFIG_FILE>

Description:
  Merge PCD files to a single output PCD with or without downsampling.

Options:
  -h: Show this message.

_EOT_
}

# Parse options
if [ "$OPTIND" = 1 ]; then
    while getopts h OPT; do
        case $OPT in
        h)
            usage
            exit 0
            ;;
        \?)
            echo "Undefined option $OPT"
            usage
            exit 1
            ;;
        esac
    done
else
    echo "No installed getopts-command." 1>&2
    exit 1
fi
shift $((OPTIND - 1))

# Check the number of runtime arguments
if [ "$#" -ne 3 ]; then
    echo "Error: pointcloud_divider.sh requires 4 arguments."
    usage
    exit 1
fi

# Parse all mandatory arguments
INPUT_DIR=$1
OUTPUT_PCD=$2
CONFIG_FILE=$3

# Search all pcd files under the directory
if [ ! -e "$INPUT_DIR" ]; then
    echo "Error: $INPUT_DIR does not exists."
    usage
    exit 1
fi

IFS=" " read -ra PCD_FILES <<<"$(find "$INPUT_DIR" -name "*.pcd" -printf "%p ")"

# Check the number of PCD files
PCD_FILE_COUNT=$(echo "${PCD_FILES[@]}" | wc -w)

if [ "$PCD_FILE_COUNT" -eq 0 ]; then
    echo "Error: No valid PCD files are found."
    usage
    exit 1
fi

# Call the primary script
$MER_CORE "${PCD_FILES[@]}" "${OUTPUT_PCD}" "${CONFIG_FILE}"
