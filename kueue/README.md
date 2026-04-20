# Kueue

Kubernetes-native job queueing for batch / AI workloads. Kueue decides **when** a job
runs (admission, quota, preemption, locality) and leaves **how** it runs to existing
controllers (`Job`, `RayJob`, `MPIJob`, `JobSet`).

## Object Hierarchy

```
Cohort               (cluster-scoped, optional)        ← quota-sharing pool
└── ClusterQueue     (cluster-scoped, 1..N per cohort) ← quota matrix + admission policy
    └── LocalQueue   (namespaced,    1..N per CQ)      ← per-namespace handle (RBAC boundary)
        └── Job / RayJob / MPIJob / ...                ← actual workloads
```

| Object          | Scope        | Holds quota? | Required? |
|-----------------|--------------|--------------|-----------|
| `Cohort`        | cluster      | no           | optional — enables borrowing/lending across CQs |
| `ClusterQueue`  | cluster      | **yes**      | required |
| `ResourceFlavor`| cluster      | no (just labels/taints/topology) | required |
| `LocalQueue`    | namespace    | no           | required — Jobs reference it by label |
| `Topology`      | cluster      | no           | optional — enables Topology-Aware Scheduling |

## Admission Flow

1. Job submitted with `suspend: true` and label
   `kueue.x-k8s.io/queue-name: <local-queue-name>` (see `sample-job.yaml`).
2. Kueue creates a `Workload` and refuses to unsuspend until quota is granted.
3. `LocalQueue` routes the workload to its `ClusterQueue`.
4. `ClusterQueue` walks `resourceGroups[].flavors` **in order**:
   - Filter by node compatibility (flavor `nodeLabels` / `nodeTaints` must match).
   - Quota check: `usage + request ≤ nominalQuota` (or `+ borrowable` from cohort).
   - Apply `flavorFungibility` policy (borrow vs spill, preempt vs spill).
5. If the chosen flavor has `topologyName`, TAS picks a specific subtree of nodes.
6. Kueue patches pods with the flavor's `nodeLabels` / `tolerations` and unsuspends
   the Job. The kube-scheduler then places pods normally.

## ResourceFlavor — "kind of capacity"

A flavor is a **stencil**, not a quantity. It says how to land a pod on the right
hardware:

```yaml
spec:
  nodeLabels:   { accelerator: h100 }   # injected as nodeSelector
  nodeTaints:   [...]                   # matching tolerations injected
  topologyName: gpu-topology            # opt-in to TAS for this flavor
```

Typical flavors: `h100-on-demand`, `h100-spot`, `a100`, `cpu-only`, `arm64`,
`reserved-team-a` (taint-gated).

## ClusterQueue — quota per (resource × flavor)

Quota lives in a **rectangular matrix** inside `resourceGroups`:

```yaml
resourceGroups:
- coveredResources: [cpu, memory, "nvidia.com/gpu"]
  flavors:
  - name: h100-on-demand
    resources:
    - { name: "nvidia.com/gpu", nominalQuota: "64",  borrowingLimit: "32", lendingLimit: "16" }
    - { name: cpu,              nominalQuota: "2000" }
    - { name: memory,           nominalQuota: "16Ti" }
  - name: h100-spot
    resources:
    - { name: "nvidia.com/gpu", nominalQuota: "256", borrowingLimit: "0" }
    - { name: cpu,              nominalQuota: "4000" }
    - { name: memory,           nominalQuota: "32Ti" }
```

Rules:
- Every flavor in a group must cover every resource in `coveredResources`.
- A resource appears in exactly **one** resourceGroup per CQ.
- Flavor **order matters** — Kueue tries them top-to-bottom.
- `nominalQuota` = guaranteed; `borrowingLimit` = max extra borrowable from cohort
  siblings; `lendingLimit` = max of nominal you'll let others borrow.

## Flavor Fungibility — "what to do when full?"

Fungibility = treat flavors as interchangeable. Two knobs:

```yaml
flavorFungibility:
  whenCanBorrow:  Borrow | TryNextFlavor   # current flavor has cohort-borrowable quota
  whenCanPreempt: Preempt | TryNextFlavor  # current flavor needs preemption to fit
```

| Setting              | Behavior                                                              |
|----------------------|-----------------------------------------------------------------------|
| `Borrow`             | Loyal to flavor order — borrow from cohort within the current flavor. |
| `Preempt`            | Loyal to flavor order — evict lower-priority workloads in this flavor.|
| `TryNextFlavor`      | Spill to the next flavor first; only borrow/preempt as last resort.   |

GPU example with flavors `[h100-on-demand, h100-spot, a100]`:

| Situation                              | Default (`Borrow`/`Preempt`)         | `TryNextFlavor`                              |
|----------------------------------------|--------------------------------------|----------------------------------------------|
| H100-on-demand has free nominal quota  | Admit on H100-on-demand              | Admit on H100-on-demand                      |
| H100-on-demand full, cohort lendable   | **Borrow** within H100-on-demand     | Skip → try H100-spot, then A100              |
| H100-on-demand full, lower-prio there  | **Preempt** in H100-on-demand        | Skip → try H100-spot, then A100              |

Fungibility runs **after** node-compatibility filtering, so a pod pinned via
`nodeSelector: accelerator=h100` is never spilled to A100 regardless of policy.

## Cohort — borrowing pool

A `Cohort` groups ClusterQueues so idle quota in CQ-A can be lent to CQ-B (up to
`borrowingLimit`) and reclaimed via preemption (`reclaimWithinCohort`). Cohort is
optional; without it a CQ runs standalone with no borrowing. Newer Kueue supports
**nested cohorts** (`spec.parent`) for hierarchical fair-share.

## LocalQueue — namespaced handle

Intentionally thin: just `spec.clusterQueue`. Required because Jobs reference it
by label; cannot point directly at a ClusterQueue.

Optional capabilities (newer versions):
- `spec.fairSharing.weight` — per-namespace fair-share weight inside one CQ.
- `spec.stopPolicy: Hold | HoldAndDrain` — pause admission for one namespace.
- `admissionChecksStrategy` — gate this LQ on external checks
  (ProvisioningRequest, MultiKueue dispatch, etc.) without touching the CQ.
- Status surface (`pendingWorkloads`, `admittedWorkloads`, `flavorUsage`) gives
  tenants per-namespace visibility without cluster-scoped read on CQ.

## Topology-Aware Scheduling (TAS)

Models the physical fabric as a **tree of node labels**. Coarsest level on top,
narrowest on the bottom (each leaf = one node):

```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: Topology
metadata: { name: gpu-topology }
spec:
  levels:
  - nodeLabel: topology.example.com/block   # cross-rack, RDMA / InfiniBand
  - nodeLabel: topology.example.com/rack    # intra-rack, NVLink / NVSwitch
  - nodeLabel: kubernetes.io/hostname       # single node (NVSwitch-internal)
```

Bind it to a flavor via `ResourceFlavor.spec.topologyName`. Workloads then express
locality intent via **PodTemplate annotations**:

| Annotation                                                 | Semantics                                                                 |
|------------------------------------------------------------|---------------------------------------------------------------------------|
| `kueue.x-k8s.io/podset-required-topology: <level>`         | **Hard** — all pods must fit in one subtree at that level, else pending.  |
| `kueue.x-k8s.io/podset-preferred-topology: <level>`        | **Soft** — try the tightest level first, walk upward if it doesn't fit.   |
| `kueue.x-k8s.io/podset-unconstrained-topology: "true"`     | No locality, just count.                                                  |

At admission Kueue searches for a subtree with enough free capacity for the
**entire PodSet** (gang semantics — no partial admission), assigns each pod to a
specific node, and injects nodeSelectors so the kube-scheduler cannot scatter them.

### Mapping to GPU fabric

| Physical fabric                     | Topology level                | Annotation                                      |
|-------------------------------------|-------------------------------|-------------------------------------------------|
| NVSwitch inside one node            | `kubernetes.io/hostname`      | `required-topology: kubernetes.io/hostname`     |
| NVLink/NVSwitch across rack         | `topology.example.com/rack`   | `required-topology: .../rack` (NCCL ring)       |
| RDMA/InfiniBand across racks        | `topology.example.com/block`  | `preferred-topology: .../rack` → spill to block |

Compose with DRA's `matchAttribute: resource.kubernetes.io/pcieRoot` for
**intra-node GPU↔NIC PCIe-root locality**; TAS handles **inter-node** rack/block
locality.

## Files in this directory

| File                  | Purpose                                                                 |
|-----------------------|-------------------------------------------------------------------------|
| `cohort.yaml`         | Empty `kwok-cohort` — enables borrowing across future sibling CQs.      |
| `cluster-queue.yaml`  | `kwok-cluster-queue` with cpu/memory quota, `BestEffortFIFO`, fungibility `Borrow` / `TryNextFlavor`. |
| `resource-flavor.yaml`| `kwok-resource-flavor` selecting `type: kwok` nodes, bound to topology. |
| `topology.yaml`       | `kwok-topology` with a single trivial level (`nodeLabel: type`).        |
| `local-queue.yaml`    | `kwok-local-queue` in `default` namespace → `kwok-cluster-queue`.       |
| `sample-job.yaml`     | Demo Job with `suspend: true` and the required queue-name label.        |

## Apply

```bash
kubectl apply -f .
kubectl -n default get workloads,localqueues
kubectl get clusterqueues,cohorts
```
