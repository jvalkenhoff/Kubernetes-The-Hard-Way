# Infrastructure Planning
The first iteration of Kubernetes The Hard Way had some growing pains. But that is normal, especially when setting it up for the first time. Doing a bit of planning can speed up the process in the long run!

- [General Layout](#general-layout)
- [Naming](#naming)
- [Resource Distribution](#resource-distribution)
- [Networking](#networking)
  - [IP distribution](#ip-distribution)
  - [networkd / resolved](#networkd--resolved)
  - [nftables](#nftables)
    - [Control Plane (`cp1` )](#control-plane-cp1-)
    - [Workers (`w1`, `w2`, `w3`)](#workers-w1-w2-w3)
- [Cluster](#cluster)
  - [Components](#components)
  - [Networking](#networking)
  - [Static Pods](#static-pods)
- [Certificates & PKI Design](#certificates--pki-design)
- [Directory layout](#directory-layout)
  - [Control Plane (`cp1`)](#control-plane-cp1)
    - [Directories and permissions](#directories-and-permissions)
    - [PKI Files](#pki-files)
      - [Kubernetes](#kubernetes)
      - [etcd](#etcd)
    - [Static pod manifests](#static-pod-manifests)
    - [Binaries](#binaries)
  - [Worker Nodes (`w1`, `w2`, `w3`)](#worker-nodes-w1-w2-w3)
    - [Directories and permissions](#directories-and-permissions)
    - [Component owned files](#component-owned-files)
    - [Binaries](#binaries)


## General Layout
The topology remains pretty simple, to keep it manageable for now:
- 1 control plane node
- 3 worker nodes
- 1 jumpbox (for SSH access once everything is locked down)


## Naming
Sounds dull, but once you name the VM, there is no going back. I will keep it simple:
- **Control Plane:** `cp1`
- **Worker Nodes** `w1`, `w2`, `w3`
- **Jumpbox**: `jumpbox`


## Resource Distribution
Lab environments don’t need much, but even light workloads can add up quickly. Current setup keeps it low, while leaving some room for test Pods.

| Name      | vCPU | RAM | Storage |
| --------- | ---- | --- | ------- |
| `jumpbox` | 1    | 1GB | 15GB    |
| `cp1`     | 2    | 4GB | 25GB    |
| `w1`      | 2    | 4GB | 25GB    |
| `w2`      | 2    | 4GB | 25GB    |
| `w3`      | 2    | 4GB | 25GB    |


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

> Note: the “API endpoint” (`10.20.0.9`) is a stable name/IP to point kubeconfigs at (e.g. `api.k8s.local`). It represents the API as a _service endpoint_, not a VM.
### networkd / resolved
All nodes will switch from Debian’s default `ifupdown` to **systemd-networkd** and **systemd-resolved**. This setup is a bit more modern, and handles DNS much better. 

### nftables
I will drop ufw for **nftables**. Below are the inbound / outbound rules per node.
#### Control Plane (`cp1` )
**Inbound**
- 6443/tcp - Kubernetes API Server
- 2379-2380/tcp - etcd client and traffic
- 10250 - kubelet API
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
- 10250/tcp - Kubelet API
- 30000-32767/tcp - NodePort Services
- 22/tcp - SSH (from jumpbox only)

**Outbound**
- 6443/tcp - kube-apiserver
- 53/tcp, 53/udp - DNS
- 123/udp - NTP
- 443/tcp - HTTPS (for image pulls)


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
Unlike before, the control plane components will not be managed as **static Pods** instead of relying on **systemd units**. That means that the **kubelet and the container runtime** needs to be installed on the control plane.

**Why**
- It aligns with common Kubernetes control plane designs
- kubelet becomes the single supervisor for core components
- No reliance on multiple systemd units
- Makes component lifecycle and failures more visible through Kubernetes-native tooling (like kubectl)

Read more about architecture considerations [here](https://kubernetes.io/docs/concepts/architecture/#architecture-variations).


## Certificates & PKI Design
This iteration will have a layered PKI model by introducing intermediate certificates:
```swift
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


## Directory layout
This section predetermines where **binaries**, **configs**, **PKI material**, **static pod manifests**, and **runtime binaries** live.  
The goal is consistency, least privilege, and predictable ownership across nodes. Read more about it in the [Kubernetes Documentation](https://kubernetes.io/docs/setup/best-practices/certificates/). There is also a blog on [Medium](https://yuminlee2.medium.com/kubernetes-folder-structure-and-functionality-overview-5b4ec10c32bf) about the folder layout.

### Control Plane (`cp1`)
The control plane will have one central PKI store in `/etc/kubernetes/pki/`.
- apiserver needs serving cert + clients (etcd/kubelet) + CA bundles
- controller/scheduler need kubeconfigs, client certs and CA bundles
#### Directories and permissions
```swift
/etc/kubernetes/                 root:root 755
/etc/kubernetes/pki/             root:root 700
/etc/kubernetes/manifests/       root:root 700

/etc/etcd/                       root:root 755
/etc/etcd/pki/                   root:root 700
/var/lib/etcd/                   etcd:etcd 700

/opt/cni/bin/                    root:root 755
```
#### PKI Files
##### Kubernetes
```swift
/etc/kubernetes/pki/
├── ca.crt                                  (644)
├── kube-apiserver.crt                      (644)
├── kube-apiserver.key                      (600)
├── kube-apiserver-kubelet-client.crt       (644)
├── kube-apiserver-kubelet-client.key       (600)
├── kube-apiserver-etcd-client.crt          (644)
├── kube-apiserver-etcd-client.key          (600)
├── sa.pub                                  (644)
└── sa.key                                  (600)
```

##### etcd
```swift
/etc/etcd/pki/
├── ca.crt                  (644)
├── etcd-server.crt         (644)
├── etcd-server.key         (600)
├── etcd-peer.crt           (644)
└── etcd-peer.key           (600)
```

#### Static pod manifests
```swift
/etc/kubernetes/manifests/
├── etcd.yaml
├── kube-apiserver.yaml
├── kube-controller-manager.yaml
└── kube-scheduler.yaml
```

#### Binaries
```swift
/usr/local/bin/kubelet

/usr/local/bin/containerd
/usr/local/bin/containerd-shim-runc-v2
/usr/local/bin/ctr
/usr/local/sbin/runc

/usr/local/bin/etcd
/usr/local/bin/etcdctl

/opt/cni/bin/*
```

### Worker Nodes (`w1`, `w2`, `w3`)
Worker nodes uses component owned directory structure.  **Worker node components** like kubelet and kube-proxy have their runtime state is already under `/var/lib/...` . This keeps the separation clean.
#### Directories and permissions
```swift
/var/lib/kubelet/                root:root 700
/var/lib/kubelet/pki/            root:root 700

/var/lib/kube-proxy/             root:root 700
/var/lib/kube-proxy/pki/         root:root 700

/opt/cni/bin/                    root:root 755
```

#### Component owned files
```swift
/var/lib/kubelet/
├── kubeconfig                   (600)
├── config.yaml                  (600)
└── pki/
    ├── kubelet-client.crt       (644)
    ├── kubelet-client.key       (600)
    ├── kubelet-serving.crt      (644)
    └── kubelet-serving.key      (600)
```

```swift
/var/lib/kube-proxy/
├── kubeconfig                   (600)
├── config.yaml                  (600)
└── pki/
```

#### Binaries
```swift
/usr/local/bin/kube-proxy

/usr/local/bin/containerd
/usr/local/bin/containerd-shim-runc-v2
/usr/local/bin/ctr
/usr/local/sbin/runc

/opt/cni/bin/*
```
