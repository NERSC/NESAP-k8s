#!/usr/bin/env bash
set -eu

pushd ${__PREFIX__}/opt/bin

# cleanup old downloads
rm -r helm-v3.17.2-darwin-arm64.tar.gz*

wget "https://get.helm.sh/helm-v3.17.2-darwin-arm64.tar.gz"
tar xvf helm-v3.17.2-darwin-arm64.tar.gz
ln -s darwin-arm64/helm

popd

