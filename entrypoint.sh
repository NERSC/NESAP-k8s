#!/usr/bin/env bash
set -euo pipefail

# Portable realpath function
__realpath() {
    if [[ $# -eq 0 ]]
    then
        printf "A portability wrapper around realpath. Usage: __realpath <path>\n" >&2
        return 1
    fi

    # Check for GNU realpath using the --version flag
    if realpath --version >/dev/null 2>&1
    then
        # This is a GNU realpath. Use it. Use `--` to handle problematic
        # filenames starting with a hyphen.
        realpath --no-symlinks -- "$1"
        return $?
    fi

    # Check for GNU grealpath (often from Homebrew on macOS)
    if command -v grealpath >/dev/null 2>&1
    then
        grealpath --no-symlinks -- "$1"
        return $?
    fi

    # Fallback to pure shell emulation for BSD or other systems
    (
        local file_path="${1}"
        local file_dir
        local file_name

        while [[ -h "${file_path}" ]]
        do
            file_dir=$(dirname "${file_path}")
            file_name=$(basename "${file_path}")
            file_path=$(readlink "${file_path}")

            if [[ "${file_path}" != /* ]]
            then
                file_path="${file_dir}/${file_path}"
            fi
        done

        file_dir=$(dirname "${file_path}")
        file_name=$(basename "${file_path}")

        if ! cd -P "${file_dir}"
        then
            printf "__realpath: cannot resolve path '%s'\n" "${1}" >&2
            return 1
        fi

        printf "%s/%s\n" "$(pwd -P)" "${file_name}"
    )
    return $?
}

# Get the absolute path of a script
__get_script_dir() {
    local source=$(__realpath "$1")
    echo "$(dirname $source)"
}

OPTIND=1 # Reset in case getopts has been used previously in the shell.
while getopts "h" opt
do
    case "$opt" in
        h|\\?)
            echo "Usage: $0 <script> [args...]"
            echo "Sets the __PREFIX__ variable to the parent directory of $0 and __DIR__ to the directory of <script>"
            echo "If <script> is not contained in __PREFIX__, then __MODE__ is set to 'external' and __DIR__ is unset"
            echo "Otherwise __MODE__ is set to 'internal'"
            exit 1
            ;;
        *)  echo "Error parsing input argument: $opt"
            exit 1
            ;;
    esac
done

# Get the current directory => __PREFIX__
export __PREFIX__=$(__get_script_dir ${BASH_SOURCE[0]})

# Get the script to run
script="$1"
shift

# Get the directory of the called script => __DIR__
export __DIR__=$(__get_script_dir $script)

export __MODE__="internal"
script_path=$(which $script)
if [[ "${script_path}" =~ ^/.* ]]
then
    if [[ ! "${script_path}" =~ "${__PREFIX__}" ]]
    then
        __MODE__="external"
        PATH=$PATH:${__PREFIX__}/opt/bin:${__PREFIX__}/opt/util
        unset __DIR__
    fi
fi

# Execute the script with remaining arguments
exec "$script" "$@"
