# Design: Modify dranet to Support InfiniBand-only Devices on AKS

## Context

dranet works on GKE because GKE GPU VMs use **Ethernet mode (RoCE)** NICs with standard netdev interfaces and standard PCI topology. On AKS, GB300 VMs (ND_GB300_v6) use **InfiniBand mode** NICs — ConnectX VFs that have only RDMA devices (`mlx5_0`-`mlx5_3`) with no netdev interface. dranet fails at three points:

1. `PrepareResourceClaim` -> `GetNetInterfaceName()` fails: "device has no interface name in local store"
2. PCIe root resolution fails: Azure VMBUS paths don't start with `/sys/devices/pci*`
3. `nsAttachNetdev()` has no interface to move into the pod namespace

This design modifies the dranet fork (`ghcr.io/anson627/dranet`) to handle IB-only devices natively.

## Scope

Upstream repo: `https://github.com/kubernetes-sigs/dranet` (fork to `github.com/anson627/dranet`)

Files to modify:
- `pkg/inventory/db.go` — device discovery, IB-only device handling
- `pkg/inventory/sysfs.go` — PCIe root resolution for VMBUS paths
- `pkg/driver/dra_hooks.go` — PrepareResourceClaim RDMA-only path
- `pkg/driver/nri_hooks.go` — RunPodSandbox skip netdev for IB-only
- `pkg/driver/pod_device_config.go` — PodConfig IBOnly flag
- `pkg/apis/attributes.go` — new attribute constants

Files to update after build:
- `nvidia/dranet/daemonset.yaml` — image tag
- `nccl/resource-claim-template.yaml` — pcieRoot constraint

## Phase 1: Device Discovery for IB-only Devices

### Problem

`db.go` `scan()` discovers PCI devices and correlates them with netlink interfaces. IB VFs have no netlink interface, so they get PCI address and RDMA attributes but no `ifName`. Currently `GetNetInterfaceName()` returns error for these devices.

### Changes in `pkg/inventory/db.go`

1. **Add IB-only device detection in `scan()`**:
   - After PCI device enumeration, check `/sys/class/infiniband/` for RDMA devices
   - For each RDMA device, resolve its PCI address via sysfs symlink
   - If the PCI address matches a discovered device that has NO netdev interface, mark it as IB-only
   - Set a new attribute `dra.net/ibOnly: true`
   - Set `dra.net/rdmaDevice` to the RDMA link name (e.g., `mlx5_0`)

2. **Add `GetRDMADeviceName(deviceName string) (string, error)` method**:
   - Lookup RDMA device name from the device store by PCI-based device key
   - Returns the RDMA link name (e.g., `mlx5_0`) for IB-only devices

3. **Add `IsIBOnlyDevice(deviceName string) bool` method**:
   - Check if a device in the store has `ibOnly == true`

### New Attributes in `pkg/apis/attributes.go`

```go
const (
    AttrIBOnly     = "ibOnly"      // bool: true for IB-only devices (no netdev)
    AttrRDMADevice = "rdmaDevice"  // string: RDMA link name (e.g., "mlx5_0")
)
```

### Expected Result

IB-only devices in ResourceSlice:

```yaml
name: pci-0101-00-00-0
attributes:
  dra.net/rdma: true
  dra.net/ibOnly: true
  dra.net/rdmaDevice: "mlx5_0"
  dra.net/pciAddress: "0101:00:00.0"
  dra.net/numaNode: 1
  dra.net/pciSubsystem: "0007"
  dra.net/pciVendor: "Mellanox Technologies"
  resource.kubernetes.io/pcieRoot: "vmbus-numa-1"
```

## Phase 2: PCIe Root Resolution and NCCL Topology

### Background

dranet resolves PCIe root using `k8s.io/dynamic-resource-allocation/deviceattribute.GetPCIeRootAttributeByPCIBusID()`, which follows sysfs symlinks to find `/sys/devices/pciXXXX:XX`. Azure VMBUS devices have paths like:

```
/sys/devices/LNXSYSTM:00/LNXSYBUS:00/ACPI0004:00/VMBUS:00/{guid}/pci{domain}:00/{domain}:00:00.0
```

This doesn't match the expected `/sys/devices/pci*` prefix, causing pcieRoot resolution to fail.

### Current State (Partially Resolved)

GPU driver publishes pcieRoot correctly. dranet NIC pcieRoot is not published — NUMA fallback not yet implemented:

| Environment | dranet pcieRoot | NVIDIA GPU pcieRoot | Alignment Works? |
|-------------|-----------------|---------------------|------------------|
| GKE (standard PCI) | `pci0000:00` | `pci0000:00` | Yes |
| Azure VMBUS (current) | `numa-0` / `numa-1` | `numa-0` / `numa-1` | Yes — NUMA-level matches GB300 topology |

#### Actual Topology Data (Azure AKS GB300 VM)

**`nvidia-smi topo -m`:**

|       | GPU0 | GPU1 | GPU2 | GPU3 | NIC0 | NIC1 | NIC2 | NIC3 | NUMA |
|-------|------|------|------|------|------|------|------|------|------|
| GPU0  | X    | NV18 | NV18 | NV18 | NODE | NODE | SYS  | SYS  | 0    |
| GPU1  | NV18 | X    | NV18 | NV18 | NODE | NODE | SYS  | SYS  | 0    |
| GPU2  | NV18 | NV18 | X    | NV18 | SYS  | SYS  | NODE | NODE | 1    |
| GPU3  | NV18 | NV18 | NV18 | X    | SYS  | SYS  | NODE | NODE | 1    |

NIC mapping: NIC0=mlx5_0, NIC1=mlx5_1, NIC2=mlx5_2, NIC3=mlx5_3

**`lspci` (GPU and NIC devices):**

| Device | PCI Address | Type |
|--------|-------------|------|
| GPU 0 bridge | 0008:00:00.0 | NVIDIA PCI bridge (22b1) |
| GPU 0 | 0008:06:00.0 | NVIDIA GB300 |
| GPU 1 bridge | 0009:00:00.0 | NVIDIA PCI bridge (22b1) |
| GPU 1 | 0009:06:00.0 | NVIDIA GB300 |
| GPU 2 bridge | 0018:00:00.0 | NVIDIA PCI bridge (22b1) |
| GPU 2 | 0018:06:00.0 | NVIDIA GB300 |
| GPU 3 bridge | 0019:00:00.0 | NVIDIA PCI bridge (22b1) |
| GPU 3 | 0019:06:00.0 | NVIDIA GB300 |
| NIC 0 | 0101:00:00.0 | Mellanox ConnectX VF (IB) |
| NIC 1 | 0102:00:00.0 | Mellanox ConnectX VF (IB) |
| NIC 2 | 0103:00:00.0 | Mellanox ConnectX VF (IB) |
| NIC 3 | 0104:00:00.0 | Mellanox ConnectX VF (IB) |

**GB300 Topology Summary:**

| Property | GB300 |
|----------|-------|
| GPUs per node | 4 (NVIDIA Blackwell B300, 288 GB HBM3E each) |
| NICs per node | 4 (800 Gb/s IB each, 400 GB/s total unidirectional) |
| GPU interconnect | NV18 (all-to-all across NUMA) |
| GPU-NIC affinity | 2:2 per NUMA node (NODE relationship) |
| NUMA groups | 2 x (2 GPU + 2 NIC) |
| NUMA-level pcieRoot sufficient? | **Yes** (2:2 matches actual topology) |
| PCI bridges in guest | NVIDIA bridges visible (22b1), one per GPU |
| GPU-NIC PCIe relationship | NODE (same NUMA, different host bridges) |

**Actual ResourceSlice Data (GB300, observed):**

**GPU ResourceSlice** (`gpu.nvidia.com`):

| GPU | pciBusID | numaNode | pcieRoot |
|-----|----------|----------|----------|
| gpu-0 | 0008:06:00.0 | 0 | pci0008:00 |
| gpu-1 | 0009:06:00.0 | 0 | pci0009:00 |
| gpu-2 | 0018:06:00.0 | 1 | pci0018:00 |
| gpu-3 | 0019:06:00.0 | 1 | pci0019:00 |

**NIC ResourceSlice** (`dra.net`):

| NIC | pciAddress | numaNode | rdma | ibOnly | rdmaDevice |
|-----|------------|----------|------|--------|------------|
| pci-0101-00-00-0 | 0101:00:00.0 | 0 | true | **missing** | **missing** |
| pci-0102-00-00-0 | 0102:00:00.0 | 0 | true | **missing** | **missing** |
| pci-0103-00-00-0 | 0103:00:00.0 | 1 | true | **missing** | **missing** |
| pci-0104-00-00-0 | 0104:00:00.0 | 1 | true | **missing** | **missing** |

> **Note**: The current `ghcr.io/anson627/dranet:test` build publishes NIC devices as IPoIB interfaces (with `dra.net/ifName`, `dra.net/type: ipoib`) — **not** as IB-only devices. The `dra.net/ibOnly` and `dra.net/rdmaDevice` attributes are absent. Phase 1 is not yet implemented.

> **Note**: GPU pcieRoot resolves correctly to PCI bridge bus IDs (`pci0008:00` etc.) via the NVIDIA PCI bridges (22b1) visible in the guest. dranet NIC pcieRoot still fails with VMBUS path errors and is not published. GPU-NIC pcieRoot-based constraint matching is therefore not yet possible.

With `matchAttribute: resource.kubernetes.io/pcieRoot`, DRA scheduling would pair 2 GPUs with 2 NICs per NUMA node — matching the actual NODE-level affinity. This is not yet usable because NIC pcieRoot is not published.

### PCIe Root and NCCL Topology on GB300

NUMA-level pcieRoot (`numa-0`/`numa-1`) is sufficient for DRA scheduling on GB300. With 2 GPUs and 2 NICs per NUMA node, all showing equidistant NODE relationships, the NUMA-level grouping correctly captures the topology.

`nvidia-smi topo -m` correctly reports GPU-NIC affinity (NODE vs SYS) on GB300, so NCCL may not require a static topo.xml — this needs benchmarking to confirm.

### Hyper-V Guest Kernel Limitation

Analysis of the Linux Hyper-V PCI controller ([`pci-hyperv.c`](https://github.com/torvalds/linux/blob/master/drivers/pci/controller/pci-hyperv.c)) reveals that **parent bridge bus IDs are not available from the guest kernel**:

1. **Flat topology**: Hyper-V creates a separate `pci_host_bridge` per pass-through device. Each device gets its own paravirtual root bus with no intermediate PCIe bridge devices. The host's PCIe switch hierarchy is not exposed to the guest.

2. **No intermediate bridges in sysfs**: The sysfs path for each device is:
   ```
   /sys/devices/LNXSYSTM:00/.../VMBUS:00/{guid}/pci{domain}:00/{domain}:00:00.0
   ```
   There is no `ffff:ff:XX.0` bridge node — those IDs are synthetic, defined by Azure's HPC team based on the physical hardware topology.

On GB300 this is not a blocking issue — NVIDIA bridges are visible in the guest (PCI device class 22b1), and the 2:2 NUMA grouping provides sufficient granularity without needing to resolve parent PCIe switch bus IDs.

### Recommendation

1. NUMA-level pcieRoot (`numa-0`/`numa-1`) is sufficient for DRA scheduling — no per-switch refinement needed
2. Benchmark NCCL with and without topo.xml to confirm whether `nvidia-smi topo` provides adequate topology information for optimal routing
3. If topo.xml is still needed, create a GB300-specific topo.xml with 2 switches (one per NUMA), each containing 2 GPUs + 2 NICs

## Phase 3: PrepareResourceClaim for RDMA-only Devices

### Problem

`PrepareResourceClaim()` in `dra_hooks.go` calls `GetNetInterfaceName()` and fails for IB-only devices.

### Changes in `pkg/driver/dra_hooks.go`

1. **Add IB-only branch in `PrepareResourceClaim()`**:

   ```go
   // For each allocated device:
   if np.netdb.IsIBOnlyDevice(result.Device) {
       // Skip netdev interface lookup
       // Get RDMA device name instead
       rdmaDevName, err := np.netdb.GetRDMADeviceName(result.Device)
       // Gather RDMA character devices from /dev/infiniband/
       // Build PodConfig with RDMAConfig only (no NetworkInterfaceConfig)
       podConfig := PodConfig{
           IBOnly: true,
           RDMAConfig: &RDMAConfig{
               LinkDevice:  rdmaDevName,  // "mlx5_0"
               CharDevices: charDevices,  // uverbs0, rdma_cm, etc.
           },
       }
   } else {
       // Existing netdev path (unchanged)
       ifName, err := np.netdb.GetNetInterfaceName(result.Device)
       ...
   }
   ```

2. **Discover RDMA character devices for IB-only devices**:
   - Read `/sys/class/infiniband/{rdma_dev}/device/infiniband_verbs/` to find uverbs device
   - Map to `/dev/infiniband/uverbs{N}` and `/dev/infiniband/rdma_cm`
   - These are the devices that NCCL needs access to

## Phase 4: NRI Hooks for RDMA-only Injection

### Problem

`RunPodSandbox()` calls `nsAttachNetdev()` to move a network interface into the pod namespace. For IB-only devices, there's no netdev to move.

### Changes in `pkg/driver/nri_hooks.go`

1. **Add IB-only branch in `RunPodSandbox()`**:

   ```go
   for _, config := range podConfigs {
       if config.IBOnly {
           // Skip nsAttachNetdev — no netdev to move
           // In shared mode: RDMA devices are already accessible from privileged pods
           // Just record the RDMA device mapping for CreateContainer()
           continue
       }
       // Existing netdev attach path (unchanged)
       nsAttachNetdev(...)
   }
   ```

2. **Add RDMA character devices in `CreateContainer()`**:

   ```go
   if config.IBOnly {
       // Add /dev/infiniband/uverbsN character device to container
       for _, charDev := range config.RDMAConfig.CharDevices {
           adj.AddDevice(&api.LinuxDevice{
               Path:  charDev.Path,
               Type:  "c",
               Major: charDev.Major,
               Minor: charDev.Minor,
           })
       }
   }
   ```

3. **Skip `nsDetachNetdev()` in `StopPodSandbox()`** for IB-only devices.

### RDMA Namespace Considerations

In `shared` RDMA netns mode (current AKS default):
- RDMA devices are visible from all network namespaces
- Moving RDMA link device via `RdmaLinkSetNsFd()` is not needed
- Pods with `privileged: true` can access `/dev/infiniband/` directly
- The DRA claim provides resource accounting (scheduler knows which NICs are allocated)

In `exclusive` RDMA netns mode (requires boot-time config):
- RDMA devices follow their associated netdev into the pod namespace
- Would need IPoIB interface to move (or kernel support for moving IB-only RDMA devices)
- Not currently supported on AKS without node-level config

**Recommendation**: Support `shared` mode first. The DRA claim ensures correct scheduling (4 NICs per node on GB300) even without namespace isolation. For NCCL, all RDMA devices are used by the single pod on each node anyway.

### Current State (Not Implemented)

Tested with `ghcr.io/anson627/dranet:test` on GB300 (2026-02-28):

- dranet NRI plugin does **not** inject `/dev/infiniband/uverbs*` character devices into pods
- `kubectl exec worker -- ls /dev/infiniband/` shows all 4 uverbs devices regardless of which NIC was allocated by DRA
- dranet logs confirm RDMA devices are discovered via sysfs (`Found RDMA device mlx5_1 for interface ibP258s... via sysfs`) but no NRI device injection is logged
- The `uverbs*` devices visible in privileged pods come from the container runtime's default device allowlist, not from dranet
- Current workaround: mount `/dev/infiniband` as hostPath, which bypasses isolation entirely

## Phase 5: PodConfig Changes

### Changes in `pkg/driver/pod_device_config.go`

```go
type PodConfig struct {
    IBOnly                       bool                    // true for IB-only devices (no netdev)
    Claim                        types.NamespacedName
    NetworkInterfaceConfigInHost *NetworkInterfaceConfig  // nil for IB-only
    NetworkInterfaceConfigInPod  *apis.NetworkConfig      // nil for IB-only
    RDMAConfig                   *RDMAConfig              // populated for both IB-only and Ethernet RDMA
}
```

## Phase 6: Build and Deploy

1. Clone fork: `git clone https://github.com/anson627/dranet`
2. Apply changes to the files listed above
3. Build: `make docker-build IMG=ghcr.io/anson627/dranet:ib-support`
4. Push: `docker push ghcr.io/anson627/dranet:ib-support`
5. Update DaemonSet: change image tag in `nvidia/dranet/daemonset.yaml`
6. Redeploy: `kubectl apply -f nvidia/dranet/`

## Phase 7: Validation

### Step 1: Verify ResourceSlice attributes

```bash
kubectl get resourceslices --field-selector=spec.driver=dra.net -o json | \
  jq '.items[0].spec.devices[] | {name, rdma: .attributes["dra.net/rdma"], ibOnly: .attributes["dra.net/ibOnly"], rdmaDevice: .attributes["dra.net/rdmaDevice"]}'
```

Expected: 4 IB-only devices per node with `ibOnly: true` and `rdmaDevice: "mlx5_X"`

### Step 2: Apply DRA resources and MPIJob

```bash
kubectl apply -f nccl/device-class.yaml
kubectl apply -f nccl/resource-claim-template.yaml
kubectl apply -f nccl/mpi-job.yaml
```

### Step 3: Verify ResourceClaim allocation

```bash
kubectl get resourceclaims -o wide
# Expected: allocated,reserved for each worker
```

### Step 4: Verify pods start without PrepareResourceClaim errors

```bash
kubectl describe pod nccl-test-dra-worker-0 | grep -A5 Events
# Expected: no FailedPrepareDynamicResources error
```

### Step 5: Run NCCL all-reduce benchmark

```bash
kubectl logs nccl-test-dra-launcher-xxxxx -f
# Expected: NCCL all_reduce_perf results with IB transport
```

### Step 6: Verify RDMA device access in pod

```bash
kubectl exec nccl-test-dra-worker-0 -- ls /dev/infiniband/
kubectl exec nccl-test-dra-worker-0 -- ibv_devinfo
```

## Summary of Changes

| File | Change | Purpose |
|------|--------|---------|
| `pkg/apis/attributes.go` | Add `AttrIBOnly`, `AttrRDMADevice` | New device attributes |
| `pkg/inventory/db.go` | IB-only detection in scan(), new methods, NUMA-based pcieRoot fallback | Discover IB devices without netdev, enable topology alignment on Azure |
| `pkg/driver/dra_hooks.go` | IB-only branch in PrepareResourceClaim | Skip netdev lookup, gather RDMA info |
| `pkg/driver/nri_hooks.go` | IB-only branch in RunPodSandbox/CreateContainer | Skip netdev move, add char devices |
| `pkg/driver/pod_device_config.go` | Add `IBOnly` field to PodConfig | Distinguish IB-only vs Ethernet paths |
| `nvidia/dranet/daemonset.yaml` | Update image tag | Deploy new build |

## References

- [NVIDIA/k8s-dra-driver-gpu#213](https://github.com/NVIDIA/k8s-dra-driver-gpu/issues/213) — Topological alignment between GPUs and NICs
- [NVIDIA/k8s-dra-driver-gpu#429](https://github.com/NVIDIA/k8s-dra-driver-gpu/pull/429) — pcieRoot attribute implementation
- [NVIDIA/k8s-dra-driver-gpu#575](https://github.com/NVIDIA/k8s-dra-driver-gpu/issues/575) — pcieRoot crash on Azure VMBUS paths
- [NVIDIA/k8s-dra-driver-gpu#577](https://github.com/NVIDIA/k8s-dra-driver-gpu/pull/577) — Graceful handling when pcieRoot resolution fails
- [Linux pci-hyperv.c](https://github.com/torvalds/linux/blob/master/drivers/pci/controller/pci-hyperv.c) — Hyper-V PCI controller creates flat topology (no intermediate PCIe bridges in guest)

## Validation Results (GB300, 2026-02-28)

### NCCL all_reduce_perf (2 nodes × 1 GPU × 1 NIC, DRA-allocated)

| Message Size | algbw | busbw | Notes |
|---|---|---|---|
| 512 MB | 110.91 GB/s | 110.91 GB/s | busbw = algbw for n=2 |
| 8 GB | 112.94 GB/s | 112.94 GB/s | ~900 Gb/s, matches 800 Gb/s NIC spec |

Transport: `NET/IBext_v11/{0,1}/GDRDMA` (nvidia-peermem GDR, `NCCL_IB_DATA_DIRECT=0`)

DRA allocation correctly selected:
- GPU: `gpu-0` (pciBusID `0008:06:00.0`) on both nodes
- NIC: `pci-0101-00-00-0` (pciAddress `0101:00:00.0`) on both nodes

### DRA CEL Selector Findings

`device.attributes` is a **two-level map**: `device.attributes[domain][id]`. The `/` in attribute names splits domain from id:

```cel
# Correct:
device.attributes["resource.kubernetes.io"]["pciBusID"] == "0008:06:00.0"
device.attributes["dra.net"]["pciAddress"] == "0101:00:00.0"
device.attributes["gpu.nvidia.com"]["type"] == "gpu"  # bare attributes use driver name as domain

# Wrong (runtime error "no such key: string"):
device.attributes["resource.kubernetes.io/pciBusID"].string == "0008:06:00.0"
device.attributes["resource.kubernetes.io/pciBusID"]["string"] == "0008:06:00.0"
```

## What Is Missing

### Phase 1: IB-only device discovery — NOT IMPLEMENTED

Current dranet publishes NIC devices as IPoIB interfaces (with `dra.net/ifName`, `dra.net/type: ipoib`). The `dra.net/ibOnly` and `dra.net/rdmaDevice` attributes are absent from the ResourceSlice. The NIC devices on GB300 have no netdev interface — the IPoIB interfaces in the current ResourceSlice are the IPoIB network interfaces, not the raw IB verbs devices (`mlx5_0`–`mlx5_3`).

**Impact**: Cannot select IB verbs devices by `dra.net/ibOnly == true`. Current workaround: select by `dra.net/pciAddress`.

### Phase 3: PrepareResourceClaim RDMA-only path — NOT IMPLEMENTED

Current dranet uses the IPoIB interface path for all devices. There is no IB-only branch that skips `GetNetInterfaceName()` and resolves RDMA character devices instead.

**Impact**: If IB-only devices were published in the ResourceSlice, `PrepareResourceClaim` would fail. Currently masked because IPoIB interfaces are published instead.

### Phase 4: NRI character device injection — NOT IMPLEMENTED

The NRI plugin does not inject `/dev/infiniband/uverbs*` into pods when a NIC is allocated via DRA. All 4 uverbs devices are visible inside privileged pods regardless of the DRA allocation, providing no isolation.

**Impact**: No `/dev/infiniband` isolation. All pods on a node can access all 4 IB devices. Current workaround: mount `/dev/infiniband` as a hostPath volume (bypasses DRA isolation entirely).

### Phase 5: PodConfig IBOnly flag — NOT IMPLEMENTED

Depends on Phases 1 and 3.

### NIC pcieRoot not published

dranet fails to resolve pcieRoot for NIC devices because Azure VMBUS paths don't start with `/sys/devices/pci*`. The `resource.kubernetes.io/pcieRoot` attribute is absent from NIC ResourceSlice entries. GPU pcieRoot resolves correctly via NVIDIA PCI bridges.

**Impact**: Cannot use `matchAttribute: resource.kubernetes.io/pcieRoot` constraint to enforce GPU-NIC NUMA alignment in DRA. Current workaround: manually specify GPU and NIC by PCI address in CEL selectors.

## Action Items

- [ ] Implement IB-only device discovery in dranet `db.go` (Phase 1)
- [ ] Implement RDMA character device discovery in `dra_hooks.go` (Phase 3)
- [ ] Implement NRI character device injection in `nri_hooks.go` (Phase 4)
- [ ] Implement PodConfig IBOnly flag in `pod_device_config.go` (Phase 5)
- [ ] Fix NIC pcieRoot resolution for Azure VMBUS paths in dranet `sysfs.go` so `matchAttribute: resource.kubernetes.io/pcieRoot` can be used for GPU-NIC alignment
- [ ] Implement NUMA-based pcieRoot fallback in dranet `sysfs.go` (Phase 2) — GPU driver resolves correctly via NVIDIA PCI bridges (`pci0008:00` etc.), but dranet NIC pcieRoot fails with VMBUS path error and publishes nothing; NUMA fallback (`numa-0`/`numa-1`) is not yet in `dranet:test`
- [x] Investigate guest kernel PCIe topology on Hyper-V — confirmed flat topology, no parent bridge bus IDs available (`pci-hyperv.c` analysis)
- [x] Validate NCCL DRA end-to-end on GB300 — working at ~113 GB/s per GPU pair via IBext nvidia-peermem GDR
- [x] Determine correct DRA CEL selector syntax — `device.attributes[domain][id]` two-level map
- [ ] Validate GB300 NCCL performance with/without topo.xml to determine if `nvidia-smi topo` provides sufficient topology info
- [ ] Test end-to-end IB-only device isolation once Phases 1, 3-5 are implemented
