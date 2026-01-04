## Step 1: Clean the Disk

### VM Check
Stop any VMs
```
sudo virsh list
sudo virsh shutdown <vm-name>
```

Wait until it's fully stopped:
`sudo virsh list --all`

### Remove Pools
Check any pools:
`sudo virsh pool-list --all`

Remove the pool:
```
sudo virsh pool-destroy <pool_name>
sudo virsh pool-undefine <pool_name>
```

### Volume Check
Check what lives on the partition:
`lsblk -f /dev/nvme0n1p6`

You can list LVM objects
Physical volume:
`sudo pvs`

```
  PV             VG  Fmt  Attr PSize    PFree
  /dev/nvme0n1p6 k8s lvm2 a--  <250.00g <90.00g
```

Volume Groups:
`sudo vgs`

```
  VG  #PV #LV #SN Attr   VSize    VFree
  k8s   1   4   0 wz--n- <250.00g <90.00g
```

Logical Volumes:
`sudo lvs`

```
  LV            VG  Attr       LSize  Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
  control-plane k8s -wi-a----- 40.00g
  worker1       k8s -wi-a----- 40.00g
  worker2       k8s -wi-a----- 40.00g
  worker3       k8s -wi-a----- 40.00g
```

### Remove Volumes
Deactivate all logical volumes
`sudo vgchange -an <vg_name>`

Remove the volume group
`sudo vgremove <vg_name>`

Remove the physical volume
`sudo pvremove /dev/nvme0n1p6`

Wipe for extra security
`sudo wipefs -a /dev/nvme0n1p6`

### Remove Networking
Remove any bridges
```
sudo virsh net-destroy k8s-net
sudo virsh net-undefine k8s-net
```

Make sure only the default and virbr0 bridge lives here:
`ls /var/lib/libvirt/dnsmasq/`

If using NetworkManager, tell it to ignore any virtual bridge:
```
sudo tee /etc/NetworkManager/conf.d/99-libvirt.conf <<'EOF'
[keyfile]
unmanaged-devices=interface-name:virbr*
EOF
```


***Reboot the system***

---
## Step 2: Create volumes

### Volumes
Create the physical volume and volume group:
```
sudo pvcreate /dev/nvme0n1p6
sudo vgcreate k8s /dev/nvme0n1p6
```

### Pools
Define an LVM pool that points at the VG
```
sudo virsh pool-define-as k8s_nodes logical --source-name k8s
sudo virsh pool-start k8s_nodes
sudo virsh pool-autostart k8s_nodes
```

### Logical Volumes
Create one LV per worker using libvirt
```
sudo virsh vol-create-as k8s_nodes control-plane 40G --format raw
sudo virsh vol-create-as k8s_nodes worker1 40G --format raw
sudo virsh vol-create-as k8s_nodes worker2 40G --format raw
sudo virsh vol-create-as k8s_nodes worker3 40G --format raw
sudo virsh vol-create-as k8s_nodes jumpbox 20G --format raw


sudo vgs
sudo lvs -a -o +devices
sudo virsh pool-list --all
sudo virsh vol-list k8s_nodes
sudo pvdisplay /dev/nvme0n1p6
sudo vgdisplay /dev/nvme0n1p6
```

### Network creation
Pick a subnet that won’t collide with your home network. Example:
- Network: `10.20.0.0/24`
- Gateway (libvirt): `10.20.0.1` 
- Jumpbox: `10.20.0.5`
- Control plane: `10.20.0.10`
- Workers: `10.20.0.11-13`

Create the network XML:
```xml
<network>
  <name>k8s-net</name>
  <forward mode='nat'/>
  <bridge name='virbr20' stp='on' delay='0'/>
  <ip address='10.20.0.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='10.20.0.100' end='10.20.0.254'/>
      <!-- Static leases (fill in MAC addresses after VM creation) -->
      <!--
      <host mac='52:54:00:aa:bb:10' name='jumpbox' ip='10.20.0.5'/>
      
      <host mac='52:54:00:aa:bb:10' name='control-plane' ip='10.20.0.10'/>
      <host mac='52:54:00:aa:bb:11' name='worker1'       ip='10.20.0.11'/>
      <host mac='52:54:00:aa:bb:12' name='worker2'       ip='10.20.0.12'/>
      <host mac='52:54:00:aa:bb:13' name='worker3'       ip='10.20.0.13'/>
      -->
    </dhcp>
  </ip>
</network>
```

Define and start the network
```
sudo virsh net-define k8s-net.xml
sudo virsh net-start k8s-net
sudo virsh net-autostart k8s-net
sudo virsh net-list --all
```

---
## Step 3: VM Installation

### ISO
Download the Debian 12 iso `debian-12.12.0-amd64-netinst.iso`

### Headless Install
Control Plane:
```
sudo virt-install \
	--name control-plane \
	--memory 6144 --vcpus 2 \
	--disk path=/dev/k8s/control-plane,format=raw \
	--os-variant=debian12 \
	--location /home/zangetsu/Projects/k8s/debian-12.12.0-amd64-netinst.iso \
	--extra-args="console=ttyS0, 115200n8 serial" \
	--network network=k8s-net,model=virtio \
	--graphics none \
	--console pty,target_type=serial
```


Workers:
```
sudo virt-install \
	--name worker1 \
	--memory 4096 \
	--vcpus 2 \
	--disk path=/dev/k8s/worker1,format=raw \
	--os-variant=debian12 \
	--location /home/zangetsu/Projects/k8s/debian-12.12.0-amd64-netinst.iso \
	--extra-args="console=ttyS0, 115200n8 serial" \
	--network network=k8s-net,model=virtio \
	--graphics none \
	--console pty,target_type=serial
```


Jumpbox:
```
sudo virt-install 
	--name jumpbox \
	--memory 2048 \
	--vcpus 2 \
	--disk path=/dev/k8s/jumpbox,format=raw \
	--os-variant=debian12 \
	--location /home/zangetsu/Projects/k8s/debian-12.12.0-amd64-netinst.iso \
	--extra-args="console=ttyS0, 115200n8 serial" \
	--network network=k8s-net,model=virtio \
	--graphics none \
	--console pty,target_type=serial
```

### Installation Settings
Use following settings during install (pretty much default settings):
- Hostname: `control-plane` / `worker 1-3` / `jumpbox`
- Domain Name: `k8s.local`
- Set root password
- Username: debian
- set username password
- Partitioning: Guided - Use entire disk
	- All Files in one partition
- Package selection: SSH Server, standard system utilities
- Bootloader GRUB: yes
- Install GRUB to main disk (/dev/vda)

---
## Step 4: Networking

### Get MAC addresses
Turn off the VMs
Check the MAC address of every VM:
```
sudo virsh domiflist control-plane
sudo virsh domiflist worker1
sudo virsh domiflist worker2
sudo virsh domiflist worker3
```

- control-plane: `52:54:00:1e:69:8e`
- worker1: `52:54:00:00:e5:00`
- worker2: `52:54:00:20:00:0e`
- worker3: `52:54:00:ef:98:3d`

### Edit Network
Edit the existing k8s-net network:
`sudo virsh net-edit k8s-net`

Add the following lines under `<range ... />`
```
      <host mac='52:54:00:1e:69:8e' name='control-plane' ip='10.20.0.10'/>
      <host mac='52:54:00:00:e5:00' name='worker1' ip='10.20.0.11'/>
      <host mac='52:54:00:20:00:0e' name='worker2' ip='10.20.0.12'/>
      <host mac='52:54:00:ef:98:3d' name='worker3' ip='10.20.0.13'/>
```

### Restart Network
Restart the k8s-net network:
```
sudo virsh net-destroy k8s-net
sudo virsh net-start k8s-net
```

### Reboot VMs
Boot the vms:
```
sudo virsh start control-plane
sudo virsh start worker1
sudo virsh start worker2
sudo virsh start worker3
```

The command: `bridge link` should show bridges that are up:
```
15: vnet0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 master virbr20 state forwarding priority 32 cost 2
16: vnet1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 master virbr20 state forwarding priority 32 cost 2
17: vnet2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 master virbr20 state forwarding priority 32 cost 2
18: vnet3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 master virbr20 state forwarding priority 32 cost 2
```

### IP Check
Enter the VMs to check if the IPs are set correctly:
```
sudo virsh console control-plane
sudo virsh console worker1
sudo virsh console worker2
sudo virsh console worker3
```

In the VM, you can do: `ip addr show`

---
## Step 5: VM Setup
Access the VMs via virsh:
```
sudo virsh console jumpbox

sudo virsh console control-plane
sudo virsh console worker1
sudo virsh console worker2
sudo virsh console worker3
```

### Sudo Setup
On each VM:
```
su -
apt update
apt install -y sudo
usermod -aG sudo debian
exit
logout
```

### SSH Setup on Jumpbox
On the jumpbox, edit `/etc/hosts` add add these lines so it matches the VM hosts:
```
10.20.0.10 control-plane
10.20.0.11 worker1
10.20.0.12 worker2
10.20.0.13 worker3
```

Generate ssh keys on the jumpbox:
`ssh-keygen -t ed25519`

Copy the key to each node:
```bash
ssh-copy-id debian@control-plane
ssh-copy-id debian@worker1
ssh-copy-id debian@worker2
ssh-copy-id debian@worker3
```

---
## Step 6: Node Hardening
We will do more hardening post cluster setup

### SSH Hardening
Access each node via virsh:
```
sudo virsh console control-plane
sudo virsh console worker1
sudo virsh console worker2
sudo virsh console worker3
```

Edit `/etc/ssh/sshd_config`

Make SSH Key only:
```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

Restrict SSH to the Jumpbox only:
```
AllowUsers debian@10.20.0.5
```

Reload ssh service:
`systemctl reload ssh`
### Time Sync and Basics
Install:
```bash
apt install -y ufw chrony curl ca-certificates gnupg lsb-release
systemctl enable --now chrony
```

### Disable Swap
Kubernetes will not run with swap on:
```bash
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab
```

check if swap is turned off (should show no output):
```bash
swapon --show
```

### Kernel modules
Create file `/etc/modules-load.d/k8s.conf`
```bash
overlay
br_netfilter
```

Run:
```bash
modprobe overlay
modprobe br_netfilter
```

### Sysctl Tuning
Create file `/etc/sysctl.d/k8s.conf`
```
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
```

Run `sysctl --system`

### Firewall
Deny all incoming by default, allow outgoing for:
- apt install
- container images
- CNI downloads
- time sync
```bash
ufw default deny incoming
ufw default allow outgoing
```

Allow internal cluster traffic:
```
# Allow internal cluster traffic
ufw allow from 10.20.0.0/24
```

Only allow traffic from the Jumpbox:
```
ufw allow from 10.20.0.5 to any port 22
```

***Control Plane only***
Kube API Server
```
sudo ufw allow from 10.20.0.0/24 to any port 6443
sudo ufw allow from 10.20.0.5 to any port 6443
```

etcd
```
ufw allow from 10.20.0.10 to any port 2379
ufw allow from 10.20.0.10 to any port 2380
```

***Worker nodes only***
Kubelet (kubelet <--> kube api server)
```
ufw allow from 10.20.0.10 to any port 10250
```

NodePort range
```
ufw allow from 10.20.0.0/24 to any proto tcp port 30000:32767
```

Apply changes and check
```
ufw enable
ufw status verbose
```

---
## Step 7: Jumpbox check

### OS & access

✔ Debian 12 installed  
✔ You log in as a **normal user** (e.g. `debian`)  
✔ `sudo` is installed and working  
✔ SSH key-based access works

Verify:
`whoami sudo whoami`

### Networking & name resolution

✔ Jumpbox is on `k8s-net`  
✔ Jumpbox can SSH to **all nodes**  
✔ Stable IP assigned (e.g. `10.20.0.5`)  
✔ `/etc/hosts` contains all nodes

`/etc/hosts` should include:

`10.20.0.10 control-plane 10.20.0.11 worker1 10.20.0.12 worker2 10.20.0.13 worker3`

Verify:

`ssh control-plane ssh worker1`

### Base packages (REQUIRED)

These are **non-negotiable** for PKI + kubectl work.

`sudo apt update sudo apt install -y \   curl \   ca-certificates \   gnupg \   openssl \   jq`

Verify:

`openssl version curl --version jq --version`

### kubectl (client only)

✔ kubectl installed  
✔ Runs as **normal user**  
✔ No kubeconfig yet (this is correct)

Verify:

`kubectl version --client`

Expected:
- Client version shown
- No server connection yet (that’s fine)

### Time synchronization

TLS **will break** if time drifts.

✔ `chrony` installed  
✔ Time synced

`sudo apt install -y chrony sudo systemctl enable --now chrony chronyc tracking`

