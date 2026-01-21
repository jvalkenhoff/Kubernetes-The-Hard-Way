# Phase 7: Checklist
## Step 1. Control Plane

### Systemd services
```
sudo systemctl is-active etcd kube-apiserver kube-controller-manager kube-scheduler
```

should show:
```
active
active
active
active
```

### Port listening
```
sudo ss -lntp | egrep ':(2379|2380|6443)\b'
```

Should show:
```
LISTEN 0      4096       127.0.0.1:2379       0.0.0.0:*    users:(("etcd",pid=2468,fd=7))
LISTEN 0      4096      10.20.0.10:2380       0.0.0.0:*    users:(("etcd",pid=2468,fd=3))
LISTEN 0      4096      10.20.0.10:2379       0.0.0.0:*    users:(("etcd",pid=2468,fd=6))
LISTEN 0      4096               *:6443             *:*    users:(("kube-apiserver",pid=3500,fd=3))
```

or at least etcd on 2379 and 2380, the apiserver on 6443

### etcd health
```
etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/etcd.crt \
  --key=/etc/etcd/etcd.key \
  endpoint health
```

should show:
```
https://127.0.0.1:2379 is healthy: successfully committed proposal: took = 41.921668ms
```

### API Server health
```
curl -k https://127.0.0.1:6443/readyz?verbose
curl -k https://127.0.0.1:6443/healthz?verbose
```

should show:
```
[+]ping ok
[+]log ok
[+]etcd ok
[+]etcd-readiness ok
[+]informer-sync ok
[+]poststarthook/start-apiserver-admission-initializer ok
[+]poststarthook/generic-apiserver-start-informers ok
[+]poststarthook/priority-and-fairness-config-consumer ok
[+]poststarthook/priority-and-fairness-filter ok
[+]poststarthook/storage-object-count-tracker-hook ok
[+]poststarthook/start-apiextensions-informers ok
[+]poststarthook/start-apiextensions-controllers ok
[+]poststarthook/crd-informer-synced ok
[+]poststarthook/start-system-namespaces-controller ok
[+]poststarthook/start-cluster-authentication-info-controller ok
[+]poststarthook/start-kube-apiserver-identity-lease-controller ok
[+]poststarthook/start-kube-apiserver-identity-lease-garbage-collector ok
[+]poststarthook/start-legacy-token-tracking-controller ok
[+]poststarthook/start-service-ip-repair-controllers ok
[+]poststarthook/rbac/bootstrap-roles ok
[+]poststarthook/scheduling/bootstrap-system-priority-classes ok
[+]poststarthook/priority-and-fairness-config-producer ok
[+]poststarthook/bootstrap-controller ok
[+]poststarthook/start-kubernetes-service-cidr-controller ok
[+]poststarthook/start-kube-aggregator-informers ok
[+]poststarthook/apiservice-status-local-available-controller ok
[+]poststarthook/apiservice-status-remote-available-controller ok
[+]poststarthook/apiservice-registration-controller ok
[+]poststarthook/apiservice-discovery-controller ok
[+]poststarthook/kube-apiserver-autoregistration ok
[+]autoregister-completion ok
[+]poststarthook/apiservice-openapi-controller ok
[+]poststarthook/apiservice-openapiv3-controller ok
[+]shutdown ok
readyz check passed
```

## Step 2. Worker Nodes

### Swap disabled
```
swapon --show
```

must show no output

### Kernel module
```
lsmod | grep br_netfilter
```

should show:
```
br_netfilter           36864  0
bridge                319488  1 br_netfilter
```

### Sysctl
```
sysctl net.ipv4.ip_forward
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.bridge.bridge-nf-call-ip6tables
```

should all show `= 1`

### Systemd services
```
sudo systemctl is-active containerd kubelet kube-proxy
```

should show:
```
active
active
active
```

### Routing table
```
ip route | grep 10.200
```

should show:
```
10.200.2.0/24 via 10.20.0.12 dev enp1s0
10.200.3.0/24 via 10.20.0.13 dev enp1s0
```

or similar for the other nodes

## Step 3. Cluster / kubectl

### kubeconfig
```
kubectl config view --minify
```

should show:
```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: DATA+OMITTED
    server: https://10.20.0.10:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: admin
  name: default
current-context: default
kind: Config
users:
- name: admin
  user:
    client-certificate-data: DATA+OMITTED
    client-key-data: DATA+OMITTED
```

`server` must be the IP of the control plane node
### Cluster info
```
kubectl cluster-info
```

should show:
```
Kubernetes control plane is running at https://10.20.0.10:6443

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

### API Health
```
kubectl get --raw='/readyz?verbose' | tail -n 5
```

should show:
```
[+]autoregister-completion ok
[+]poststarthook/apiservice-openapi-controller ok
[+]poststarthook/apiservice-openapiv3-controller ok
[+]shutdown ok
readyz check passed
```

### Namespaces
```
kubectl get namespaces
```

should show:
```
NAME              STATUS   AGE
default           Active   16h
kube-node-lease   Active   16h
kube-public       Active   16h
kube-system       Active   16h
```

### Controller manager and scheduler
```
kubectl get --raw='/livez?verbose' | tail -n 20
```

should show:
```
[+]poststarthook/start-cluster-authentication-info-controller ok
[+]poststarthook/start-kube-apiserver-identity-lease-controller ok
[+]poststarthook/start-kube-apiserver-identity-lease-garbage-collector ok
[+]poststarthook/start-legacy-token-tracking-controller ok
[+]poststarthook/start-service-ip-repair-controllers ok
[+]poststarthook/rbac/bootstrap-roles ok
[+]poststarthook/scheduling/bootstrap-system-priority-classes ok
[+]poststarthook/priority-and-fairness-config-producer ok
[+]poststarthook/bootstrap-controller ok
[+]poststarthook/start-kubernetes-service-cidr-controller ok
[+]poststarthook/start-kube-aggregator-informers ok
[+]poststarthook/apiservice-status-local-available-controller ok
[+]poststarthook/apiservice-status-remote-available-controller ok
[+]poststarthook/apiservice-registration-controller ok
[+]poststarthook/apiservice-discovery-controller ok
[+]poststarthook/kube-apiserver-autoregistration ok
[+]autoregister-completion ok
[+]poststarthook/apiservice-openapi-controller ok
[+]poststarthook/apiservice-openapiv3-controller ok
livez check passed
```

### Authorization
```
kubectl auth can-i --as=kube-apiserver-kubelet-client create pods/exec
```

should say `no`

```
kubectl auth can-i --as=kube-apiserver-kubelet-client get nodes/proxy
kubectl auth can-i --as=kube-apiserver-kubelet-client get nodes/stats
kubectl auth can-i --as=kube-apiserver-kubelet-client get nodes/log
```

should all return `yes`


