# Phase 5: Jumpbox Setup

- [Base packages](#base-packages)
- [Time synchronization](#time-synchronization)
- [Download Binaries](#download-binaries)
- [Kubectl](#kubectl)
## Base packages
Install the these packages. This is all you need really.
```
sudo apt update
sudo apt install -y curl wget tree ca-certificates gnupg openssl jq chrony vim
```

Verify:
```
openssl version
curl --version
jq --version
```

## Time synchronization
TLS **will break** if time is out of sync.

Check the timezone:
```bash
timedatectl status
```

If time is out of sync, set the timezone according to your local area:
```
timedatectl set-timezone <area>/<location>

# example
timedatectl set-timezone Europe/Amsterdam
```

Synchronize the hardware clock:
```
systemctl enable --now chrony
```

Verify with:
```
chronyc tracking
```

- `Leap status : Normal`
- `System Time` should be < 0.1 seconds

## Download Binaries
In Iteration 0, everything is downloaded by hand. Instead of that, I build a script which downloads the necessary binaries and distributes them.

Get this file:
```bash
wget -P ~/ https://raw.githubusercontent.com/jvalkenhoff/Kubernetes-The-Hard-Way/refs/heads/iteration-1/scripts/fetch-k8s-binaries.sh
```

It needs a `downloads.txt` file. Download this too:
```bash
wget -P /tmp/ https://raw.githubusercontent.com/jvalkenhoff/Kubernetes-The-Hard-Way/refs/heads/iteration-1/downloads.txt
```

This will download and organize all required Kubernetes binaries in a clean directory structure.

## Kubectl
Install kubectl right away
```
sudo install -m 0755 ~/downloads/client/kubectl /usr/local/bin/kubectl
```

Verify:
`kubectl version --client`

Should show:
```
Client Version: v1.34.2
Kustomize Version: v5.7.1
```

