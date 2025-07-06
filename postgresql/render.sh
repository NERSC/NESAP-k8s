#!/usr/bin/env bash
set -eu
pushd ${__PREFIX__}/postgresql

${__PREFIX__}/opt/bin/simple-templates.ex --dir  \
    --resource ".*/templates/.*.[yaml|txt|tpl]$" \
    template                                     \
    settings.toml                                \
    "rendered/{{{app_name}}}"

popd
