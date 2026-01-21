# Kubernetes The Hard Way
This repository is heavily influenced on the original Kubernetes The Hard Way repository by Kelsey Hightower. Be sure to check out the original work [here](https://github.com/kelseyhightower/kubernetes-the-hard-way). I have also consulted https://github.com/ghik/kubernetes-the-harder-way , which has a more verbose take on the original repository.
## Cluster Details
- Kubernetes v1.34.x
- containerd v2.2.x
- CNI v1.9.x
- etcd v3.6.x
- runc v1.4.x

All VMs are built with Debian 12.12.x . It is available in the [Debian Archive](https://cdimage.debian.org/cdimage/archive/12.12.0/amd64/iso-cd/).

## Future Plans
This setup is far from finished:
- Iteration 0: Raw setup, minimal scripts
- Iteration 1: Stabilized setup, introducing more scripts
	- networkd
	- Intermediate CA
	- Replace ufw with iptables
- Iteration 2: Introducing HA
	- HA Control Plane
	- Static Pods
	- Introducing MetalLB and coreDNS
- Iteration 3: Further Enhancements
	- Swap runc with crun
	- Swap containerd with CRI-O
	- Introduce Cilium
