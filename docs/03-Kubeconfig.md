# Phase 3: Kubeconfig

```bash
API_SERVER="https://10.20.0.10:6443"
CLUSTER_NAME="kubernetes"
```

## Step 1. Admin

```bash
kubectl config set-cluster ${CLUSTER_NAME} \
  --certificate-authority=certs/ca.crt \
  --embed-certs=true \
  --server=${API_SERVER} \
  --kubeconfig=admin.kubeconfig
```

```bash
kubectl config set-credentials admin \
  --client-certificate=certs/admin.crt \
  --client-key=private/admin.key \
  --embed-certs=true \
  --kubeconfig=admin.kubeconfig
```

```bash
kubectl config set-context default \
  --cluster=${CLUSTER_NAME} \
  --user=admin \
  --kubeconfig=admin.kubeconfig
```

```bash
kubectl config use-context default --kubeconfig=admin.kubeconfig
```

---
## Step 2. Kubelets
```bash
kubectl config set-cluster ${CLUSTER_NAME} \
  --certificate-authority=certs/ca.crt \
  --embed-certs=true \
  --server=${API_SERVER} \
  --kubeconfig=kubelet-worker1.kubeconfig
```

```bash
kubectl config set-credentials system:node:worker1 \
  --client-certificate=certs/kubelet-worker1.crt \
  --client-key=private/kubelet-worker1.key \
  --embed-certs=true \
  --kubeconfig=kubelet-worker1.kubeconfig
```

```bash
kubectl config set-context default \
  --cluster=${CLUSTER_NAME} \
  --user=system:node:worker1 \
  --kubeconfig=kubelet-worker1.kubeconfig
```

```bash
kubectl config use-context default --kubeconfig=kubelet-worker1.kubeconfig
```

repeat for worker2 and worker3

---
## Step 3. kube-proxy

```bash
kubectl config set-cluster ${CLUSTER_NAME} \
  --certificate-authority=certs/ca.crt \
  --embed-certs=true \
  --server=${API_SERVER} \
  --kubeconfig=kube-proxy.kubeconfig
```

```bash
kubectl config set-credentials system:kube-proxy \
  --client-certificate=certs/kube-proxy.crt \
  --client-key=private/kube-proxy.key \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
```

```bash
kubectl config set-context default \
  --cluster=${CLUSTER_NAME} \
  --user=system:kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
```

```bash
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
```

---
## Step 4. Controller-manager

```bash
kubectl config set-cluster ${CLUSTER_NAME} \
  --certificate-authority=certs/ca.crt \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kube-controller-manager.kubeconfig
```

```bash
kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=certs/kube-controller-manager.crt \
  --client-key=private/kube-controller-manager.key \
  --embed-certs=true \
  --kubeconfig=kube-controller-manager.kubeconfig
```

```bash
kubectl config set-context default \
  --cluster=${CLUSTER_NAME} \
  --user=system:kube-controller-manager \
  --kubeconfig=kube-controller-manager.kubeconfig
```

```bash
kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
```

---
## Step 5. Kube-scheduler

```bash
kubectl config set-cluster ${CLUSTER_NAME} \
  --certificate-authority=certs/ca.crt \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kube-scheduler.kubeconfig
```

```bash
kubectl config set-credentials system:kube-scheduler \
  --client-certificate=certs/kube-scheduler.crt \
  --client-key=private/kube-scheduler.key \
  --embed-certs=true \
  --kubeconfig=kube-scheduler.kubeconfig
```

```bash
kubectl config set-context default \
  --cluster=${CLUSTER_NAME} \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig
```

```bash
kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
```

---
## Step 6. Distribute the kubeconfigs

move kubeconfigs to central folder:
```bash
mv *.kubeconfig ./kubeconfigs/
```

folder creation (should already exist):
```bash
# control plane
ssh debian@control-plane "sudo install -d -m 0755 /etc/kubernetes"

# workers
for n in worker1 worker2 worker3; do
  ssh debian@$n "sudo install -d -m 0755 /var/lib/kubelet /var/lib/kube-proxy"
done
```

COntrol plane:
```bash
scp kubeconfigs/admin.kubeconfig \
    kubeconfigs/kube-controller-manager.kubeconfig \
    kubeconfigs/kube-scheduler.kubeconfig \
    debian@control-plane:~/
```

```bash
ssh debian@control-plane "
  sudo install -m 0644 -o root -g root kube-controller-manager.kubeconfig /etc/kubernetes/kube-controller-manager.kubeconfig &&
  sudo install -m 0644 -o root -g root kube-scheduler.kubeconfig /etc/kubernetes/kube-scheduler.kubeconfig &&

  # pick ONE of these admin options:

  # Option A: admin kubeconfig for root kubectl
  sudo install -d -m 0700 /root/.kube &&
  sudo install -m 0600 -o root -g root admin.kubeconfig /root/.kube/config &&

  rm -f admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig
"
```

workers:
```bash
for n in worker1 worker2 worker3; do
  scp "kubeconfigs/kubelet-${n}.kubeconfig" \
      kubeconfigs/kube-proxy.kubeconfig \
      debian@${n}:~/

  ssh debian@${n} "
    sudo install -m 0600 -o root -g root kubelet-${n}.kubeconfig /var/lib/kubelet/kubeconfig &&
    sudo install -m 0600 -o root -g root kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig &&
    rm -f kubelet-${n}.kubeconfig kube-proxy.kubeconfig
  "
done
```
