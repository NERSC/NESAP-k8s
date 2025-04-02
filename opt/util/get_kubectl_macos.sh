#!/usr/bin/env bash
set -eu

pushd ${__PREFIX__}/opt/bin

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl"
chmod u+x kubectl

popd

