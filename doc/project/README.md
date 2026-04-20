# Project Deep-Dive

## Telescope Benchmarking and Optimization

This project is a benchmarking and optimization platform for hyperscale Kubernetes clusters running GPU- and AI-intensive workloads. Its purpose is to make cluster performance evaluation repeatable, comparable, and safe across environments while keeping the architecture portable across cloud providers, schedulers, and storage backends.

At a high level, the system follows a closed-loop workflow:

1. Provision or select target infrastructure
2. Validate readiness of the environment
3. Execute benchmark and stress scenarios
4. Collect, analyze, and persist telemetry
5. Publish results and feed recommendations back into platform tuning

The design avoids lock-in to specific implementation choices. Workflow automation is modeled as a generic workflow scheduling and execution engine rather than a specific CI/CD product, and result storage is modeled as a column-based analytics store with query, dashboarding, and visualization capabilities rather than a specific managed database.

## Design Goals

- Support repeatable benchmarking for control plane, data plane, and GPU workload scenarios
- Scale from small validation runs to extreme-scale simulations and production-like clusters
- Separate scenario intent from execution plumbing so new tests can be added with minimal orchestration changes
- Preserve portability across cloud providers and cluster implementations
- Turn raw benchmark output into operational insights, regressions, and optimization recommendations

## System Design

The platform is organized into five logical layers.

### 1. Benchmark Scenario Definition Layer

This layer describes what to test, not how to execute it.

- Benchmark scenarios define workload shape, scale targets, topology constraints, success criteria, and SLOs/SLIs
- Environment profiles describe cluster size, node mix, GPU type, region, network topology, and isolation level
- Test matrices combine scenarios with infrastructure profiles to produce repeatable experiment runs

Examples of scenario classes in this project:

- Control plane scale and scheduling throughput
- Service discovery and DNS latency
- Network throughput and RDMA-sensitive topology alignment
- GPU communication performance such as NCCL all-reduce
- Large-scale simulated clusters for scheduler and controller stress

### 2. Workflow Scheduling and Ochestration Layer

This layer coordinates the end-to-end experiment lifecycle.

- Accepts scenario definitions and execution parameters
- Schedules runs, retries failed phases, and tracks state transitions
- Fans out work across provisioning, validation, test execution, cleanup, and publishing stages
- Enforces policy gates such as readiness checks, canary progression, and rollback criteria

This replaces dependence on any single pipeline product. The key design point is that workflows are declarative and portable, while the execution engine can be implemented by any scheduler capable of orchestrating multi-step jobs.

### 3. Environment Provisioning and Validation Layer

This layer prepares the benchmark target and verifies it is safe to test.

- Provisions or attaches to Kubernetes clusters across cloud environments
- Configures node pools, accelerators, networking, storage, and supporting operators
- Applies benchmark dependencies such as drivers, schedulers, telemetry agents, and test frameworks
- Runs validation checks before benchmark execution begins

Validation is a first-class phase because large-scale test results are only meaningful when the cluster is in a known-good state. Readiness checks may include:

- Cluster health and node readiness
- GPU operator and driver health
- DNS, networking, and storage checks
- Capacity verification for scale targets
- Baseline telemetry sanity checks

### 4. Benchmark and Measurement Layer

This layer runs workload generators and gathers measurements.

- Executes benchmark engines such as cluster scalability tests, simulated-node tests, network tests, and distributed training communication tests
- Captures platform telemetry from Kubernetes, node, GPU, storage, and network surfaces
- Correlates workload events with infrastructure metrics and scenario metadata
- Normalizes measurements into a common schema for analysis

Representative benchmark families include:

- ClusterLoader2 for control plane scalability and scheduling latency
- KWOK for extreme-scale simulation
- iperf for network characterization
- NCCL-based tests for multi-GPU and multi-node communication behavior

### 5. Telemetry and Analytics Layer

This layer turns experiment output into decisions.

- Stores run metadata, metrics, logs, and derived aggregates in a column-based store optimized for analytical queries
- Supports trend analysis, regression detection, slice-and-dice comparisons, and long-term retention
- Exposes dashboards and visualizations for engineers, performance analysts, and platform operators
- Publishes benchmark summaries, reports, and optimization recommendations

This layer is intentionally generic: the essential capability is analytical storage plus visualization, not a dependency on a particular vendor database.

## Scenario Examples

Rather than a single static architecture, this platform is best understood through reusable scenario patterns. Each scenario combines the same core lifecycle with different benchmark drivers, control loops, and telemetry surfaces.

### Example 1: Job Scheduling and Control Plane Scale on Virtual GPU Nodes

This scenario combines workload scheduling with direct control-plane scale testing. A load generator submits jobs at scale, an operator reconciles them into cluster resources, and KWOK-backed virtual GPU nodes absorb the scheduling load. The goal is to measure API responsiveness, scheduling throughput, reconciliation behavior, and job lifecycle progress without requiring physical GPUs.

```text
 +-------------------+      manage cluster       +-----------------------------------+
 | workflow engine   | ------------------------> | Kubernetes Control Plane          |
 | scenario runner   |                           +-----------------------------------+
 +---------+---------+                              ^            ^
           |                                        |            |
           | deploy workload                        | create nodes| assign pods
           v                                        |            |
 +--------------------+                             |   +------------------+   +------------------+
 | clusterloader2     | -- submit test jobs ------> |   | kwok-controller  |   | virtual GPU node |
 | load generator     |                             |   | node simulator   |   | kwok-gpu-node-*  |
 +--------------------+                             |   +--------+---------+   +------------------+
                                                   |
                                                   | scrape metrics
                                                   v
                            +--------------------------------------+
                            | telemetry publisher                  |
                            | control plane benchmark data         |
                            +--------------------------------------+
                                     |
                                     | publish metrics
                                     |
                                     v
                            +------------------------------+
                            | analytics data store         |
                            | job throughput & latency     |
                            +------------------------------+
                                     |
                                     |  visualize metrics
                                     v
                            +------------------------------+
                            | dashboards and reports       |
                            | trends, SLOs, regressions    |
                            +------------------------------+
```

Key behaviors:

- Exercises control-plane scalability without physical GPU dependency
- Separates workload submission, reconciliation, scheduling, and node simulation
- Measures API responsiveness, scheduling latency, and controller throughput at scale
- Evaluates how watch behavior, cache efficiency, and concurrency settings affect performance
- Publishes benchmark output into an analytics data store and dashboard layer for trend and regression analysis

### Example 2: GPU Network and Collective Communication Performance

This scenario focuses on the data plane. It measures whether network topology, NIC-to-GPU affinity, and node placement policies are sufficient for distributed AI workloads. It combines `iperf` for inter-node TCP/UDP characterization with GPU collective benchmarks for distributed training communication behavior.

```text
 +-------------------+      submit test job       +----------------------+
 | workflow engine   | -------------------------> | Kubernetes Control   |
 | scenario runner   | -- manage cluster -------> | Plane                |
 +-------------------+                            +----------+-----------+
                                                              |
                                                              | schedule benchmark pods
                                                              v
             +--------------------------+     +--------------------------+
             | GPU node group A         | <-> | GPU node group B         |
             | GPU, NIC, RDMA resources |     | GPU, NIC, RDMA resources |
             +--------------------------+     +--------------------------+
                     ^          ^                         ^          ^
                     |          |                         |          |
                     |          | iperf TCP/UDP traffic   |          |
                     |          +-------------------------+          |
                     |                                               |
                     |        NCCL / collective traffic              |
                     +-----------------------------------------------+
                                       |
                                       | scrape metrics
                                       v
                            +------------------------------+
                            | telemetry publisher          |
                            | network + GPU benchmark data |
                            +------------------------------+
                                       |
                                       | publish metrics
                                       v
                            +------------------------------+
                            | analytics data store         |
                            | throughput, latency, errors, |
                            +------------------------------+
                                       |
                                       | visualize metrics
                                       v
                            +------------------------------+
                            | dashboards and reports       |
                            | TCP/UDP trends, placement,   |
                            | topology impact              |
                            +------------------------------+
```

Key behaviors:

- Measures inter-node TCP/UDP throughput, latency, and collective communication efficiency
- Reveals the impact of topology-aware scheduling and NUMA or PCIe locality
- Distinguishes general network bottlenecks from GPU collective communication bottlenecks
- Connects infrastructure placement decisions to distributed training performance

## Reusable Platform Components

The project can be understood as three reusable components:

1. Infrastructure modules: provision and configure benchmark targets in a cloud-agnostic way
2. Workflow templates: define reusable orchestration patterns for setup, validation, run, cleanup, and publish
3. Execution modules: integrate with benchmark tools and test frameworks

This separation allows the same platform to support many benchmark types without tightly coupling scenario logic to infrastructure or analytics tooling.

## Why This Architecture Works

- It scales operationally because provisioning, validation, execution, and publishing are independently evolvable
- It scales analytically because results are stored in a query-friendly format suitable for longitudinal analysis
- It scales organizationally because new scenarios can be added without redesigning the system
- It remains portable because core responsibilities are defined by capability, not vendor product

In short, this project is best viewed not as a collection of scripts, but as a portable performance engineering system for AI-scale Kubernetes infrastructure.
