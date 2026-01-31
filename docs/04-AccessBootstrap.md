# Phase 4: Access Boostrap
This phase establishes **SSH access** to all nodes via a jumpbox and **removes reliance on serial console access**. **This will be the last and only phase where commands will be executed as `root` user**. In subsequent phases, root access will _only_ be possible via `sudo`.

- [Goal](#goal)
- [Access Model](#access-model)
  - [Topology](#topology)
  - [Target Access Matrix](#target-access-matrix)
- [Part 1: Reachability](#part-1-reachability)
  - [All VMs: sudo install](#all-vms-sudo-install)
  - [Nodes: Prepare SSH](#nodes-prepare-ssh)
  - [Jumpbox --> Nodes](#jumpbox----nodes)
- [Part 2: Hardening](#part-2-hardening)
  - [Nodes: SSH Hardening](#nodes-ssh-hardening)
- [Host --> Jumpbox](#host----jumpbox)

## Goal
This phase will be split up in two parts:
- **Reachability**: establishes SSH
- **Hardening:** After SSH has been established, access will become more restrictive

In both parts, use `virsh console <vm-name>` to access the VMs.
## Access Model

### Topology
This phase will set up **two trust boundaries**:
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
## Part 1: Reachability

### All VMs: sudo install
On each VM, install `sudo`
```
apt update && apt install -y sudo
```

Add the user `debian` to the sudo group
```
usermod -aG sudo debian
```

Enable passwordless `sudo`. 
On each node, run:
```
sudo visudo
```

Add the following line **below** the existing `%sudo` entry:
```
%sudo ALL=(ALL) NOPASSWD: ALL
```

> [!NOTE]
> Passwordless sudo is enabled to reduce friction while working through the lab. 


Logout, and log in with the debian user:
```
exit
```

Check if you can login:
```
sudo -i
```

### Nodes: Prepare SSH
On all nodes, edit `/etc/ssh/sshd_config`. Clear the file contents, and add this:
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

### Jumpbox --> Nodes
On the jumpbox, edit `/etc/hosts` add add these lines so it matches the VM hosts:
```
10.20.0.10 cp1
10.20.0.11 w1
10.20.0.12 w2
10.20.0.13 w3
```

Generate a dedicated admin key on the jumpbox:
```
ssh-keygen -t ed25519 -C "k8s-admin@jumpbox"
```

> [!NOTE]
> A passphrase is not necessary, but for good practice, it is recommended.


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

## Part 2: Hardening

> [!warning]
> Apply SSH restrictions only after verifying key-based SSH access
> from the jumpbox.

### Nodes: SSH Hardening
Edit the `/etc/ssh/sshd_config` on **all nodes**.
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


Add this part too. This will restrict access to the jumpbox.
```
Match Address 10.20.0.5
    AllowUsers debian

Match all
    DenyUsers *
```

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

## Host --> Jumpbox
Lastly, access the Jumpbox from the host. For convenience sake, I will keep the Host --> Jumpbox boundary pretty simple.  

Add this line to the `/etc/hosts` file:
```
10.20.0.5 jumpbox
```

Access the jumpbox from the host with:
```nginx
ssh debian@jumpbox
```


> [!IMPORTANT]
> **Host system boundary**
> From this point onward:
> - The **host system is no longer required** for installation
> - All remaining phases are executed via:
>   ```
>   Host → SSH → Jumpbox → SSH → Nodes
>   ```
