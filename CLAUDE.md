# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kubernetes GPU/AI infrastructure toolkit for provisioning, benchmarking, and scale-testing clusters across Azure AKS, AWS EKS, and Google GKE. Focus areas: Dynamic Resource Allocation (DRA) for GPUs, scheduling throughput at 100K+ node scale, and LLM training infrastructure.

## Architecture

| Directory | Role |
|-----------|------|
| `aks/flex/` | AKS cluster with custom CNI/ipvlan and VirtualMachines VM set type |
| `aks/gpu/` | AKS GPU nodes with NVIDIA DRA driver (`resource.k8s.io/v1beta1`) |
| `aks/scale/` | Extreme-scale AKS (50K+ nodes) with custom OS images |
| `eks/`, `gke/` | Minimal EKS/GKE cluster provisioning |
| `cl2/` | ClusterLoader2 performance benchmarks (job scheduling throughput, pod startup latency) |
| `kwok/` | KWOK simulated clusters (10K fake nodes + fake GPU ResourceSlices) |
| `ray/` | KubeRay operator deployment and PyTorch MNIST RayJob benchmarks on KWOK |
| `aks/gpu/nccl/` | MPIJob manifests for NCCL all-reduce benchmarks (A100, H100 GPUs) |
| `kueue/` | Kueue fair-share job scheduling configs (ClusterQueue, Topology, Cohort) |
| `doc/` | Technical articles and Mermaid architecture diagrams |

Cross-directory dependency: `ray/run.sh` sources `../cl2/wait-for-jobs.sh`.

## Commands

```bash
# KWOK scale test (primary workflow)
kwok/init.sh          # Create KWOK simulated cluster
kwok/run.sh           # Create 10K fake nodes + resource slices
cl2/run.sh            # Execute ClusterLoader2 benchmark
cl2/clean.sh          # Clean test namespaces
kwok/clean.sh         # Tear down KWOK cluster

# AKS GPU cluster (run in order)
cd aks/gpu && source variables.sh
bash cluster.sh       # Provision AKS cluster + GPU node pool
bash nvidia.sh        # Deploy NVIDIA Operator stack + DRA driver + dranet
bash nccl.sh          # Deploy MPI operator + NCCL all-reduce benchmark
bash cleanup.sh       # Destroy resource group

# Ray on KWOK (requires local KubeRay fork at $HOME/go/src/github.com/anson627/kuberay)
ray/init.sh           # Deploy KubeRay operator
ray/run.sh            # Submit RayJob + wait

# Kueue (apply all manifests)
kubectl apply -f kueue/

# EKS / GKE
eks/setup.sh / eks/teardown.sh
gke/setup.sh / gke/teardown.sh
```

## Key Tools & Dependencies

`az`, `gcloud`, `eksctl`, `kubectl`, `helm`, `kwokctl` (v0.7.0), `clusterloader2`, `envsubst`, `jq`. Custom fork image: `ghcr.io/anson627/kuberay/operator:v1.4.2` (KubeRay).

NVIDIA operator component versions (pinned in `nvidia.sh`): Network Operator `25.10.0`, GPU Operator `v25.10.1`, DRA Driver `25.12.0`.

`ray/init.sh` installs from the local KubeRay Helm chart at `$HOME/go/src/github.com/anson627/kuberay/helm-chart/kuberay-operator` — this path must exist.

## ClusterLoader2 Benchmark Parameters

`cl2/overrides.yaml` sets the active scale-test parameters (edit here to change test load):
- `CL2_JOBS: 100000`, `CL2_NAMESPACES: 10`, `CL2_LOAD_TEST_THROUGHPUT: 700`
- `CL2_JOB_GPU: 8`, `CL2_JOB_TEMPLATE_PATH: dra/job_template.yaml`, `CL2_ENABLE_RESOURCE_CLAIMS: true`

`cl2/config.yaml` accepts these as Go template overrides. Swap `CL2_JOB_TEMPLATE_PATH` to `base/job_template.yaml` or `gpu/job_template.yaml` for non-DRA runs.

## AKS GPU VM Sizes

`aks/gpu/variables.sh` contains commented-out alternatives for each GPU generation — uncomment the desired block before running:
- A100: `eastus` / `Standard_ND96asr_v4`
- H100: `swedencentral` / `standard_nd96isrf_h100_v5` (active default)
- H200: `eastus2euap` / `Standard_ND96isr_H200_v5`
- GB200: `centraluseuap` / `Standard_ND128isr_NDR_GB200_v6`
- GB300: `eastus2euap` / `Standard_ND128isr_GB300_v6`

## Shell Script Conventions

- Shebang: `#!/bin/bash` with `set -eo pipefail` (use `set -euo pipefail` for new scripts)
- Load config via `source variables.sh` at script top — each scenario has its own `variables.sh`
- Variable style: `${VARIABLE}` with braces; quote variables in new code (`"${VARIABLE}"`)
- Idempotent resource creation: check existence before creating (e.g., `az resource show ... &>/dev/null`)
- Template expansion: `envsubst < template.yaml > output.yaml` — no Helm, no Kustomize
- Scripts are linear and procedural — no shared utility libraries
- Preserve alternative configs as comments rather than parameterizing

## Kubernetes YAML Conventions

- Uses cutting-edge APIs: `resource.k8s.io/v1beta1`, `resource.k8s.io/v1`, `kueue.x-k8s.io/v1beta1`, `ray.io/v1` (Kubernetes 1.33–1.34)
- KWOK workloads must include `nodeSelector: { type: kwok }` and toleration for `kwok.x-k8s.io/node=fake:NoSchedule`
- ClusterLoader2 templates use Go template syntax: `{{.Name}}`, `{{.Group}}`, `{{.JobGPU}}`
- KWOK/envsubst templates use `${VARIABLE}` placeholders
- Namespaces: `kube-system` for infra, `default` for test workloads, `gpu-operator` for NVIDIA components (namespace is `nvidia`)
- DRA resource hierarchy: `DeviceClass` → `ResourceClaimTemplate` → pod `resourceClaims` → allocated `ResourceClaim`
- GPU+NIC co-scheduling uses `matchAttribute: resource.kubernetes.io/pcieRoot` constraint to enforce NUMA locality

## Security Notes

- Debug pods and DRA DaemonSets use `privileged: true`, `hostNetwork`, `hostPID` — expected for GPU/NRI workloads
- Variables files may contain real subscription IDs — do not commit credentials
