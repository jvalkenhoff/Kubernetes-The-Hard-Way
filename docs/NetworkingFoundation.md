# Phase 2 Networking Foundation
Networking will have its own Phase. VMs should be able to attach to a network that has already been setup.
To keep everything clustered, I will setup a bridged network with `virsh`. In later stages, tap networks like `macvtap` will be used.

- [Network Design](#network-design)
- [MAC Address](#mac-address)
- [Network Definition](#network-definition)
- [Network Activation](#network-activation)
- [Verify](#verify)

## Network Design
The network layout has been defined during the [Planning Phase](https://github.com/jvalkenhoff/Kubernetes-The-Hard-Way/blob/iteration-1/docs/00-InfraPlanning.md#networking). Here is the layout once more:

**Network**
- **Subnet**: `10.20.0.0/24`
- **Gateway (libvirt)**: `10.20.0.1`

**VMs**
- **Jumpbox**: `10.20.0.5`
- **cp1**: `10.20.0.10`
- **API (virtual host):** `10.20.0.9`
- **w1**: `10.20.0.11`
- **w2:** `10.20.0.12`
- **w3:** `10.20.0.13`

## MAC Address
In order to setup the network cleanly, we need MAC addresses as well. I have created a script, which will generate MAC addresses for us:
```bash
./gen-macs.sh w1 w2 w3 cp1 api jumpbox
```

This will output:
```
w1:        52:54:00:60:c5:59
w2:        52:54:00:06:f8:fa
w3:        52:54:00:55:ea:e5
cp1:       52:54:00:30:6b:6a
api:       52:54:00:14:c2:52
jumpbox:   52:54:00:a4:a2:df
```

## Network Definition
In order to setup a bridged network, a network definition needs to be created. Name it `k8s-net.xml`. In here, the network will be defined according to the planned design:
```xml
<network>
  <name>k8s-net</name>
  <forward mode='nat'/>
  <bridge name='virbr20' stp='on' delay='0'/>
  <domain name='k8s.local' localOnly='yes' />
    
  <ip address='10.20.0.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='10.20.0.200' end='10.20.0.254'/>
      
      <!-- Jumpbox -->
      <host mac='52:54:00:a4:a2:df' name='jumpbox' ip='10.20.0.5'/>

      <!-- Virtual API, points to cp1 -->
      <host mac='52:54:00:14:c2:52' name='api' ip='10.20.0.9'/>

      <!-- Control Plane -->
      <host mac='52:54:00:30:6b:6a' name='cp1' ip='10.20.0.10'/>

      <!-- Workers -->
      <host mac='52:54:00:60:c5:59' name='w1' ip='10.20.0.11'/>
      <host mac='52:54:00:06:f8:fa' name='w2' ip='10.20.0.12'/>
      <host mac='52:54:00:55:ea:e5' name='w3' ip='10.20.0.13'/>
    </dhcp>
  </ip>
</network>
```

> [!NOTE]
> The API has not been fully explained yet. This will be covered later.

## Network Activation
Activate the network, and start it:
```bash
sudo virsh net-define k8s-net.xml
sudo virsh net-start k8s-net
sudo virsh net-autostart k8s-net
```

## Verify
Perform the following checks:
- [ ] `k8s-net` is active
- [ ] `virbr20` exists on the host 

```bash
sudo virsh net-list --all
ip link | grep iA1 virbr20
```

