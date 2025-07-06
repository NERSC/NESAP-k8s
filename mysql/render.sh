#!/usr/bin/env bash
set -eu
pushd ${__PREFIX__}/mysql

${__PREFIX__}/opt/bin/simple-templates.ex --dir  \
    --resource ".*/templates/.*.[yaml|txt|tpl]$" \
    template                                     \
    settings.toml                                \
    "rendered/{{{name}}}"

popd
