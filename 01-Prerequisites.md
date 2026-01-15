# Phase 1: Environment Prep
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
## Step 4: VM Post installation

### Access VMs
You can access each VM with:
```
sudo virsh console control-plane
sudo virsh console worker1
sudo virsh console worker2
sudo virsh console worker3

sudo virsh console jumpbox
```

### Sudo
On each VM:
```
apt update
apt install -y sudo
usermod -aG sudo debian
```

Logout and back in:
```
exit
logout
```

Check if you can become sudo with:
`sudo -i`
or
`su -`

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
```xml
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
```shell
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
## Step 6: Prepare cluster nodes
Access each node via virsh
### Base Packages
Install:
```bash
apt install -y ufw chrony curl ca-certificates gnupg lsb-release
```

### SSH
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
TLS **will break** if time is out of sync.
```
systemctl enable --now chrony
chronyc tracking
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
## Step 7: Prepare Jumpbox
Access jumpbox via virsh

### Base packages
```
sudo apt update
sudo apt install -y curl wget tree ca-certificates gnupg openssl jq chrony
```

Verify:
`openssl version curl --version` 
`jq --version`

### Time synchronization
TLS **will break** if time is out of sync.
```
systemctl enable --now chrony
chronyc tracking
```

### SSH Setup
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

Verify:
```
ssh debian@control-plane 
ssh debian@worker1
ssh debian@worker2
ssh debian@worker3
```

### kubectl
Download kubectl:
```
wget https://dl.k8s.io/v1.34.2/bin/linux/amd64/kubectl
```

make it executable:
```
chmod +x ~/kubectl
```

move it to `/usr/local/bin`
```
sudo cp ~/kubectl /usr/local/bin/
```

Verify:
`kubectl version --client`

Should show:
```
Client Version: v1.34.2
Kustomize Version: v5.7.1
```

---
# Phase 2: CA Setup
We will setup the CA entirely from scratch. It uses a Root CA Setup. If you want to know more how it's setup, check:
[PKI certificates and requirements | Kubernetes](https://kubernetes.io/docs/setup/best-practices/certificates/) - Official Kubernetes docs about the CA requirements
[A.5. Creating Your Own Certificates | Security Guide | Red Hat AMQ | 6.2 | Red Hat Documentation](https://docs.redhat.com/en/documentation/red_hat_amq/6.2/html/security_guide/createcerts) - Redhat docs for setting up own CA
[kubernetes-the-harder-way/docs/04_Bootstrapping_Kubernetes_Security.md at linux · ghik/kubernetes-the-harder-way](https://github.com/ghik/kubernetes-the-harder-way/blob/linux/docs/04_Bootstrapping_Kubernetes_Security.md#the-service-account-token-signing-certificate) - This phase roughly follows this guide

## Step 1. Prepare CA Directory

### Directory setup
On the jumpbox, run:
```
mkdir -p ~/k8s-ca/{certs,crl,newcerts,private,config}
cd ~/k8s-ca
chmod 700 private
```

### Default state
This creates the database and serial increments:
```
touch index.txt
echo 1000 > serial
echo 1000 > crlnum
```

## Step 2. Build Root CA
### CA config
Create `config/root-ca.cnf`
```ini
[ ca ]
default_ca = k8s_root_ca

[ k8s_root_ca ]
dir           = /home/debian/k8s-ca
certs         = $dir/certs
crl_dir       = $dir/crl
new_certs_dir = $dir/newcerts
database      = $dir/index.txt
serial        = $dir/serial
crlnumber     = $dir/crlnum

private_key = $dir/private/ca.key
certificate = $dir/certs/ca.crt

default_md    = sha256
default_days  = 365
policy        = k8s_policy

unique_subject  = no
copy_extensions = copy
```

### CA Policy
Within the same file, add the policy:
```ini
[ k8s_policy ]
commonName              = supplied
organizationName        = optional
organizationalUnitName  = optional
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
emailAddress            = optional
```

### CSR defaults
In `config/root-ca.cnf`, append default settings for CSRs:
```ini
[ req ]
default_bits        = 4096
default_md          = sha256
prompt              = no
distinguished_name  = req_dn
```

### Root CA DN
```ini
[ req_dn ]
CN  = kubernetes-root-ca
O   = kubernetes
```

### Extensions
```ini
[ v3_ca ]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always,issuer
basicConstraints        = critical, CA:true
keyUsage                = critical, keyCertSign, cRLSign
```

Save the file

---
## Step 3. Create Root CA

### Private Key
generate the root ca private key:
```
openssl genrsa -out private/ca.key 4096
chmod 600 private/ca.key
```

### Root CA
Run this to generate the root CA:
```
openssl req -new -x509 -key private/ca.key -out certs/ca.crt -days 3650 -config config/root-ca.cnf -extensions v3_ca
```

Verify the CA:
```
openssl x509 -in certs/ca.crt -noout -text
```

You should see:
`CA:TRUE`
`Key Usage: Certificate Sign, CRL Sign`

---
## Step 4. CA Profiles
not necessary. But in real CA you never issue certs without certificate profiles.

### Add to CA Config
open the CA config to add the certificate profiles:
```
vim ~/k8s-ca/config/root-ca.cnf
```
#### Client
Issues for kubectl, controller-manager, scheduler

```ini
[ client_cert ]
basicConstraints        = CA:FALSE
keyUsage                = critical, digitalSignature, keyEncipherment
extendedKeyUsage        = clientAuth
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid,issuer
```

#### Server
Issues for the API server
```ini
[ server_cert ]
basicConstraints        = CA:FALSE
keyUsage                = critical, digitalSignature, keyEncipherment
extendedKeyUsage        = serverAuth
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid,issuer
```

#### Peer
Issues for the kubelet
```ini
[ peer_cert ]
basicConstraints        = CA:FALSE
keyUsage                = critical, digitalSignature, keyEncipherment
extendedKeyUsage        = serverAuth, clientAuth
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid,issuer
```

---
## Step 5. Certificates

We will setup certificates for each component in the following order:
1. CSR config creation
2. CSR creation against private key and config
3. Certificate creation by signing the CSR
### 1. kubectl
Create `config/admin.cnf`
```ini
[ req ]
default_bits        = 4096
prompt              = no
default_md          = sha256
distinguished_name  = dn

[ dn ]
CN  = admin
O   = system:masters
```

Create private key, create CSR with private key and config:
```
openssl genrsa -out private/admin.key 4096

openssl req -new -key private/admin.key -out csr/admin.csr -config config/admin.cnf
```

Sign the CSR using the CA, **client_cert** profile:
```
openssl ca -config config/root-ca.cnf -extensions client_cert -in csr/admin.csr -out certs/admin.crt
```

Verify by running:
```
openssl x509 -in certs/admin.crt -noout -text | grep -A2 "Extended Key Usage"
```

You should see:
```
TLS Web Client Authentication
```

### 2. Controller Manager
Create `config/kube-controller-manager.cnf`
```ini
[ req ]
prompt            = no
default_md        = sha256
distinguished_name = dn

[ dn ]
CN = system:kube-controller-manager
```

Create private key, create CSR with private key and config:
```
openssl genrsa -out private/kube-controller-manager.key 4096

openssl req -new -key private/kube-controller-manager.key -out csr/kube-controller-manager.csr -config config/kube-controller-manager.cnf
```

Sign the CSR using the CA, **client_cert** profile:
```
openssl ca -config config/root-ca.cnf -extensions client_cert -in csr/kube-controller-manager.csr -out certs/kube-controller-manager.crt
```

Verify by running:
```
openssl x509 -in certs/kube-controller-manager.crt -noout -text | grep -A2 "Extended Key Usage"
```

You should see:
```
TLS Web Client Authentication
```

### 3. Scheduler
Create `config/kube-scheduler.cnf`
```ini
[ req ]
prompt              = no
default_md          = sha256
distinguished_name  = dn

[ dn ]
CN = system:kube-scheduler
```

Create private key, create CSR with private key and config:
```
openssl genrsa -out private/kube-scheduler.key 4096

openssl req -new -key private/kube-scheduler.key -out csr/kube-scheduler.csr -config config/kube-scheduler.cnf
```

Sign the CSR using the CA, **client_cert** profile:
```
openssl ca -config config/root-ca.cnf -extensions client_cert -in csr/kube-scheduler.csr -out certs/kube-scheduler.crt
```

Verify by running:
```
openssl x509 -in certs/kube-scheduler.crt -noout -text | grep -A2 "Extended Key Usage"
```

You should see:
```
TLS Web Client Authentication
```

### 4. API Server
The API server works a bit differently. the SANs are very important here:
```ini
[ req ]
default_bits        = 4096
prompt              = no
default_md          = sha256
distinguished_name  = dn
req_extensions      = req_ext

[ dn ]
CN = kube-apiserver

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
DNS.5 = control-plane
DNS.6 = control-plane.k8s.local
IP.1  = 10.20.0.10
IP.2  = 127.0.0.1
```

generate key + csr:
```
openssl genrsa -out private/kube-apiserver.key 4096

openssl req -new -key private/kube-apiserver.key -out csr/kube-apiserver.csr -config config/kube-apiserver.cnf
```

Sign the CSR using the CA, **server_cert** profile:
```
openssl ca -config config/root-ca.cnf -extensions server_cert -in csr/kube-apiserver.csr -out certs/kube-apiserver.crt
```

Verify by running, this time look for Subject Alternative Name:
```
openssl x509 -in certs/kube-apiserver.crt -noout -text | grep -A1 "Subject Alternative Name"
```

You should see:
```
X509v3 Subject Alternative Name:
    DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, DNS:control-plane, DNS:control-plane.k8s.local, IP Address:10.20.0.10, IP Address:127.0.0.1
```

### 5. Kubelets
For each worker we need a certificate for the kubelet. The following steps can be repeated for worker2, worker3

create `config/kubelet-worker1.cnf`
```ini
[ req ]
prompt  = no
default_md  = sha256
distinguished_name  = dn
req_extensions      = req_ext

[ dn ]
CN = system:node:worker1
O  = system:nodes

[ req_ext ]
subjectAltName  = @alt_names

[ alt_names ]
DNS.1 = worker1
DNS.2 = worker1.k8s.local
IP.1  = 10.20.0.11
```

generate key + csr:
```
openssl genrsa -out private/kubelet-worker1.key 4096

openssl req -new -key private/kubelet-worker1.key -out csr/kubelet-worker1.csr -config config/kubelet-worker1.cnf
```

Sign the CSR using the CA, **peer_cert** profile:
```
openssl ca -config config/root-ca.cnf -extensions peer_cert -in csr/kubelet-worker1.csr -out certs/kubelet-worker1.crt
```

Verify, no `grep` because we need to look in multiple places:
```
openssl x509 -in certs/kubelet-worker1.crt -noout -text
```

Subject:
```
Subject: CN = system:node:worker1, O = system:nodes
```

Extended Key Usage:
```
X509v3 Extended Key Usage:
    TLS Web Server Authentication, TLS Web Client Authentication
```

Subject Alternative Name:
```
X509v3 Subject Alternative Name:
    DNS:worker1, DNS:worker1.k8s.local, IP Address:10.20.0.11
```

Repeat for worker2:
- CN: `system:node:worker2`
- IP: `10.20.0.12`

worker3:
- CN: `system:node:worker3`
- IP: `10.20.0.12`

### 6. kube-proxy
Although kube-proxy runs on every worker node, it has one single identity. We only need to create one certificate.
create `config/kube-proxy.cnf`
```ini
[ req ]
prompt = no
default_md = sha256
distinguished_name = dn

[ dn ]
CN = system:kube-proxy
```

Create private key, create CSR with private key and config:
```
openssl genrsa -out private/admin.key 4096

openssl req -new -key private/admin.key -out csr/admin.csr -config config/admin.cnf
```

Sign the CSR using the CA, **client_cert** profile:
```
openssl ca -config config/root-ca.cnf -extensions client_cert -in csr/admin.csr -out certs/admin.crt
```

Verify by running:
```
openssl x509 -in certs/admin.crt -noout -text | grep -A2 "Extended Key Usage"
```

You should see:
```
TLS Web Client Authentication
```


---

## Future:
Multiple master nodes
predefined search domain in k8s-net
static pods
CRI-O 
crun
