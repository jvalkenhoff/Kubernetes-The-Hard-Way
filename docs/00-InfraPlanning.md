The first iteration of Kubernetes The Hard Way had some growing pains. But that is normal, especially when setting it up for the first time. Doing a bit of planning can speed up the process in the long run!

---
## General Layout
The topology remains pretty simple, to keep it manageable for now:
- 1 control plane node
- 3 worker nodes
- 1 jumpbox (for SSH access once everything is locked down)

---
## Naming
Sounds dull, but once you name the VM, there is no going back. I will keep it simple:
- **Control Plane:** `cp1`
- **Worker Nodes** `w1`, `w2`, `w3`
- **Jumpbox**: `jumpbox`

---
## Resource Distribution
Lab environments don’t need much, but even light workloads can add up quickly. Current setup keeps it low, while leaving some room for test Pods.

| Name      | vCPU | RAM | Storage |
| --------- | ---- | --- | ------- |
| `jumpbox` | 1    | 1GB | 15GB    |
| `cp1`     | 2    | 4GB | 25GB    |
| `w1`      | 2    | 4GB | 25GB    |
| `w2`      | 2    | 4GB | 25GB    |
| `w3`      | 2    | 4GB | 25GB    |

---
## Networking

### IP distribution
Pre-planning the network avoids problems later. Even in a lab, treating IPs as fixed infrastructure pays off.

**Network**
- **Subnet**: `10.20.0.0/24`
- **Gateway (libvirt)**: `10.20.0.1` 

**VMs**
- **Jumpbox**: `10.20.0.5`
- **cp1**: `10.20.0.10`
- **API (virtual host):** `10.20.0.9`
- **w1**: `10.20.0.11`
- **w2:** `10.20.0.12`
- **w3:** `10.20.0.13`

**Domain name:** `k8s.local`

### networkd / resolved
All nodes will switch from Debian’s default `ifupdown` to **systemd-networkd** and **systemd-resolved**. This setup is a bit more modern, and handles DNS much better. 

### nftables
I will drop ufw for **nftables**. Below are the inbound / outbound rules per node.
#### Control Plane (`cp1` )
**Inbound**
- 6443/tcp - Kubernetes API Server
- 2379-2380/tcp - etcd client and traffic
- 10257/tcp - controller-manager (localhost)
- 10259/tcp - scheduler (localhost)
- 22/tcp - SSH (from jumpbox only)

**Outbound**
- 10250/tcp - to Kubelets
- 2379-2380/tcp - etcd peers
- 53/tcp, 53/udp - DNS
- 123/udp - NTP

#### Workers (`w1`, `w2`, `w3`)
**Inbound**
- 10250 - Kubelet API
- 30000-32767 - NodePort Services
- 22 - SSH (from jumpbox only)

**Outbound**
- 6443 - kube-apiserver
- DNS / NTP
- Container image registries

---
## Cluster

### Components
- **Kubernetes**: v1.34.x
- **containerd**: v2.2.x
- **CNI**: v1.9.x
- **etcd:** v3.6.x
- **runc:** v1.4.x

### Networking
- **Cluster CIDR:** `10.200.0.0/16`
- **Service Cluster IP Range:** `10.32.0.0/24`
- **Service Node Port Range:** `30000-32767`


All VMs are built with **Debian 12.12.x**. It is available in the [Debian Archive](https://cdimage.debian.org/cdimage/archive/12.12.0/amd64/iso-cd/).

### Static Pods

---
## Certificates & PKI Design
This iteration will have a layered PKI model by introducing intermediate certificates:
```
Offline Root CA
 ├─ Kubernetes Intermediate CA
 │   ├─ kube-apiserver serving certs
 │   ├─ kube-apiserver client cert (→ kubelet)
 │   ├─ kubelet serving certs
 │   ├─ kubelet client certs (→ apiserver)
 │   ├─ controller-manager client cert
 │   ├─ scheduler client cert
 │   └─ admin (kubectl) client cert
 │
 └─ etcd Intermediate CA
     ├─ etcd server certs
     ├─ etcd peer certs
     └─ etcd client certs (apiserver → etcd)
```

**Reasons**
- The Offline root CA will **never be present** on cluster nodes
- Separate intermediates isolate Kubernetes and etcd trust domains
- kube-apiserver uses a dedicated client certificate when authenticating to:
    - kubelets
    - etcd

---
## Directory layout
Tightening the directories:
#### Control plane
```
/etc/kubernetes/pki        root:root 700
/etc/kubernetes            root:root 755
```

#### Workers
```
/var/lib/kubelet            root:root 700
/var/lib/kubelet/pki        root:root 700
/var/lib/kube-proxy         root:root 700
```

Component-owned directories keep credentials isolated and permissions tight:
```
/var/lib/kubelet/
├── kubeconfig
└── pki/

/var/lib/kube-proxy/
├── kubeconfig
└── pki/
```
