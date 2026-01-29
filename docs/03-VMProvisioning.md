# Phase 3: Virtual Machine Provisioning
This phase creates the Virtual Machines that will later become Kubernetes nodes. It will install the Virtual Machines in the dedicated LVs defined in the previous steps.

- [Preparation](#preparation)
  - [ISO](#iso)
  - [MAC Pinning](#mac-pinning)
- [Installation](#installation)
  - [Control Plane VM](#control-plane-vm)
  - [Worker Nodes](#worker-nodes)
  - [Jumpbox](#jumpbox)
- [Installation Settings](#installation-settings)
- [Post Installation Access](#post-installation-access)
- [Verify](#verify)

## Preparation
Based on the setup in Phase 1 and 2, the VMs will use raw LVM backend disks, and relies on `virtio` networking. Furthermore, it will use serial console access; no GUI or GUI tools is necessary.
### ISO
Download the Debian netinst ISO. It is available in the [Debian Archive](https://cdimage.debian.org/cdimage/archive/12.12.0/amd64/iso-cd/).
```
debian-12.12.0-amd64-netinst.iso
```

This ISO will be used for ALL nodes.
### MAC Pinning
The MAC addresses has been determined in Phase 2. During installation, it is possible to already pin the MAC addresses, so the VMs immediately recive their desired MAC and IP address. The following list is needed in the next step:

| VM        | MAC Address       |
| --------- | ----------------- |
| `cp1`     | 52:54:00:30:6b:6a |
| `w1`      | 52:54:00:60:c5:59 |
| `w2`      | 52:54:00:06:f8:fa |
| `w3`      | 52:54:00:55:ea:e5 |
| `jumpbox` | 52:54:00:a4:a2:df |

## Installation
### Control Plane VM
Create the Control Plane VM:
```bash
sudo virt-install \
	--name cp1 \
	--memory 4096 --vcpus 2 \
	--disk path=/dev/k8s/cp1,format=raw \
	--os-variant=debian12 \
	--location /home/zangetsu/Projects/k8s/debian-12.12.0-amd64-netinst.iso \
	--extra-args="console=ttyS0, 115200n8 serial" \
	--network network=k8s-net,model=virtio,mac="52:54:00:30:6b:6a" \
	--graphics none \
	--console pty,target_type=serial
```

### Worker Nodes
Make sure to include the correct MAC address for each VM:
- w1: 52:54:00:60:c5:59
- w2: 52:54:00:06:f8:fa
- w3: 52:54:00:55:ea:e5

**w1**
```bash
sudo virt-install \
	--name w1 \
	--memory 4096 \ 
	--vcpus 2 \
	--disk path=/dev/k8s/w1,format=raw \
	--os-variant=debian12 \
	--location /home/zangetsu/Projects/k8s/debian-12.12.0-amd64-netinst.iso \
	--extra-args="console=ttyS0, 115200n8 serial" \
	--network network=k8s-net,model=virtio,mac="52:54:00:60:c5:59" \
	--graphics none \
	--console pty,target_type=serial
```

**w2**
```bash
sudo virt-install \
	--name w2 \
	--memory 4096 \ 
	--vcpus 2 \
	--disk path=/dev/k8s/w2,format=raw \
	--os-variant=debian12 \
	--location /home/zangetsu/Projects/k8s/debian-12.12.0-amd64-netinst.iso \
	--extra-args="console=ttyS0, 115200n8 serial" \
	--network network=k8s-net,model=virtio,mac="52:54:00:06:f8:fa" \
	--graphics none \
	--console pty,target_type=serial
```

**w3**
```bash
sudo virt-install \
	--name w3 \
	--memory 4096 \ 
	--vcpus 2 \
	--disk path=/dev/k8s/w3,format=raw \
	--os-variant=debian12 \
	--location /home/zangetsu/Projects/k8s/debian-12.12.0-amd64-netinst.iso \
	--extra-args="console=ttyS0, 115200n8 serial" \
	--network network=k8s-net,model=virtio,mac="52:54:00:55:ea:e5" \
	--graphics none \
	--console pty,target_type=serial
```

### Jumpbox
```bash
sudo virt-install \
	--name jumpbox \
	--memory 2048 --vcpus 1 \
	--disk path=/dev/k8s/jumpbox,format=raw \
	--os-variant=debian12 \
	--location /home/zangetsu/Projects/k8s/debian-12.12.0-amd64-netinst.iso \
	--extra-args="console=ttyS0, 115200n8 serial" \
	--network network=k8s-net,model=virtio,mac="52:54:00:a4:a2:df" \
	--graphics none \
	--console pty,target_type=serial
```

## Installation Settings
Use the following steps to consistently setup the VM:
**Localization**
1. **Country:** Netherlands 
2. **Locales:** United States (en_US.UTF-8)
3. **Keymap** American English

*loading components...*

**Configure Network**
1. **Hostname:** `w1`, `w2`, `w3`, `cp1`, `jumpbox`
2. **Domain Name:** `k8s.local`

**Users Setup**
1. **Root password:** `<password>`
2. **Verify password**
3. **Name for new user:** `debian`
4. **Username:** `debian`
5. **User password:** `<password>`
6. **Verify password**

**Partition Disks**
1. **Partitioning method**: guided - use entire disk
2. **Select disk**: Virtual Disk 1 - vda (can only choose one)
3. **partitioning scheme**: all files in one partition
4. **Partition Table Overview**: Finish partitioning - write changes to disk

*Installing base system...*

**Package Manager**
1. **Scan extra installation media**: no
2. **Mirror country**: Netherlands
3. **Archive mirror**: deb.debian.org
4. **HTTP Proxy**: leave empty

**Software Selection**
1. **DESELECT:** Debian desktop environment, GNOME (with spacebar)
2. **SELECT:** SSH server, standard system utilities

**Configure GRUB**
1. **Boot loader on primary drive**: yes
2. **Device for bootloader**: /dev/vda

Reboot the system.

## Post Installation Access
Each VM is reachable with:
```bash
sudo virsh console cp1
sudo virsh console w1
sudo virsh console w2
sudo virsh console w3
sudo virsh console jumpbox
```

Once entering the console, exiting is done with:
```nginx
Ctrl + ]
```

## Verify
The following checks verify if the VMs are installed correctly:
- [ ] All VMs exist
- [ ] All VMs boot successfully
- [ ] VMs have their pinned MAC Addresses

```bash
# list all the VMs
sudo virsh list --all

# lists their MAC addresses
sudo virsh domiflist w1
sudo virsh domiflist w2
sudo virsh domiflist w3
sudo virsh domiflist cp1
sudo virsh domiflist jumpbox
```
