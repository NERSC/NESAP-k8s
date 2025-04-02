#!/usr/bin/env bash
set -eu

# Check if a script is provided as argument
if [[ $# -lt 1 ]];
then
    echo "Usage: $0 <script> [args...]"
    echo "Sets the __PREFIX__ variable to the parent directory of $0 and __DIR__ to the directory of <script>"
    exit 1
fi

# Get the absolute path of this script
__get_script_dir() {
    local source="$1"
    echo "$(dirname "$(realpath "$source")")"
}

# Get the current directory => __PREFIX__
export __PREFIX__=$(__get_script_dir ${BASH_SOURCE[0]})

# Get the script to run
script="$1"
shift

# Get the directory of the called script => __DIR__
export __DIR__=$(__get_script_dir $script)

# Execute the script with remaining arguments
exec "$script" "$@"
