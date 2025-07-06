#!/usr/bin/env bash
set -eu

# Initialize our own variables
OPTIND=1         # Reset in case getopts has been used previously in the shell.
unset -v name
unset -v arch

while getopts "h?n:a:" opt; do
    case "$opt" in
    h|\\?)        # Display help information
        echo "Usage: $0 [-n OS] [-a architecture]"
        echo " - The OS name must one of {darwin, linux}"
        echo " - The system architecture must one of {amd64, arm64}"
        echo "Both arguments (-n, and -a) are mandatory"
        exit 0
        ;;
    n)  name=$OPTARG        # Set the name
        ;;
    a)  arch=$OPTARG
        ;;
    *)  echo "Error parsing input argument: $opt"
        exit 1
        ;;
    esac
done

if [[ -z ${name+x} || -z ${arch+x} ]]
then
    echo "Error: missing parameter (either -n or -a)"
    exit 1
fi

pushd ${__PREFIX__}/opt/bin

version="3.18.3"
# cleanup old downloads
rm -fr helm-v${version}-${name}-${arch}.tar.gz*

wget "https://get.helm.sh/helm-v${version}-${name}-${arch}.tar.gz"
tar xvf helm-v${version}-${name}-${arch}.tar.gz
ln -s ${name}-${arch}/helm

popd

