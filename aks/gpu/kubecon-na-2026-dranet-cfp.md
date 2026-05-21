# KubeCon + CloudNativeCon North America 2026 — DRANET Talk Proposal

**Event:** KubeCon + CloudNativeCon North America 2026
**Dates:** November 9–12, 2026, Salt Lake City
**CFP Deadline:** May 31, 2026 (11:59pm MT)
**CFP URL:** https://events.linuxfoundation.org/kubecon-cloudnativecon-north-america/program/cfp/

---

## 1. Outreach Email to Co-Speaker

> Draft for reaching out to **Gaurav Ghildiyal** (`@gauravkghildiyal`) or **Antonio Ojea** (`@aojea`) at Google as a co-speaker.

**To:** gauravkghildiyal@google.com *(or aojea@google.com)*
**Cc:** *(optional — Michael Zappa, msft teammates)*
**Subject:** KubeCon NA 2026 — co-speak on DRANET? (CFP closes May 31)

Hi Gaurav *(/ Antonio)*,

Hope you're doing well! Following our collaboration on [kubernetes-sigs/dranet](https://github.com/kubernetes-sigs/dranet) over the past several months, I'd love to propose a joint talk at **KubeCon + CloudNativeCon NA 2026** (Nov 9–12, Salt Lake City) with you as co-speaker — one voice from Google, one from Azure.

The pitch — incorporating your feedback and Gaurav's on metrics: **"How to make your AI stack cloud-neutral."** Lead with the end-user problem (scarce accelerators + a fragmented RDMA landscape that breaks portability across clouds), position DRANET as the unification layer, and only *then* go into the juicy bits — the cloud-provider driver interface, DRA + NRI hooks, the scheduling magic. KubeCon audiences respond to "solves my problem" much better than "here's how the project works," so this framing should land harder than a pure architecture walkthrough.

On metrics: alongside MFU for training, I'm leaning on **KV-cache transfer latency** (avg + p50/p95/p99) for the inference side — that's what our NIXL benchmark measures directly, and it's what inference platform teams running disaggregated prefill/decode actually budget against.

A few anchors we could build on:
- **The portability story:** today, moving a training job or a disaggregated inference deployment between clouds means rewriting the network plumbing — InfiniBand on one cluster, RoCE on another, and even RoCE-on-AWS ≠ RoCE-on-Azure ≠ RoCE-on-GCP in terms of CNI hooks and device-plugin glue. DRANET's `DeviceClass` + per-cloud driver model lets the *same* `ResourceClaimTemplate` ("4 GPUs + 4 NUMA-aligned RDMA NICs") land identically on AKS, GKE, and EKS.
- **The recent AKS blog post**, [*DRANET: Topology-Aware RDMA Optimization for AI on AKS*](https://blog.aks.azure.com/2026/04/01/dranet-rdma-optimization-for-ai-on-aks), which shows **2.2×–4.5× NCCL bandwidth improvements** on ND GB300-v6 via topology-aware GPU+NIC co-scheduling.
- New end-to-end results from the upstream [`dranet/examples`](https://github.com/kubernetes-sigs/dranet/tree/main/examples) on 2 × H100 nodes — same YAML, only the NIC NUMA selector changes:
  - **Distributed training:** BF16 PyTorch DDP MFU goes from **32.83% → 36.06%** (a **~10% relative MFU lift**, ~9% faster step time).
  - **Disaggregated inference:** 1 GiB GPU→GPU KV-cache handoff drops from **38.99 ms → 27.49 ms** (**29.5% lower KV-transfer latency, 1.42× bandwidth**, p99 39.13 ms → 27.50 ms) — the exact prefill→decode transfer path on the inference critical path.
- Your experience on the upstream DRA side and the SIG-Network direction.

I've drafted a session proposal (title, abstract, benefits-to-ecosystem, outline) — attached / below. Happy to revise based on your angle, or pivot to a panel / tutorial format if you'd prefer.

**Ask:** could you let me know by **~May 24** if you're up for co-speaking? That leaves a week of buffer before the **May 31** CFP deadline. Speakers can submit up to three sessions, so this wouldn't lock you out of other proposals.

Either way, thank you for the partnership on DRANET — the project has come a long way because of it.

Best,
Anson Qian
Software Engineer, Azure Kubernetes Service (AKS)
Microsoft

---

## 2. CFP Submission Draft

### Track (primary)
**AI Inference + Agentic** — with **Connectivity** as a strong secondary fit.

### Session Format
**Session Presentation — 30 minutes, 2 speakers**

### Title *(≤ ~100 chars, inclusive-language compliant)*
**Make Your AI Stack Cloud-Neutral: Portable RDMA Scheduling with DRANET on Kubernetes**

*Alternate titles:*
- *One YAML, Every Cloud: DRANET for Portable Distributed Training and Disaggregated Inference*
- *Stop Rewriting RDMA Plumbing per Cloud: DRANET, MFU, and KV-Transfer Latency in One ResourceClaimTemplate*
- *Cloud-Neutral AI Infrastructure: How DRANET Unifies InfiniBand and RoCE Behind a Single DRA API*

### Speakers
- **Anson Qian**, Software Engineer, Azure Kubernetes Service — Microsoft
- **Gaurav Ghildiyal** *(or Antonio Ojea)*, Software Engineer — Google

### Session Description *(abstract)*

Accelerators are scarce, expensive, and never in the cloud you want them in. So teams hedge — train on one provider, serve on another, burst across regions when the quota arrives. And every time they do, they hit the same wall: **the network underneath AI workloads is wildly unportable.** InfiniBand on one cluster, RoCE on another, and even "RoCE" means a different stack of NICs, CNIs, device plugins, and privileged pods on AKS than on GKE than on EKS. The result: rewritten YAML per cloud, brittle per-cluster tuning, lost weeks, and lost MFU.

This talk is about how to **make your AI stack cloud-neutral** — by treating RDMA the way Kubernetes treats CPUs and memory: as a scheduled, declared, portable resource. Engineers from **Google** and **Microsoft**, collaborators on the `kubernetes-sigs/dranet` SIG project, will show how a single `ResourceClaimTemplate` — *"give me 4 GPUs and 4 NUMA-aligned RDMA NICs"* — schedules identically on AKS, GKE, and EKS, with each cloud's DRA driver doing the provider-specific work behind a shared interface.

**What you'll see:**

1. **The portability problem, in user terms.** Why moving a distributed training job or a disaggregated inference deployment between clouds is currently a multi-week porting exercise, and which parts of that pain are accidental vs. fundamental.
2. **The unification: one YAML, every cloud.** A single declarative claim that lands on InfiniBand on Azure and RoCE on Google — same scheduler decisions, same topology guarantees, no privileged sidecars.
3. **Visibility in the metrics users already speak.** Not `ib_write_bw`, but the numbers on your dashboard:
   - **Distributed training MFU** — **32.83% → 36.06%** (~10% relative lift, ~9% faster step) on 2 × H100 by flipping one NIC selector, from the upstream `examples/distributed_training` benchmark.
   - **Inference KV-cache transfer latency** — measured via NIXL on the prefill→decode critical path: 1 GiB GPU→GPU handoff drops from **38.99 ms → 27.49 ms** (29.5% lower latency, 1.42× bandwidth, p99 39.13 ms → 27.50 ms), from `examples/nixl-kv-transfer`.
   - **NCCL collectives** — 2.2×–4.5× bandwidth on ND GB300-v6 for teams that still need the underlying number.
4. **The juicy details, finally.** The DRANET cloud-provider interface (so each cloud implements its own logic behind one DeviceClass), how DRA + NRI hooks inject only the allocated `/dev/infiniband` devices, and the scheduling constraints that keep GPUs and NICs on the same NUMA node without privileged containers or a custom CNI.
5. **Getting to production.** What's stable, what's beta, known gaps (multi-tenancy, heterogeneous fleets, GPU NUMA attribute publishing), and how to contribute upstream.

Attendees will leave with a concrete answer to *"can I run the same AI workload on any cloud without rewriting plumbing?"*, copy-pasteable `ResourceClaimTemplate`s for both training and inference, a benchmark methodology that ties NIC placement to MFU and KV-cache transfer latency, and honest guidance on when DRANET is — and isn't — the right answer.

### Benefits to the Ecosystem

- **Directly attacks the #1 pain operators report with AI infrastructure:** workload portability across clouds. Every team running distributed training or disaggregated inference is hedging across multiple providers, and the RDMA layer is where that strategy currently breaks.
- **Translates DRA into the language users already speak** — MFU for training, KV-cache transfer latency (avg + p50/p95/p99) for disaggregated inference — instead of `ib_write_bw` numbers that don't map to a training bill or a serving SLO.
- **Lowers the adoption barrier** for a young SIG project by replacing folklore with a precise, demo-driven mental model and the same YAML running on more than one cloud.
- **Bridges three audiences end-user-first:** platform teams hedging accelerators across clouds, AI/HPC training engineers tracking MFU, and inference platform teams running disaggregated prefill/decode (vLLM, NIXL). The architecture deep-dive serves the developers in the room without losing the operators.
- **Cross-vendor perspective** (Google + Microsoft) is the proof that "cloud-neutral" isn't marketing — it's a neutral, upstream-first effort with two hyperscalers already shipping drivers behind the same DeviceClass.
- **Actionable output:** working `ResourceClaimTemplate`s for both training and inference, an MFU benchmark and a NIXL KV-cache transfer benchmark (both reproducible from `kubernetes-sigs/dranet/examples`), and a migration path from privileged/device-plugin approaches.
- **Feeds back into SIG-Network and WG-Device-Management** by surfacing real-world gaps (GPU NUMA attribute publishing, cross-driver constraint matching, cross-cloud driver-interface stability) from production AKS and GKE deployments.

### Case Study?
**Yes** — real deployment experience on Azure ND GB300-v6 and H100-v5 nodes, with three production-representative benchmark families: NCCL collectives, PyTorch DDP MFU, and NIXL KV-cache transfer.

### Relevant CNCF Projects
- Kubernetes (graduated) — DRA, scheduler, kubelet, NRI
- kubernetes-sigs/dranet (sandbox-adjacent, SIG project)
- Related: containerd, CNI, device-plugin ecosystem

### Prior Presentation Disclosure
This material has **not** been presented before. It builds on — but substantially extends — the April 2026 AKS blog post [*DRANET: Topology-Aware RDMA Optimization for AI on AKS*](https://blog.aks.azure.com/2026/04/01/dranet-rdma-optimization-for-ai-on-aks), adding the upstream/Google perspective, a live architectural walkthrough, and updated benchmarks.

### Outline (30 min) — *Problem → Solution → Proof → Juicy Details*

| Time | Section | Who |
|------|---------|-----|
| 0:00–0:04 | **The problem:** scarce accelerators + a fragmented RDMA landscape (IB vs RoCE vs each cloud's RoCE) makes AI workloads unportable | Anson |
| 0:04–0:08 | **The solution:** make your AI stack cloud-neutral — one `ResourceClaimTemplate`, every cloud, with metrics ops teams already track | Google co-speaker |
| 0:08–0:12 | **Live demo:** same YAML applied on AKS (InfiniBand) and GKE (RoCE) — identical scheduling, identical `/dev/infiniband` injection | Both |
| 0:12–0:15 | **Training result in user metrics:** PyTorch DDP MFU on 2 × H100, NIC-aligned vs cross-NUMA (**32.83% → 36.06%**) | Anson |
| 0:15–0:18 | **Inference result in user metrics:** NIXL **KV-cache transfer latency** on the prefill→decode path (**38.99 ms → 27.49 ms**, p99 included) | Anson |
| 0:18–0:20 | NCCL bandwidth context: 2.2×–4.5× on ND GB300-v6 — the underlying lever behind both wins | Anson |
| 0:20–0:26 | **The juicy details:** the DRANET cloud-provider driver interface, DRA + NRI hooks, GPU↔NIC scheduling constraints | Google co-speaker |
| 0:26–0:29 | Gaps, roadmap, how to contribute (multi-tenancy, GPU NUMA attrs, heterogeneous fleets, driver-interface stability) | Both |
| 0:29–0:30 | Q&A pointer + links to `examples/distributed_training` and `examples/nixl-kv-transfer` | Both |

### Speaker Bios

**Anson Qian** is a Software Engineer on the Azure Kubernetes Service (AKS) team at Microsoft, focused on Kubernetes networking and AI infrastructure. He co-authored the AKS engineering blog post on DRANET and contributes to `kubernetes-sigs/dranet`, working on RDMA device discovery, topology-aware scheduling, and the upstream distributed-training-MFU and NIXL KV-transfer benchmark examples for distributed training and disaggregated inference on AKS.

**Gaurav Ghildiyal** *(or Antonio Ojea)* is a Software Engineer at Google working on Kubernetes networking. A maintainer-level contributor to `kubernetes-sigs/dranet` and active in SIG-Network, *(he/they)* focuses on upstream DRA-for-networking design and its integration with GKE's AI infrastructure.

### Speaker Video / Audio Sample
*(Attach a previous talk link or record a 2–3 min Loom: apply the **same** `h100-4gpu-4nic-numa-aligned` `ResourceClaimTemplate` on both an AKS and a GKE cluster — show identical scheduling decisions and identical `/dev/infiniband` injection. Then on AKS, flip to `h100-4gpu-4nic-numa-unaligned` to show the MFU launcher print `mfu_percent=36.06` vs `32.83` and the NIXL initiator print `avg_GBps=39.07` vs `27.54` — same YAML, different cloud, then same cloud, one selector flip.)*

---

## 3. Pre-Submission Checklist

- [ ] Co-speaker (Gaurav or Antonio) confirmed by **May 24, 2026**
- [ ] Title finalized (≤ ~100 chars, inclusive language)
- [ ] Abstract trimmed/tightened to Sched's word limit
- [ ] Benefits-to-ecosystem paragraph reviewed by co-speaker
- [ ] Speaker bios (≤ 400 chars each typical) and headshots uploaded
- [ ] Speaker sample video/audio link attached
- [ ] Case study box checked **Yes**
- [ ] Relevant CNCF projects list filled (Kubernetes, dranet)
- [ ] Submitted via Sched before **May 31, 2026, 11:59pm MT**
- [ ] Internal approvals: manager + Microsoft Open Source Programs Office (if required)
- [ ] Consider a second submission as a **75-min Tutorial** (hands-on deploy) or **Lightning Talk** for broader reach (max 3 per speaker)
