#!/usr/bin/env bash
jq -r 'select(.type=="assistant" and .message.usage) | "\(.timestamp[5:16] | sub("T";" ")) \(((.message.usage.input_tokens + (.message.usage.cache_read_input_tokens//0) + (.message.usage.cache_creation_input_tokens//0)) / 1000 | floor))k"' "$1"
