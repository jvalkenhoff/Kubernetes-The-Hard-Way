#!/usr/bin/env bash

seed="$1"

if [[ -z "$seed" ]]; then
  echo "Usage: $0 <seed>"
  exit 1
fi

hash=$(echo -n "$seed" | sha256sum | cut -c1-12)

printf "52:54:00:%s:%s:%s\n" \
  "${hash:0:2}" \
  "${hash:2:2}" \
  "${hash:4:2}"

