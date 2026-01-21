# Phase 8: Smoke Test

## Cross pod networking
Create 2 pods:
```
kubectl run a --image=busybox --restart=Never -- sleep 3600
kubectl run b --image=busybox --restart=Never -- sleep 3600
```

Check where they run with `kubectl get pods -o wide:
```
NAME   READY   STATUS    RESTARTS   AGE   IP           NODE      NOMINATED NODE   READINESS GATES
a      1/1     Running   0          10s   10.200.1.4   worker1   <none>           <none>
b      1/1     Running   0          5s    10.200.2.4   worker2   <none>           <none>
```

Perform a ping test with `kubectl exec -it a -- ping 10.200.2.4` :
```
PING 10.200.2.4 (10.200.2.4): 56 data bytes
64 bytes from 10.200.2.4: seq=0 ttl=62 time=1.055 ms
64 bytes from 10.200.2.4: seq=1 ttl=62 time=0.888 ms
64 bytes from 10.200.2.4: seq=2 ttl=62 time=0.369 ms
64 bytes from 10.200.2.4: seq=3 ttl=62 time=0.436 ms
```

---
## Data encryption
Create a secret:
```
kubectl create secret generic kubernetes-the-hard-way --from-literal="mykey=mydata"
```

check if it exists with `kubectl get secret kubernetes-the-hard-way` :
```
NAME                      TYPE     DATA   AGE
kubernetes-the-hard-way   Opaque   1      3m21s
```

on the control-plane, run this command to print a hexdump
```
etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/etcd.crt \
  --key=/etc/etcd/etcd.key \
  get /registry/secrets/default/kubernetes-the-hard-way | hexdump -C
```

This output indicates that the secret is encrypted:
```
00000000  2f 72 65 67 69 73 74 72  79 2f 73 65 63 72 65 74  |/registry/secret|
00000010  73 2f 64 65 66 61 75 6c  74 2f 6b 75 62 65 72 6e  |s/default/kubern|
00000020  65 74 65 73 2d 74 68 65  2d 68 61 72 64 2d 77 61  |etes-the-hard-wa|
00000030  79 0a 6b 38 73 3a 65 6e  63 3a 61 65 73 63 62 63  |y.k8s:enc:aescbc|
00000040  3a 76 31 3a 6b 65 79 31  3a 90 69 4a 80 56 08 c3  |:v1:key1:.iJ.V..|
00000050  30 63 92 45 c0 f5 11 e2  2d fb e7 34 d1 5f b5 85  |0c.E....-..4._..|
00000060  f2 1e cc 0f ce 58 20 13  1a d0 a1 77 3f 52 78 b9  |.....X ....w?Rx.|
00000070  ab e8 1c b5 b2 70 26 cd  b8 69 92 33 46 fb 92 d1  |.....p&..i.3F...|
00000080  4d 35 bb ce b5 45 b7 a1  51 41 5a fe b9 7a a8 22  |M5...E..QAZ..z."|
00000090  ec e7 57 53 ec bd bf 62  2c 9d 61 3a ba dd e8 b6  |..WS...b,.a:....|
000000a0  f1 22 33 6f 33 f2 cd 5b  28 4e b9 98 cb 83 97 0c  |."3o3..[(N......|
000000b0  b1 15 f1 0e db 13 1a c5  a3 83 16 b6 78 e5 c7 5f  |............x.._|
000000c0  00 dc 88 b5 57 fe 41 a0  6f 0b 4d 4d 62 87 17 59  |....W.A.o.MMb..Y|
000000d0  3e 15 e7 d1 6b 79 33 29  e3 8d 72 e5 f6 6d 50 ee  |>...ky3)..r..mP.|
000000e0  9f 15 3b 0c 3b 58 91 3f  4f cd 44 3f d9 2b 41 72  |..;.;X.?O.D?.+Ar|
000000f0  bc 66 2f 50 82 a3 b3 6b  16 c6 35 19 dd 66 85 40  |.f/P...k..5..f.@|
00000100  ba be 26 8a a9 b8 8a 01  32 13 2a fa f2 95 9b 56  |..&.....2.*....V|
00000110  0b cc 30 92 87 f2 fb 28  bd 5b c6 3e b5 9c 48 29  |..0....(.[.>..H)|
00000120  0f 2f 64 0a f4 08 d7 53  1e 5c 00 8f 2d 91 7e 9a  |./d....S.\..-.~.|
00000130  47 ce c4 da 49 f5 1a c9  86 ab 05 e4 12 a1 08 98  |G...I...........|
00000140  d3 d1 7b 28 b8 3c d1 45  21 ba 21 d1 fd b0 7d 7d  |..{(.<.E!.!...}}|
00000150  f8 07 00 a0 e4 e9 3f 08  24 0a                    |......?.$.|
0000015a
```

---
## Expose Application

### Deployment
In the terminal, run:
`kubectl create deployment nginx --image=nginx:latest --replicas=3`

This will create one single Deployment consisting of 3 identical pods. You can check them out with `kubectl get pods`:

```
NAME                     READY   STATUS              RESTARTS   AGE
nginx-5869d7778c-8kbxz   1/1     Running             0          4s
nginx-5869d7778c-8wnv2   0/1     ContainerCreating   0          4s
nginx-5869d7778c-dft7r   0/1     ContainerCreating   0          4s
```

If you run `kubectl get pods -o wide`, you can see how the Pods are spread out across the Nodes:

```
NAME                     READY   STATUS    RESTARTS   AGE    IP           NODE           NOMINATED NODE   READINESS GATES
nginx-5869d7778c-8kbxz   1/1     Running   0          4m9s   10.244.2.3   minikube-m03   <none>           <none>
nginx-5869d7778c-8wnv2   1/1     Running   0          4m9s   10.244.1.2   minikube-m02   <none>           <none>
nginx-5869d7778c-dft7r   1/1     Running   0          4m9s   10.244.0.3   minikube       <none>           <none>
```

### Expose the Deployment
The Deployment is created, but the pods aren't exposed to the outside. Run:
`kubectl expose deployment nginx --port=8000 --target-port=80`

This will create a ClusterIP service to establish connectivity between different applications internally within the Kubernetes cluster. expose the Pods internal ports 80 to port 8000 outside the pods. You can see this by running `kubectl get services`:

```
NAME         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
kubernetes   ClusterIP   10.96.0.1        <none>        443/TCP    2d13h
nginx        ClusterIP   10.104.148.211   <none>        8000/TCP   4s
```

### Port-Forward it
The connectivity still lives inside the cluster, but you probably want to expose it outside the cluster. Run:
`kubectl port-forward service/nginx 5000:8000`

This forwards port 8000 inside the cluster to 5000 outside the cluster. In this case, localhost (because we are running the cluster locally on the computer).

```
Forwarding from 127.0.0.1:5000 -> 80
Forwarding from [::1]:5000 -> 80
```

You can now reach the NGINX homepage with localhost:5000
![[Pasted image 20251129104044.png]]
### Delete the Deployment
To delete the pods for good, you actually have to delete the deployment. This will remove all the pods with it.

Check the deployment with`kubectl get deployments`:
```
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
nginx   3/3     3            3           72m
```

Delete the deployment with `kubectl delete deployment nginx`

You also have to delete the ClusterIP service with `kubectl delete service nginx`
