# Phase 7: Server Checks
## Step 1. Checklist

### kubectl
you can already perform checks with kubectl on the jumpbox. Go to `~/k8s-certs/kubeconfigs`

#### Cluster info
```
KUBECONFIG=admin.kubeconfig kubectl cluster-info
```

should show:
```
Kubernetes control plane is running at https://10.20.0.10:6443

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

#### API Health
```
KUBECONFIG=admin.kubeconfig kubectl get --raw='/readyz?verbose' | tail -n 5
```

should show:
```
[+]autoregister-completion ok
[+]poststarthook/apiservice-openapi-controller ok
[+]poststarthook/apiservice-openapiv3-controller ok
[+]shutdown ok
readyz check passed
```

#### Namespaces
```
KUBECONFIG=admin.kubeconfig kubectl get namespaces
```

should show:
```
NAME              STATUS   AGE
default           Active   16h
kube-node-lease   Active   16h
kube-public       Active   16h
kube-system       Active   16h
```

#### Controller manager and scheduler
```
KUBECONFIG=admin.kubeconfig kubectl get --raw='/livez?verbose' | tail -n 20
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

or at leat etcd on 2379 and 2380, the apiserver on 6443

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



