#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Layout: "downloads bundles" on the jumpbox
# - client:      client-side tools (kubectl, etcdctl)
# - controller:  control-plane + node-runtime (static pods => needs kubelet+containerd+runc+crictl)
# - worker:      node-runtime (kubelet+containerd+runc+crictl, plus kube-proxy if you use it)
# - cni-plugins: CNI plugin binaries only (no README/LICENSE)
# ------------------------------------------------------------
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

#ensure destination directories exist
mkdir -p "$CLIENT_DIR" "$CTRL_DIR" "$WORKER_DIR" "$CNI_DIR"

# temporary path
WORKDIR="$(mktemp -d /tmp/k8s-bin.XXXXXX)"
DL_DIR="${WORKDIR}/dl"
EXTRACT_DIR="${WORKDIR}/extract"
mkdir -p "$DL_DIR" "$EXTRACT_DIR"

# safe cleanup function
cleanup() {
  rm -rf "$WORKDIR"
}

# makes sure cleanup always happens at the end
trap cleanup EXIT

# ------------------------------------------------------------
# Download artifacts
# ------------------------------------------------------------
download() {
  local url="$1"

  wget -q --show-progress --https-only --timestamping -P "$DL_DIR" "$url"
}

echo "Downloading binaries from $LIST_FILE"
while IFS= read -r url; do
  [[ -z "$url" ]] && continue
  [[ "$url" =~ ^[[:space:]]*# ]] && continue

  fname="$(basename "$url")"

  echo " - syncing $fname"
  download "$url"
done<"$LIST_FILE"


# ------------------------------------------------------------
# Install helper (copy + chmod in one step)
# ------------------------------------------------------------
install_bin() {
  local src="$1"
  local dst_dir="$2"
  local dst_name="${3:-$(basename "$src")}"

  install -m 0755 "$src" "${dst_dir}/${dst_name}"
}

# ------------------------------------------------------------
# Kubernetes core binaries
# ------------------------------------------------------------
echo "Installing Kubernetes binaries"

# control plane
install_bin "${DL_DIR}/kube-apiserver"          "$CTRL_DIR"
install_bin "${DL_DIR}/kube-controller-manager" "$CTRL_DIR"
install_bin "${DL_DIR}/kube-scheduler"          "$CTRL_DIR"

# worker nodes
install_bin "${DL_DIR}/kubelet"                 "$WORKER_DIR"
install_bin "${DL_DIR}/kubelet"                 "$CTRL_DIR"

install_bin "${DL_DIR}/kube-proxy"              "$WORKER_DIR"
install_bin "${DL_DIR}/kube-proxy"              "$CTRL_DIR"

# kubectl
install_bin "${DL_DIR}/kubectl"                 "$CLIENT_DIR"

# ------------------------------------------------------------
# runc
# ------------------------------------------------------------
echo "Installing runc"

# download name is runc.amd64 , changing to runc
install_bin "${DL_DIR}/runc.amd64"              "$WORKER_DIR" "runc"
install_bin "${DL_DIR}/runc.amd64"              "$CTRL_DIR" "runc"

# ------------------------------------------------------------
# crictl
# ------------------------------------------------------------
echo "Installing crictl"

tar -xzf "${DL_DIR}/crictl-"*"-linux-amd64.tar.gz" -C "$EXTRACT_DIR"
install_bin "${EXTRACT_DIR}/crictl"             "$WORKER_DIR"
install_bin "${EXTRACT_DIR}/crictl"             "$CTRL_DIR"
rm -rf "${EXTRACT_DIR}/crictl"

# ------------------------------------------------------------
# containerd
# ------------------------------------------------------------
echo "Installing containerd"

tar -xzf "${DL_DIR}/containerd-"*"-linux-amd64.tar.gz" -C "$EXTRACT_DIR"
for b in containerd containerd-shim-runc-v2 ctr; do
  if [[ -f "${EXTRACT_DIR}/bin/${b}" ]]; then
    install_bin "${EXTRACT_DIR}/bin/${b}" "$WORKER_DIR"
    install_bin "${EXTRACT_DIR}/bin/${b}" "$CTRL_DIR"
  else
    echo "containerd archive did not contain bin/${b}" >&2
  fi
done
rm -rf "${EXTRACT_DIR:?}/"*

# ------------------------------------------------------------
# CNI plugins
# ------------------------------------------------------------
echo "Installing CNI Plugins"

tar -xzf "${DL_DIR}/cni-plugins-linux-amd64-"*".tgz" -C "$CNI_DIR"
# ensure executables
chmod 0755 "$CNI_DIR"/*
# Removing non executable files
find "$CNI_DIR" -type f ! -executable -delete

# ------------------------------------------------------------
# etcd + etcdctl
# ------------------------------------------------------------
echo "Installing etcd and etcdctl"

tar -xzf "${DL_DIR}/etcd-v"*"-linux-amd64.tar.gz" -C "$EXTRACT_DIR"
ETCD_ROOT="$(find "$EXTRACT_DIR" -maxdepth 1 -type d -name 'etcd-v*-linux-amd64' | head -n1)"
if [[ -z "${ETCD_ROOT:-}" ]]; then
  echo "ERROR: could not locate extarcted etcd directory" >&2
  exit 1
fi

# etcd runs on controllers
install_bin "${ETCD_ROOT}/etcd"     "$CTRL_DIR"
# etcdctl is a client tool
install_bin "${ETCD_ROOT}/etcdctl"  "$CLIENT_DIR"

rm -rf "${EXTRACT_DIR:?}/"*

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo "Summary:"
echo " Controller: $(find "$CTRL_DIR" -maxdepth 1 -type f | wc -l) files -> $CTRL_DIR"
echo " Worker: $(find "$WORKER_DIR" -maxdepth 1 -type f | wc -l) files -> $WORKER_DIR"
echo " Client: $(find "$CLIENT_DIR" -maxdepth 1 -type f | wc -l) files -> $CLIENT_DIR"
echo " CNI: $(find "$CNI_DIR" -maxdepth 1 -type f | wc -l) files -> $CNI_DIR"

echo " Done"
