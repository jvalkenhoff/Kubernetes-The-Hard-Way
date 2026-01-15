#!/usr/bin/env bash

count=${1:-5}

for ((i=0; i<count; i++)); do
  printf "52:54:00:%02x:%02x:%02x\n" \
    $((RANDOM % 256)) \
    $((RANDOM % 256)) \
    $((RANDOM % 256))
done
