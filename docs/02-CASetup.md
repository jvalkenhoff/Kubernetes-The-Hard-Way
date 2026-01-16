# Phase 2: CA Setup
We will setup the CA entirely from scratch. It uses a Root CA Setup. If you want to know more how it's setup, check:
- [PKI certificates and requirements | Kubernetes](https://kubernetes.io/docs/setup/best-practices/certificates/) - Official Kubernetes docs about the CA requirements
- [A.5. Creating Your Own Certificates | Security Guide | Red Hat AMQ | 6.2 | Red Hat Documentation](https://docs.redhat.com/en/documentation/red_hat_amq/6.2/html/security_guide/createcerts) - Redhat docs for setting up own CA
- [kubernetes-the-harder-way/docs/04_Bootstrapping_Kubernetes_Security.md at linux · ghik/kubernetes-the-harder-way](https://github.com/ghik/kubernetes-the-harder-way/blob/linux/docs/04_Bootstrapping_Kubernetes_Security.md#the-service-account-token-signing-certificate) - This phase roughly follows this guide

## Step 1. Prepare CA Directory

### Directory setup
On the jumpbox, run:
```
mkdir -p ~/k8s-ca/{certs,crl,newcerts,private,config}
cd ~/k8s-ca
chmod 700 private
```

### Default state
This creates the database and serial increments:
```
touch index.txt
echo 1000 > serial
echo 1000 > crlnum
```

## Step 2. Build Root CA
### CA config
Create `config/root-ca.cnf`
```ini
[ ca ]
default_ca = k8s_root_ca

[ k8s_root_ca ]
dir           = /home/debian/k8s-ca
certs         = $dir/certs
crl_dir       = $dir/crl
new_certs_dir = $dir/newcerts
database      = $dir/index.txt
serial        = $dir/serial
crlnumber     = $dir/crlnum

private_key = $dir/private/ca.key
certificate = $dir/certs/ca.crt

default_md    = sha256
default_days  = 365
policy        = k8s_policy

unique_subject  = no
copy_extensions = copy
```

### CA Policy
Within the same file, add the policy:
```ini
[ k8s_policy ]
commonName              = supplied
organizationName        = optional
organizationalUnitName  = optional
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
emailAddress            = optional
```

### CSR defaults
In `config/root-ca.cnf`, append default settings for CSRs:
```ini
[ req ]
default_bits        = 4096
default_md          = sha256
prompt              = no
distinguished_name  = req_dn
```

### Root CA DN
```ini
[ req_dn ]
CN  = kubernetes-root-ca
O   = kubernetes
```

### Extensions
```ini
[ v3_ca ]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always,issuer
basicConstraints        = critical, CA:true
keyUsage                = critical, keyCertSign, cRLSign
```

Save the file

---
## Step 3. Create Root CA

### Private Key
generate the root ca private key:
```
openssl genrsa -out private/ca.key 4096
chmod 600 private/ca.key
```

### Root CA
Run this to generate the root CA:
```
openssl req -new -x509 -key private/ca.key -out certs/ca.crt -days 3650 -config config/root-ca.cnf -extensions v3_ca
```

Verify the CA:
```
openssl x509 -in certs/ca.crt -noout -text
```

You should see:
`CA:TRUE`
`Key Usage: Certificate Sign, CRL Sign`

---
## Step 4. CA Profiles
not necessary. But in real CA you never issue certs without certificate profiles.

### Add to CA Config
open the CA config to add the certificate profiles:
```
vim ~/k8s-ca/config/root-ca.cnf
```
#### Client
Issues for kubectl, controller-manager, scheduler

```ini
[ client_cert ]
basicConstraints        = CA:FALSE
keyUsage                = critical, digitalSignature, keyEncipherment
extendedKeyUsage        = clientAuth
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid,issuer
```

#### Server
Issues for the API server
```ini
[ server_cert ]
basicConstraints        = CA:FALSE
keyUsage                = critical, digitalSignature, keyEncipherment
extendedKeyUsage        = serverAuth
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid,issuer
```

#### Peer
Issues for the kubelet
```ini
[ peer_cert ]
basicConstraints        = CA:FALSE
keyUsage                = critical, digitalSignature, keyEncipherment
extendedKeyUsage        = serverAuth, clientAuth
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid,issuer
```

---
## Step 5. Certificates

We will setup certificates for each component in the following order:
1. CSR config creation
2. CSR creation against private key and config
3. Certificate creation by signing the CSR
### 1. kubectl
Create `config/admin.cnf`
```ini
[ req ]
default_bits        = 4096
prompt              = no
default_md          = sha256
distinguished_name  = dn

[ dn ]
CN  = admin
O   = system:masters
```

Create private key, create CSR with private key and config:
```
openssl genrsa -out private/admin.key 4096

openssl req -new -key private/admin.key -out csr/admin.csr -config config/admin.cnf
```

Sign the CSR using the CA, **client_cert** profile:
```
openssl ca -config config/root-ca.cnf -extensions client_cert -in csr/admin.csr -out certs/admin.crt
```

Verify by running:
```
openssl x509 -in certs/admin.crt -noout -text | grep -A2 "Extended Key Usage"
```

You should see:
```
TLS Web Client Authentication
```

### 2. Controller Manager
Create `config/kube-controller-manager.cnf`
```ini
[ req ]
prompt            = no
default_md        = sha256
distinguished_name = dn

[ dn ]
CN = system:kube-controller-manager
```

Create private key, create CSR with private key and config:
```
openssl genrsa -out private/kube-controller-manager.key 4096

openssl req -new -key private/kube-controller-manager.key -out csr/kube-controller-manager.csr -config config/kube-controller-manager.cnf
```

Sign the CSR using the CA, **client_cert** profile:
```
openssl ca -config config/root-ca.cnf -extensions client_cert -in csr/kube-controller-manager.csr -out certs/kube-controller-manager.crt
```

Verify by running:
```
openssl x509 -in certs/kube-controller-manager.crt -noout -text | grep -A2 "Extended Key Usage"
```

You should see:
```
TLS Web Client Authentication
```

### 3. Scheduler
Create `config/kube-scheduler.cnf`
```ini
[ req ]
prompt              = no
default_md          = sha256
distinguished_name  = dn

[ dn ]
CN = system:kube-scheduler
```

Create private key, create CSR with private key and config:
```
openssl genrsa -out private/kube-scheduler.key 4096

openssl req -new -key private/kube-scheduler.key -out csr/kube-scheduler.csr -config config/kube-scheduler.cnf
```

Sign the CSR using the CA, **client_cert** profile:
```
openssl ca -config config/root-ca.cnf -extensions client_cert -in csr/kube-scheduler.csr -out certs/kube-scheduler.crt
```

Verify by running:
```
openssl x509 -in certs/kube-scheduler.crt -noout -text | grep -A2 "Extended Key Usage"
```

You should see:
```
TLS Web Client Authentication
```

### 4. API Server
The API server works a bit differently. the SANs are very important here:
```ini
[ req ]
default_bits        = 4096
prompt              = no
default_md          = sha256
distinguished_name  = dn
req_extensions      = req_ext

[ dn ]
CN = kube-apiserver

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
DNS.5 = control-plane
DNS.6 = control-plane.k8s.local
IP.1  = 10.20.0.10
IP.2  = 127.0.0.1
```

generate key + csr:
```
openssl genrsa -out private/kube-apiserver.key 4096

openssl req -new -key private/kube-apiserver.key -out csr/kube-apiserver.csr -config config/kube-apiserver.cnf
```

Sign the CSR using the CA, **server_cert** profile:
```
openssl ca -config config/root-ca.cnf -extensions server_cert -in csr/kube-apiserver.csr -out certs/kube-apiserver.crt
```

Verify by running, this time look for Subject Alternative Name:
```
openssl x509 -in certs/kube-apiserver.crt -noout -text | grep -A1 "Subject Alternative Name"
```

You should see:
```
X509v3 Subject Alternative Name:
    DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, DNS:control-plane, DNS:control-plane.k8s.local, IP Address:10.20.0.10, IP Address:127.0.0.1
```

### 5. Kubelets
For each worker we need a certificate for the kubelet. The following steps can be repeated for worker2, worker3

create `config/kubelet-worker1.cnf`
```ini
[ req ]
prompt  = no
default_md  = sha256
distinguished_name  = dn
req_extensions      = req_ext

[ dn ]
CN = system:node:worker1
O  = system:nodes

[ req_ext ]
subjectAltName  = @alt_names

[ alt_names ]
DNS.1 = worker1
DNS.2 = worker1.k8s.local
IP.1  = 10.20.0.11
```

generate key + csr:
```
openssl genrsa -out private/kubelet-worker1.key 4096

openssl req -new -key private/kubelet-worker1.key -out csr/kubelet-worker1.csr -config config/kubelet-worker1.cnf
```

Sign the CSR using the CA, **peer_cert** profile:
```
openssl ca -config config/root-ca.cnf -extensions peer_cert -in csr/kubelet-worker1.csr -out certs/kubelet-worker1.crt
```

Verify, no `grep` because we need to look in multiple places:
```
openssl x509 -in certs/kubelet-worker1.crt -noout -text
```

Subject:
```
Subject: CN = system:node:worker1, O = system:nodes
```

Extended Key Usage:
```
X509v3 Extended Key Usage:
    TLS Web Server Authentication, TLS Web Client Authentication
```

Subject Alternative Name:
```
X509v3 Subject Alternative Name:
    DNS:worker1, DNS:worker1.k8s.local, IP Address:10.20.0.11
```

Repeat for worker2:
- CN: `system:node:worker2`
- IP: `10.20.0.12`

worker3:
- CN: `system:node:worker3`
- IP: `10.20.0.12`

### 6. kube-proxy
Although kube-proxy runs on every worker node, it has one single identity. We only need to create one certificate.
create `config/kube-proxy.cnf`
```ini
[ req ]
prompt = no
default_md = sha256
distinguished_name = dn

[ dn ]
CN = system:kube-proxy
```

Create private key, create CSR with private key and config:
```
openssl genrsa -out private/admin.key 4096

openssl req -new -key private/admin.key -out csr/admin.csr -config config/admin.cnf
```

Sign the CSR using the CA, **client_cert** profile:
```
openssl ca -config config/root-ca.cnf -extensions client_cert -in csr/admin.csr -out certs/admin.crt
```

Verify by running:
```
openssl x509 -in certs/admin.crt -noout -text | grep -A2 "Extended Key Usage"
```

You should see:
```
TLS Web Client Authentication
```

### 7. etcd
Create `config/etcd.cnf`
```ini
[ req ]
default_bits        = 4096
prompt              = no
default_md          = sha256
distinguished_name  = dn
req_extensions      = req_ext

[ dn ]
CN = etcd

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = control-plane
DNS.2 = localhost
IP.1  = 10.20.0.10
IP.2  = 127.0.0.1
```

Create private key, create CSR with private key and config:
```
openssl genrsa -out private/etcd.key 4096

openssl req -new -key private/etcd.key -out csr/etcd.csr -config config/etcd.cnf
```

Sign the CSR using the CA, **peer_cert** profile:
```
openssl ca -config config/root-ca.cnf -extensions peer_cert -in csr/etcd.csr -out certs/etcd.crt
```

Verify by running:
```
openssl x509 -in certs/etcd.crt -noout -text
```

**Check carefully:**
Subject
```
Subject: CN = etcd
```

Extended Key Usage
```
X509v3 Extended Key Usage:
    TLS Web Server Authentication, TLS Web Client Authentication
```

Subject Alternative Name
```
X509v3 Subject Alternative Name:
    DNS:control-plane, DNS:localhost, IP Address:10.20.0.10, IP Address:127.0.0.1
```

---
## Step 6. SA Signing Key
Not really related to the CA, still meaningful to do it now

run:
```
openssl genrsa -out private/sa.key 4096
```

extract the public key:
```
openssl rsa -in private/sa.key -pubout -out certs/sa.pub
```

Verify if both are created:
```
ls certs/sa*
ls private/sa*
```

---
## Step 7. Distribute Certificates
### Decide Locations
I will use these paths for distributing the certificates:
- **CA Trust:** `/etc/kubernetes/pki/ca.crt`
- **Components:** `/etc/kubernetes/pki/*.crt | *.key`
- **Service Account:** `/etc/kubernetes/pki/sa.key` and `/etc/kubernetes/pki/sa.pub`

### Create directories
On the control plane:
```bash
ssh debian@control-plane "sudo mkdir -p /etc/kubernetes/pki /var/lib/kubernetes && sudo chown -R root:root /etc/kubernetes /var/lib/kubernetes"
```

For each worker:
```bash
for n in worker1 worker2 worker3; do
	ssh debian@$n "sudo mkdir -p /etc/kubernetes/pki /var/lib/kubelet /var/lib/kubernetes && sudo chown -R root:root /etc/kubernetes /var/lib/kubelet /var/lib/kubernetes"
done
```

### Control Plane
Control Plane needs the following:
- CA Cert
- API server cert and key
- kube controller manager cert and key
- scheduler cert and key
- etcd cert and key
- service account private and public key

```bash
scp certs/ca.crt debian@control-plane:/tmp/
scp certs/kube-apiserver.crt private/kube-apiserver.key debian@control-plane:/tmp/
scp certs/kube-controller-manager.crt private/kube-controller-manager.key debian@control-plane:/tmp/
scp certs/kube-scheduler.crt private/kube-scheduler.key debian@control-plane:/tmp/
scp private/sa.key certs/sa.pub debian@control-plane:/tmp/
```

Move files into place:
```bash
ssh debian@control-plane 'sudo mv /tmp/ca.crt /etc/kubernetes/pki/ca.crt'
ssh debian@control-plane 'sudo mv /tmp/kube-apiserver.crt /etc/kubernetes/pki/ && sudo mv /tmp/kube-apiserver.key /etc/kubernetes/pki/'
ssh debian@control-plane 'sudo mv /tmp/kube-controller-manager.crt /etc/kubernetes/pki/ && sudo mv /tmp/kube-controller-manager.key /etc/kubernetes/pki/'
ssh debian@control-plane 'sudo mv /tmp/kube-scheduler.crt /etc/kubernetes/pki/ && sudo mv /tmp/kube-scheduler.key /etc/kubernetes/pki/'
ssh debian@control-plane 'sudo mv /tmp/sa.key /etc/kubernetes/pki/sa.key && sudo mv /tmp/sa.pub /etc/kubernetes/pki'

ssh debian@control-plane 'sudo chmod 600 /etc/kubernetes/pki/*.key'
```

### Worker nodes
Each worker node needs:
- CA Cert
- its own kubelet crt and key
- shared kubeproxy crt and key

```bash
scp certs/ca.crt debian@worker1:/tmp/
scp certs/kubelet-worker1.crt private/kubelet-worker1.key debian@control-plane:/tmp/
scp certs/kube-proxy.crt private/kube-proxy.key debian@control-plane:/tmp/
```

move files into place:
```bash
ssh debian@worker1 'sudo mv /tmp/ca.crt /etc/kubernetes/pki/ca.crt'
ssh debian@worker1 'sudo mv /tmp/kubelet-worker1.crt /etc/kubernetes/pki/ && sudo mv /tmp/kubelet-worker1.key /etc/kubernetes/pki/'
ssh debian@worker1 'sudo mv /tmp/kube-proxy.crt /etc/kubernetes/pki/ && sudo mv /tmp/kube-proxy.key /etc/kubernetes/pki/'
```
