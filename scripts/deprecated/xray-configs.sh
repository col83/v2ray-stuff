#!/usr/bin/bash

URL=""

type_filter_exclude="type=xhttp|type=grpc|type=raw"
country_filter="🇷🇺|🇩🇪|🇫🇮|🇱🇻|🇵🇱|🇸🇪|🇳🇱|🇫🇷"

clip_command=""

if command -v wl-copy > /dev/null 2>&1; then
    clip_command="wl-copy"

elif command -v xclip > /dev/null 2>&1; then
    clip_command="xclip -selection clipboard"
fi

if [ -n "$clip_command" ]; then
    curl -s "${URL}" | rg "${country_filter}" | rg -v "${type_filter_exclude}" | ${clip_command}
else
    echo
    curl -s "${URL}" | rg "${country_filter}" | rg -v "${type_filter_exclude}"
    echo
fi
