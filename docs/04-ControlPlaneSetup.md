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
install -m 0755 etcd etcdctl /usr/local/bin/etcd
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

### Systemd Unit
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
sudo systemctl status etcd --no-pager
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


> [!info] about ETCDCTL_API=3
> Earlier versions require to run with `export ETCDCTL_API=3`. In newer versions of etcd, this setting is redundant and deprecated.

