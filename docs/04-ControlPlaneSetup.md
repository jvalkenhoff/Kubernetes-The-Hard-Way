# Phase 4: Control Plane setup

## Step 1. Encryption at rest
Is possible without, but secrets will be stored in plain text in etcd.

### Config
Create the config file. I advise to do this directly on the control plane:
```bash
sudo tee /var/lib/kubernetes/encryption-config.yaml >/dev/null <<'EOF'
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
```

### Add key
Run to create the key:
```bash
export ENCRYPTION_KEY="$(head -c 32 /dev/urandom | base64 -w 0)"
```

insert the key in the config:
```bash
envsubst < encryption-config.yaml > /var/lib/kubernetes/encryption-config.yaml
```

Set permissions:
```bash
sudo chmod 600 /var/lib/kubernetes/encryption-config.yaml
```

---
## Step 2. Audit log path
The kube-apiserver with write to the audit log path:
```bash
sudo touch /var/log/audit.log
sudo chmod 600 /var/log/audit.log
```

---
## Step 3. etcd

### Install
scp etcd and etcdctl from the jumpbox:
```bash
scp ~/downloads/controller/etcd /home/debian/downloads/client/etcdctl debian@control-plane:~/
```

binaries should already be executables, but this command moves and sets correct permissions
```bash
sudo install -m 0755 etcd etcdctl /usr/local/bin/
```

verify:
```
etcd --version
etcdctl version
```

### Create user
make a user for etcd:
```bash
sudo useradd -r -s /usr/sbin/nologin -M etcd || true
```

prepare directories for the user:
```
sudo mkdir -p /etc/etcd /var/lib/etcd
sudo chown etcd:etcd /var/lib/etcd
sudo chmod 700 /var/lib/etcd
```

### Certs
Distribute the certs from earlier steps 
```bash
sudo cp /etc/kubernetes/pki/ca.crt /etc/etcd/ca.crt
sudo cp /etc/kubernetes/pki/etcd.crt /etc/etcd/etcd.crt
sudo cp /etc/kubernetes/pki/etcd.key /etc/etcd/etcd.key
```

adjust appropriate permissions:
```
sudo chown -R etcd:etcd /etc/etcd
sudo chmod 600 /etc/etcd/etcd.key
```

### Systemd
create the systemd unit file `/etc/systemd/system/etcd.service`
```ini
[Unit]
Description=etcd
Documentation=https://etcd.io/docs/
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=etcd
ExecStart=/usr/local/bin/etcd \
  --name control-plane \
  --data-dir /var/lib/etcd \
  --listen-client-urls https://127.0.0.1:2379,https://10.20.0.10:2379 \
  --advertise-client-urls https://10.20.0.10:2379 \
  --listen-peer-urls https://10.20.0.10:2380 \
  --initial-advertise-peer-urls https://10.20.0.10:2380 \
  --initial-cluster control-plane=https://10.20.0.10:2380 \
  --initial-cluster-token k8s-etcd-cluster \
  --initial-cluster-state new \
  --client-cert-auth=true \
  --trusted-ca-file=/etc/etcd/ca.crt \
  --cert-file=/etc/etcd/etcd.crt \
  --key-file=/etc/etcd/etcd.key \
  --peer-client-cert-auth=true \
  --peer-trusted-ca-file=/etc/etcd/ca.crt \
  --peer-cert-file=/etc/etcd/etcd.crt \
  --peer-key-file=/etc/etcd/etcd.key
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Start etcd
run:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now etcd
```

### Verify
check if this returns `healthy`.
```bash
etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/etcd.crt \
  --key=/etc/etcd/etcd.key \
  endpoint health
```

should return:
```
https://127.0.0.1:2379 is healthy: successfully committed proposal: took = 41.921668ms
```

also check:
```
etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/etcd.crt \
  --key=/etc/etcd/etcd.key \
  member list
```

should return:
```
794d7fe90de59918, started, control-plane, https://10.20.0.10:2380, https://10.20.0.10:2379, false
```

> Earlier versions require to run with `export ETCDCTL_API=3`. In newer versions of etcd, this setting is redundant and deprecated.

---
## Step 4. kube-apiserver

### Install
scp kube-apiserver from the jumpbox:
```bash
scp ~/downloads/controller/kube-apiserver debian@control-plane:~/
```

binaries should already be executables, but this command moves and sets correct permissions
```bash
sudo install -m 0755 kube-apiserver /usr/local/bin/
```

verify:
```
kube-apiserver --version
```

### Prepare directories
```
sudo mkdir -p /etc/kubernetes/manifests /var/lib/kubernetes
```

### Certs
Copy ca and apiserver certs:
```
sudo cp /etc/kubernetes/pki/ca.crt /var/lib/kubernetes/ca.crt
sudo cp /etc/kubernetes/pki/kube-apiserver.crt /var/lib/kubernetes/kube-apiserver.crt
sudo cp /etc/kubernetes/pki/kube-apiserver.key /var/lib/kubernetes/kube-apiserver.key
```

etcd certs too:
``` 
sudo cp /etc/kubernetes/pki/etcd.crt /var/lib/kubernetes/etcd.crt
sudo cp /etc/kubernetes/pki/etcd.key /var/lib/kubernetes/etcd.key
sudo cp /etc/kubernetes/pki/ca.crt /var/lib/kubernetes/etcd-ca.crt
```

service account keys:
```
sudo cp /etc/kubernetes/pki/sa.key /var/lib/kubernetes/service-account.key
sudo cp /etc/kubernetes/pki/sa.pub /var/lib/kubernetes/service-account.pub
```

set correct permissions on the keys:
```
sudo chmod 600 /var/lib/kubernetes/*.key
```

> This copies the ca cert twice; normally etcd has its own dedicated ca, which i will setup later

### Systemd
create the systemd unit file `/etc/systemd/system/kube-apiserver.service`
```ini
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=network-online.target etcd.service
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/kube-apiserver \
  --advertise-address=10.20.0.10 \
  --bind-address=0.0.0.0 \
  --secure-port=6443 \
  --allow-privileged=true \
  --apiserver-count=1 \
  --authorization-mode=Node,RBAC \
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,ResourceQuota \
  --client-ca-file=/var/lib/kubernetes/ca.crt \
  --tls-cert-file=/var/lib/kubernetes/kube-apiserver.crt \
  --tls-private-key-file=/var/lib/kubernetes/kube-apiserver.key \
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.crt \
  --kubelet-client-certificate=/var/lib/kubernetes/kube-apiserver.crt \
  --kubelet-client-key=/var/lib/kubernetes/kube-apiserver.key \
  --etcd-servers=https://127.0.0.1:2379 \
  --etcd-cafile=/var/lib/kubernetes/etcd-ca.crt \
  --etcd-certfile=/var/lib/kubernetes/etcd.crt \
  --etcd-keyfile=/var/lib/kubernetes/etcd.key \
  --service-cluster-ip-range=10.32.0.0/24 \
  --service-node-port-range=30000-32767 \
  --service-account-issuer=https://kubernetes.default.svc.cluster.local \
  --service-account-signing-key-file=/var/lib/kubernetes/service-account.key \
  --service-account-key-file=/var/lib/kubernetes/service-account.pub \
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \
  --audit-log-path=/var/log/audit.log \
  --audit-log-maxage=30 \
  --audit-log-maxbackup=3 \
  --audit-log-maxsize=100 \
  --event-ttl=1h \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Start kube-apiserver
```bash
sudo systemctl daemon-reload
sudo systemctl restart kube-apiserver
```

### Verify
run:
```
curl -k https://127.0.0.1:6443/readyz?verbose
```

Should return a bunch of checks:
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

---
## Step 5. kube-controller-manager
### Install
scp kube-controller-manager from the jumpbox:
```bash
scp ~/downloads/controller/kube-controller-manager debian@control-plane:~/
```

binaries should already be executables, but this command moves and sets correct permissions
```bash
sudo install -m 0755 kube-controller-manager /usr/local/bin/
```

verify:
```
kube-controller-manager --version
```

---
## Step 6. kube-scheduler

### Install
scp kube-apiserver from the jumpbox:
```bash
scp ~/downloads/controller/kube-scheduler debian@control-plane:~/
```

binaries should already be executables, but this command moves and sets correct permissions
```bash
sudo install -m 0755 kube-scheduler /usr/local/bin/
```

verify:
```
kube-scheduler --version
```

---
## Step 7. Checklist

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

