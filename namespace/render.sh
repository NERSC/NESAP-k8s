#!/usr/bin/env bash
set -eu
pushd ${__DIR__}

${__PREFIX__}/opt/bin/simple-templates.ex template.yaml settings.toml          \
    "rendered/{{{name}}}.yaml"

popd
