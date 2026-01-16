#!/usr/bin/env bash
set -euo pipefail

# Define binary final locations
BASE_DIR="${HOME}/downloads"
CLIENT_DIR="${BASE_DIR}/client"
CTRL_DIR="${BASE_DIR}/controller"
WORKER_DIR="${BASE_DIR}/worker"
CNI_DIR="${BASE_DIR}/cni-plugins"

LIST_FILE="${1:-/tmp/downloads.txt}"

if [[ ! -f "$LIST_FILE" ]]; then
  echo "ERROR: downloads list not found: $LIST_FILE" >&2
  exit 1
fi

mkdir -p "$CLIENT_DIR" "$CTRL_DIR" "$WORKER_DIR" "$CNI_DIR"

# temporary path
WORKDIR="$(mktemp -d /tmp/k8s-bin.XXXXXX)"
DL_DIR="${WORKDIR}/dl"
EXTRACT_DIR="${WORKDIR}/extract"
mkdir -p "$DL_DIR" "$EXTRACT_DIR"

# safe cleanup function
cleanup() {
  rm -rf "$WORKDIR";
}

# makes sure cleanup always happens at the end
trap cleanup EXIT

# download function
download() {
  local url="$1"
  local out="$2"

  wget -q --show-progress --https-only --timestamping -O "$out" "$url"
}

echo "Downloading binaries from $LIST_FILE"
while IFS= read -r url; do
  [[ -z "$url" ]] && continue
  [[ "$url" =~ ^[[:space:]]*# ]] && continue

  fname="$(basename "$url")"
  out="${DL_DIR}/${fname}"

  echo " - syncing $fname"
  download "$url" "$out"
done<"$LIST_FILE"

install_bin() {
  local src="$1"
  local dst_dir="$2"
  local dst_name="${3:-$(basename "$src")}"

  install -m 0755 "$src" "${dst_dir}/${dst_name}"
}

echo "Installing Kubernetes binaries"
