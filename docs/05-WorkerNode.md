## Step 1. CNI

### Prepare folders
on the worker node, run this:
```
sudo mkdir -p /etc/cni/net.d/ /opt/cni/bin
```
### Install
from the jumpbox, scp to the worker node:
```
scp ~/downloads/cni-plugins/* debian@worker1:~/cni-plugins/
```

```
sudo install -m 0755 ./cni-plugins/* /opt/cni/bin/
```

### Bridge CNI
`/etc/cni/net.d/10-bridge.conflist`

```json
{
  "cniVersion": "1.1.0",
  "name": "bridge",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "cni0",
      "isGateway": true,
      "hairpinMode": true,
      "ipMasq": false,
      "ipam": {
        "type": "host-local",
        "ranges": [
          [
            { "subnet": "10.200.1.0/24" }
          ]
        ],
        "routes": [
          { "dst": "0.0.0.0/0" }
        ]
      }
    },
    {
      "type": "portmap",
      "capabilities": { "portMappings": true}
    }
  ]
}
```

### Loopback CNI
`/etc/cni/net.d/99-loopback.conf`

```json
{
  "cniVersion": "1.1.0",
  "name": "lo",
  "type": "loopback"
}
```

### Cross Pod CIDR Routing

on worker1:
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

## Step 2. containerd

### Prepare folders
on the worker node, run this:
```
sudo mkdir -p /etc/containerd/ /etc/cni/net.d/ /opt/cni/bin
```

### Install runtime
from the jumpbox, scp to the worker node:
```
scp ~/downloads/worker/containerd ~/downloads/worker/containerd-shim-runc-v2 ~/downloads/worker/ctr ~/downloads/worker/runc debian@worker1:~/
```

```
sudo install -m 0755 containerd containerd-shim-runc-v2 /bin/
sudo install -m 0755 runc /usr/local/bin/
```

### Config containerd
run:
```
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
```

This creates a containerd config file. open `/etc/containerd/config.toml`, and set:
```toml
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
SystemdCgroup = true
```

### Systemd
create `/etc/system/systemd/containerd.service`

```ini
[Unit]
Description=containerd
After=network-online.target
Wants=network-online.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOPROFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
```

### Start
```
sudo systemctl daemon-reload
sudo systemctl enable --now containerd
```

## Step 3. Kubelet

### Prepare folders
run:
```
sudo mkdir -p /var/lib/kubelet
```

### Install
from the jumpbox:
```
scp ~/downloads/workers/kubelet debian@worker1:~/
```

```
sudo install -m 0755 kubelet /usr/local/bin/
```

### Config
`/var/lib/kubelet/kubelet-config.yaml`

```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
address: "0.0.0.0"
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
authorization:
  mode: Webhook
containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
runtimeRequestTimeout: 15m
cgroupDriver: systemd
rotateCertificates: false
enableServer: true
failSwapOn: false
maxPods: 16
memorySwap:
  swapBehavior: NoSwap
port: 10250
resolvConf: "/etc/resolv.conf"
registerNode: true
tlsCertFile: "/var/lib/kubelet/pki/kubelet.crt"
tlsPrivateKeyFile: "/var/lib/kubelet/pki/kubelet.key"
```

### Systemd
Create `/etc/systemd/system/kubelet.service`

```ini
[Unit]
Description=Kubernetes Kubelet
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \
  --config=/var/lib/kubelet/kubelet-config.yaml \
  --kubeconfig=/var/lib/kubelet/kubeconfig \
  --node-ip=10.20.0.11 \
  --v=2
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Start
```
sudo systemctl daemon-reload
sudo systemctl enable --now kubelet
```

## Step 4. Kube-proxy
### Prepare folders
run:
```
sudo mkdir -p /var/lib/kube-proxy
```

### Install
from the jumpbox:
```
scp ~/downloads/workers/kube-proxy debian@worker1:~/
```

```
sudo install -m 0755 kube-proxy /usr/local/bin/
```

### Config
`/var/lib/kube-proxy/kube-proxy-config.yaml`

Same CIDR as defined in the Controller manager
```yaml
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
clientConnection:
  clientConnection: /var/lib/kube-proxy/kubeconfig
mode: iptables
clusterCIDR: 10.200.0.0/16
```

### Systemd
`/etc/systemd/system/kube-proxy.service`

```ini
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-proxy \
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml \
  --v=2
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Start
```
sudo systemctl daemon-reload
sudo systemctl enable --now kube-proxy
```

