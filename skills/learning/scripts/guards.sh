#!/usr/bin/env bash
jq -r 'select(.type == "attachment" or .type == "system") | (.timestamp // "")[5:16] as $t | .type as $k | [.. | strings | select(test("^(CTX GUARD|LIMIT GUARD|Usage limit reached)"))] | unique | .[] | "\($t | sub("T";" ")) \($k): \(.[0:260] | gsub("\n";" "))"' "$1"
