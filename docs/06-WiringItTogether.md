# Phase 6: Wiring it together
## Step 1. Cross Pod CIDR Routing

### Worker 1
```
sudo ip route add 10.200.2.0/24 via 10.20.0.12
sudo ip route add 10.200.3.0/24 via 10.20.0.13
```

persist with systemd file `/etc/systemd/system/pod-cidr-routes.service`

```ini
[Unit]
Description=Kubernetes Pod CIDR Routes
After=network-online.service
Wants=network-online.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/ip route add 10.200.2.0/24 via 10.20.0.12
ExecStart=/usr/sbin/ip route add 10.200.3.0/24 via 10.20.0.13

[Install]
WantedBy=multi-user.target
```

Enable and start:
```
sudo systemctl daemon-reload
sudo systemctl enable --now pod-cidr-routes
```

### Worker 2
```
sudo ip route add 10.200.1.0/24 via 10.20.0.11
sudo ip route add 10.200.3.0/24 via 10.20.0.13
```

persist with systemd file `/etc/systemd/system/pod-cidr-routes.service`

```ini
[Unit]
Description=Kubernetes Pod CIDR Routes
After=network-online.service
Wants=network-online.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/ip route add 10.200.1.0/24 via 10.20.0.11
ExecStart=/usr/sbin/ip route add 10.200.3.0/24 via 10.20.0.13

[Install]
WantedBy=multi-user.target
```

Enable and start:
```
sudo systemctl daemon-reload
sudo systemctl enable --now pod-cidr-routes
```

### Worker 3
```
sudo ip route add 10.200.1.0/24 via 10.20.0.11
sudo ip route add 10.200.2.0/24 via 10.20.0.12
```

persist with systemd file `/etc/systemd/system/pod-cidr-routes.service`

```ini
[Unit]
Description=Kubernetes Pod CIDR Routes
After=network-online.service
Wants=network-online.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/ip route add 10.200.1.0/24 via 10.20.0.11
ExecStart=/usr/sbin/ip route add 10.200.2.0/24 via 10.20.0.12

[Install]
WantedBy=multi-user.target
```

Enable and start:
```
sudo systemctl daemon-reload
sudo systemctl enable --now pod-cidr-routes
```

> This is not necessary when setting up Cilium


## Step 2. kubectl
Make sure you can run kubectl without specifying the kubeconfig in the command:
```
cd ~/k8s-ca/kubeconfigs/
install -m 0600 admin.kubeconfig ~/.kube/config
```

check with `kubectl version`:
```
Client Version: v1.34.2
Kustomize Version: v5.7.1
Server Version: v1.34.2
```

## Step 3. RBAC Authorization
I actually decided to create a separate cert for api-server --> kubelet authorization; also because i completely missed this step.

### Cert
on the jumpbox, go to `~/k8s-ca`
create `configs/kube-apiserver-kubelet-client.cnf`
```ini
[ req ]
default_bits        = 2048
prompt              = no
default_md          = sha256
distinguished_name  = dn

[ dn ]
CN = kube-apiserver-kubelet-client
O  = system:kube-apiserver
```

Generate private key:
```
openssl genrsa -out private/kube-apiserver-kubelet-client.key 4096
```

Create certificate request file:
```
openssl req -new -key private/kube-apiserver-kubelet-client.key -out csr/kube-apiserver-kubelet-client.csr -config config/kube-apiserver-kubelet-client.cnf
```

sign it, with `client_cert` (because the apiserver acts as a client for this usecase):
```
openssl ca -config config/root-ca.cnf -extensions client_cert -in csr/kube-apiserver-kubelet-client.csr -out certs/kube-apiserver-kubelet-client.crt
```

Move it to the control-plane:
```
scp private/kube-apiserver-kubelet-client.key certs/kube-apiserver-kubelet-client.crt debian@control-plane:~/
```

### Edit apiserver service
install the keys:
```
sudo install -m 0644 -o root -g root kube-apiserver-kubelet-client.crt /etc/kubernetes/pki/
sudo install -m 0600 -o root -g root kube-apiserver-kubelet-client.key /etc/kubernetes/pki/

sudo cp /etc/kubernetes/pki/kube-apiserver-kubelet-client.crt /var/lib/kubernetes/kube-apiserver-kubelet-client.crt
sudo cp /etc/kubernetes/pki/kube-apiserver-kubelet-client.key /var/lib/kubernetes/kube-apiserver-kubelet-client.key
```

edit these lines in `/etc/systemd/system/kube-apiserver.service` to:
```
  --kubelet-client-certificate=/var/lib/kubernetes/kube-apiserver-kubelet-client.crt \
  --kubelet-client-key=/var/lib/kubernetes/kube-apiserver-kubelet-client.key
```

Restart and check:
```
sudo systemctl daemon-reload
sudo systemctl restart kube-apiserver
sudo systemctl status kube-apiserver --no-pager
```

### ClusterRoleBinding
create the ClusterRoleBinding object. I use one of the existing component roles specified [here](https://kubernetes.io/docs/reference/access-authn-authz/rbac/).
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: apiserver-kubelet-api-admin
subjects:
  - kind: User
    name: kube-apiserver-kubelet-client
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: system:kubelet-api-admin
  apiGroup: rbac.authorization.k8s.io
```

apply it:
```
kubectl apply -f apiserver-kubelet-api-admin.yaml
```
