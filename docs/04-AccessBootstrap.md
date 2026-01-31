# Phase 4: Access Boostrap
This phase establishes **SSH access** to all nodes via a jumpbox and **removes reliance on serial console access**. **This will be the last and only phase where commands will be executed as `root` user**. In subsequent phases, root access will _only_ be possible via `sudo`.

- [Goal](#goal)
- [Access Model](#access-model)
   * [Topology](#topology)
   * [Target Access Matrix](#target-access-matrix)
- [Host --> Jumpbox](#host-jumpbox)
   * [Hostname resolution](#hostname-resolution)
   * [Access](#access)
- [Nodes: Privilege Escalation](#nodes-privilege-escalation)
   * [Sudo](#sudo)
   * [Add user to sudo group](#add-user-to-sudo-group)
   * [Verify sudo](#verify-sudo)
- [Nodes: Prepare SSH](#nodes-prepare-ssh)
   * [Base SSH Config](#base-ssh-config)
- [Jumpbox: Hostname Resolution](#jumpbox-hostname-resolution)
- [Jumpbox: SSH Key Generation](#jumpbox-ssh-key-generation)
- [Nodes: Authorize Jumpbox Access](#nodes-authorize-jumpbox-access)
- [Nodes: SSH Hardening](#nodes-ssh-hardening)
   * [SSH Hardening](#ssh-hardening)
   * [Restrict access](#restrict-access)
   * [Reload SSH](#reload-ssh)
- [Optional: Enable Passwordless Sudo](#optional-enable-passwordless-sudo)
- [Optional: Extra lockdown](#optional-extra-lockdown)
   * [Disable root password login](#disable-root-password-login)
   * [Prevent serial login](#prevent-serial-login)

## Goal
This phase will be split up in two parts:
- **Reachability**: establishes SSH
- **Hardening:** After SSH has been established, access will become more restrictive
## Access Model

### Topology
This phase will setup **two trust boundaries**:
1. **Host machine → Jumpbox** 
2. **Jumpbox → Nodes**

The topology will look like this:
```less
[ Host Machine ]
        |
        v
   SSH (key)
        |
   [ Jumpbox ]
        |
        v
   SSH (key)
        |
[ Control Plane / Workers ]
```

### Target Access Matrix

| Source         | Target        | Method | User   | Purpose                  |
| -------------- | ------------- | ------ | ------ | ------------------------ |
| Host machine   | Jumpbox       | SSH    | debian | Entry point into cluster |
| Jumpbox        | Control plane | SSH    | debian | Cluster administration   |
| Jumpbox        | Worker nodes  | SSH    | debian | Node administration      |
| Host machine   | Nodes         | ❌      | —      | Not allowed              |
| Serial console | Any node      | 🔒     | root   | Break-glass only         |
## Host --> Jumpbox

### Hostname resolution
Add this line to the `/etc/hosts` file:
```
10.20.0.5 jumpbox
```
### Access
Access the jumpbox from the host with:
```nginx
ssh debian@jumpbox
```
> For convenience sake, I will keep the Host --> Jumpbox boundary pretty simple. 

## Nodes: Privilege Escalation
> [!NOTE]
> **Access method:** Serial console (`virsh console`)
### Sudo
On each VM, install `sudo`
```
apt update
apt install -y sudo
```

### Add user to sudo group
Add the user `debian` to the sudo group
```
usermod -aG sudo debian
```

### Verify sudo
Logout, and log in with the debian user:
```
exit
```

Check if you can login:
```
sudo -i
```

## Nodes: Prepare SSH
> [!NOTE]
> **Access method:** Serial console (`virsh console`)

On all nodes, edit `/etc/ssh/sshd_config`
### Base SSH Config
```nginx
# Authentication
PermitRootLogin no
PasswordAuthentication yes    # TEMPORARY
PubkeyAuthentication yes
KbdInteractiveAuthentication no
UsePAM yes

# Reduce attack surface
X11Forwarding no
AllowTcpForwarding no
PermitTunnel no
PermitUserEnvironment no
```

Reload SSH
```
systemctl reload ssh
```

## Jumpbox: Hostname Resolution
> [!NOTE]
> **Access method:** SSH host to jumpbox


On the jumpbox, edit `/etc/hosts` add add these lines so it matches the VM hosts:
```
10.20.0.10 cp1
10.20.0.11 w1
10.20.0.12 w2
10.20.0.13 w3
```

## Jumpbox: SSH Key Generation
Generate a dedicated admin key on the jumpbox:
```
ssh-keygen -t ed25519 -C "k8s-admin@jumpbox"
```
> A passphrase is not necessary, but for good practice, it is recommended.

## Nodes: Authorize Jumpbox Access
From the jumpbox, copy the key to each node:
```bash
ssh-copy-id debian@cp1
ssh-copy-id debian@w1
ssh-copy-id debian@w2
ssh-copy-id debian@w3
```

Verify:
```
ssh debian@cp1
ssh debian@w1
ssh debian@w2
ssh debian@w3
```

## Nodes: SSH Hardening
> [!NOTE]
> **Access method:** SSH jumpbox to Nodes

Edit the `/etc/ssh/sshd_config` on **all nodes**.
### SSH Hardening
```
# Authentication
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
UsePAM yes

# Reduce attack surface
X11Forwarding no
AllowTcpForwarding no
PermitTunnel no
PermitUserEnvironment no

# Limit auth attempts
MaxAuthTries 3
LoginGraceTime 30
```

### Restrict access
Add this part too. This will restrict access to the jumpbox.
```
Match Address 10.20.0.5
    AllowUsers debian

Match all
    DenyUsers *
```

### Reload SSH
After the changes on the file, reload SSH
```
systemctl reload ssh
```

Check if you can SSH to all nodes from the jumpbox:
```
ssh debian@cp1
ssh debian@w1
ssh debian@w2
ssh debian@w3
```

## Optional: Enable Passwordless Sudo
On each node, run:
```
sudo visudo
```

Add the following line **below** the existing `%sudo` entry:
```
%sudo ALL=(ALL) NOPASSWD: ALL
```

> Passwordless sudo is enabled to reduce friction while working through the lab. 


## Optional: Extra lockdown
> [!NOTE]
> **Access method:** SSH jumpbox to Nodes

### Disable root password login
```
sudo passwd -l root
```

Root still remains accessible via `sudo`
### Prevent serial login
Edit `/etc/securetty`

Comment out this line:
```
# ttyS0
```

This prevents direct root login over serial

> [!IMPORTANT]
> **Host system boundary**
>
> From this point onward:
> - The **host system is no longer required** for installation
> - All remaining phases are executed via:
>   ```
>   Host → SSH → Jumpbox → SSH → Nodes
>   ```
> - The host is only used for:
>   - Power management (start/stop VMs)
>   - Emergency console access
>
> All Kubernetes installation steps assume SSH access via the jumpbox.
