# Phase 6: Node Preparation
- [Base Packages](#base-packages)
- [Time Synchronization](#time-synchronization)
- [Disable Swap](#disable-swap)
- [Kernel modules](#kernel-modules)
- [Sysctl Tuning](#sysctl-tuning)

## Goal
This phase sets up the nodes with correct packages.
## Base Packages
Install:
```bash
apt install -y chrony curl ca-certificates gnupg lsb-release socat conntrack ipset kmod
```

## Time synchronization
This is the exact same step as in Phase 05.
TLS **will break** if time is out of sync.

Check the timezone:
```bash
timedatectl status
```

If time is out of sync, set the timezone according to your local area:
```
timedatectl set-timezone <area>/<location>

# example
timedatectl set-timezone Europe/Amsterdam
```

Synchronize the hardware clock:
```
systemctl enable --now chrony
```

Verify with:
```
chronyc tracking
```

- `Leap status : Normal`
- `System Time` should be < 0.1 seconds

## Disable Swap
Kubernetes will not run with swap on:
```bash
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab
```

check if swap is turned off (should show no output):
```bash
swapon --show
```

## Kernel modules
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

## Sysctl Tuning
Create file `/etc/sysctl.d/k8s.conf`
```
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
```

Run `sysctl --system`
