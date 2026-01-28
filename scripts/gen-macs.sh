#!/usr/bin/env bash

gen_mac() {
  local seed="$1"
  local hash

  hash=$(echo -n "$seed" | sha256sum | cut -c1-12)

  printf "52:54:00:%s:%s:%s" \
    "${hash:0:2}" \
    "${hash:2:2}" \
    "${hash:4:2}"
}

for name in "$@"; do
  printf "%-10s %s\n" "$name:" "$(gen_mac "$name")"
done
