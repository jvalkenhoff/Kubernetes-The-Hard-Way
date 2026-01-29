#!/usr/bin/env bash
set -euo pipefail

ISO="/home/zangetsu/Projects/k8s/debian-12.12.0-amd64-netinst.iso"
NETWORK="k8s-net"
OS_VARIANT="debian12"
MEMORY=4096
VCPUS=2
DISK_BASE="/dev/k8s"

declare -A VM_MACS=(
  [w1]="52:54:00:60:c5:59"
  [w2]="52:54:00:06:f8:fa"
  [w3]="52:54:00:55:ea:e5"
)

for VM in "${!VM_MACS[@]}"; do
  MAC="${VM_MACS[$VM]}"
  DISK="${DISK_BASE}/${VM}"

  echo "Creating VM: ${VM} (MAC=$MAC})"

  sudo virt-install \
    --name "$VM" \
    --memory "$MEMORY" \
    --vcpus "$VCPUS" \
    --disk "path=$DISK,format=raw" \
    --os-variant "$OS_VARIANT" \
    --location "$ISO" \
    --extra-args="console=ttyS0,115200n8 serial" \
    --network "network=$NETWORK,model=virtio,mac=$MAC" \
    --graphics none \
    --console pty,target_type=serial \
    --wait 0 \
    --noautoconsole

  echo "VM ${VM} started (detached)"
done

echo "All VMs defined and booting."
echo "You can attach later with: virsh console <vm-name>"
