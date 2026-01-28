# Phase 1: Infrastructure Setup
This phase prepares the virtualization backend. No VMs will be installed yet.

- [Storage Backend](#storage-backend)
  - [Physical Volume](#physical-volume)
  - [Create volume group](#create-volume-group)
  - [Verify LVM State](#verify-lvm-state)
- [Libvirt Storage Pool](#libvirt-storage-pool)
  - [Create backend Pool](#create-backend-pool)
  - [Start and autostart Pool](#start-and-autostart-pool)
  - [Verify Pool](#verify-pool)
- [VM Disks](#vm-disks)
  - [Naming](#naming)
  - [Create Logical Volumes](#create-logical-volumes)
  - [Verify Disk layout](#verify-disk-layout)

## Storage Backend
Kubernetes needs long lived VMs. The disks should be persistent and isolated.

### Physical Volume
Make sure you have an empty disk or partition ready.
In this setup, I will use `/dev/nvme0n1p6` as my dedicated partition to create the physical volume.
```bash
sudo pvcreate /dev/nvme0n1p6
```

This initializes the block device for LVM usage

### Create volume group
Create a dedicated volume group for Kubernetes related storage:
```bash
sudo vgcreate k8s /dev/nvme0n1p6
```

### Verify LVM State
Perform the following checks:
- [ ] PV is allocated
- [ ] VG `k8s` exists
- [ ] Free space is available

```bash
sudo pvdisplay /dev/nvme0n1p6
sudo vgdisplay k8s
sudo vgs
```


## Libvirt Storage Pool
Libvirt can create and manage volumes. But it does not manage the LVM directly. So it consumes storage using **pools**.

### Create backend Pool
Create a libvirt storage pool that maps directly to the `k8s` volume group:
```bash
sudo virsh pool-define-as k8s_nodes logical --source-name k8s
```

### Start and autostart Pool
This ensures that the pool is immediately available if the host reboots, or powers on.
```bash
sudo virsh pool-start k8s_nodes
sudo virsh pool-autostart k8s_nodes
```

### Verify Pool
Perform the following checks:
- [ ] The `k8s_nodes` pool is active
- [ ] Type is `logical`
- [ ] Source VG is `k8s`

```bash
sudo virsh pool-list --all
sudo virsh pool-info k8s_nodes
sudo virsh pool-dumpxml k8s_nodes
```

## VM Disks
After defining the pool, each node will get its own logical volume.
### Naming
Naming has been defined during the [Planning Phase](https://github.com/jvalkenhoff/Kubernetes-The-Hard-Way/blob/iteration-1/docs/00-InfraPlanning.md#naming). To keep everything obvious, we will align the LV names with the VM names.

| Name      | LV        | Storage |
| --------- | --------- | ------- |
| `jumpbox` | `jumpbox` | 15GB    |
| `cp1`     | `cp1`     | 25GB    |
| `w1`      | `w1`      | 25GB    |
| `w2`      | `w2`      | 25GB    |
| `w3`      | `w3`      | 25GB    |

### Create Logical Volumes
```bash
sudo virsh vol-create-as k8s_nodes cp1 25G --format raw
sudo virsh vol-create-as k8s_nodes w1 25G --format raw
sudo virsh vol-create-as k8s_nodes w2 25G --format raw
sudo virsh vol-create-as k8s_nodes w3 25G --format raw
sudo virsh vol-create-as k8s_nodes jumpbox 15G --format raw
```

> [!NOTE]
> You could also go for `qcow2` as format if you want easier snapshots.

### Verify Disk layout
- [ ] Each LV exists
- [ ] Each LV has their appropriate size
- [ ] Each LV maps to `/dev/k8s/`

```bash
sudo lvs -a -o +devices
sudo virsh vol-list k8s_nodes
```
