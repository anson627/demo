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

The pitch: **demystify DRANET and accelerate adoption.** DRA for networking is still new territory for most operators, and I think a cross-vendor talk — walking through the architecture, the scheduling model, and real numbers — is the fastest way to get the community comfortable deploying it for distributed AI workloads.

A few anchors we could build on:
- The recent AKS blog post, [*DRANET: Topology-Aware RDMA Optimization for AI on AKS*](https://blog.aks.azure.com/2026/04/01/dranet-rdma-optimization-for-ai-on-aks), which shows **2.2×–4.5× bandwidth improvements** on ND GB300-v6 nodes via topology-aware GPU+NIC co-scheduling.
- DRANET's reported **~60% throughput gains** on all-reduce / all-gather for distributed training.
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
**DRA Meets RDMA: A Cross-Vendor Walkthrough of DRANET for Distributed AI**

*Alternate titles:*
- *Demystifying DRANET: Topology-Aware RDMA Scheduling for AI Workloads on Kubernetes*
- *From 25 GB/s to 112 GB/s: How DRANET Makes RDMA Scheduling Boring*

### Speakers
- **Anson Qian**, Software Engineer, Azure Kubernetes Service — Microsoft
- **Gaurav Ghildiyal** *(or Antonio Ojea)*, Software Engineer — Google

### Session Description *(abstract)*

Distributed AI training and disaggregated inference live and die by the network. A single misaligned GPU–NIC pair — say, a GPU on NUMA 0 talking to an InfiniBand NIC on NUMA 1 — can cut all-reduce bandwidth by more than half and stall the entire training pipeline. Until recently, fixing this meant privileged pods, hand-rolled device plugins, and brittle per-cluster tuning.

**DRANET**, a Kubernetes SIG project, changes that. Built on Dynamic Resource Allocation (DRA) and NRI, DRANET discovers RDMA-capable devices, publishes them as `ResourceSlices` with topology attributes (NUMA, PCI, RDMA capability), and lets the scheduler co-place GPUs and NICs declaratively — no privileged containers, no custom CNI.

In this talk, engineers from **Google** and **Microsoft** — collaborators on `kubernetes-sigs/dranet` — will demystify the project end-to-end:

1. **The problem:** why naive scheduling wastes RDMA fabric and what "topology-aware" actually means for collective ops.
2. **The architecture:** how DRANET plugs into DRA, kubelet, and NRI; what lives where; and how it coexists with existing CNIs.
3. **A live walkthrough:** a `ResourceClaimTemplate` going from YAML to an injected `/dev/infiniband` device inside a pod.
4. **The numbers:** benchmarks on real hardware — cross-NUMA vs. same-NUMA vs. dual-NIC alignment — showing **2.2×–4.5× bandwidth gains** and ~60% improvements on all-reduce / all-gather.
5. **Getting to production:** what's stable today, what's beta, known gaps (multi-tenancy, heterogeneous fleets), and how to contribute.

Attendees will leave with a clear mental model of DRA-for-networking, a concrete deployment recipe, and honest guidance on when DRANET is — and isn't — the right answer for their AI infrastructure.

### Benefits to the Ecosystem

- **Lowers the adoption barrier** for a young SIG project that many operators have heard of but haven't deployed, by replacing folklore with a precise, demo-driven mental model.
- **Bridges two audiences:** Kubernetes platform engineers who know DRA but not RDMA, and AI/HPC engineers who know RDMA but not DRA.
- **Cross-vendor perspective** (Google + Microsoft) signals that DRA networking is a neutral, upstream-first effort — not a single-cloud pattern — which tends to drive broader adoption.
- **Actionable output:** working YAML, benchmark methodology, and a migration path from privileged/device-plugin approaches, all reusable by any cluster operator.
- **Feeds back into SIG-Network and WG-Device-Management** by surfacing real-world gaps from production AKS and GKE deployments.

### Case Study?
**Yes** — includes real deployment experience on Azure ND GB300-v6 nodes, with production-representative benchmarks.

### Relevant CNCF Projects
- Kubernetes (graduated) — DRA, scheduler, kubelet, NRI
- kubernetes-sigs/dranet (sandbox-adjacent, SIG project)
- Related: containerd, CNI, device-plugin ecosystem

### Prior Presentation Disclosure
This material has **not** been presented before. It builds on — but substantially extends — the April 2026 AKS blog post [*DRANET: Topology-Aware RDMA Optimization for AI on AKS*](https://blog.aks.azure.com/2026/04/01/dranet-rdma-optimization-for-ai-on-aks), adding the upstream/Google perspective, a live architectural walkthrough, and updated benchmarks.

### Outline (30 min)

| Time | Section | Who |
|------|---------|-----|
| 0:00–0:03 | Why RDMA scheduling is an AI problem (the 25 → 112 GB/s story) | Anson |
| 0:03–0:08 | DRA 101 + where networking fits | Google co-speaker |
| 0:08–0:15 | DRANET architecture: discovery, ResourceSlices, NRI injection | Google co-speaker |
| 0:15–0:22 | Live walkthrough: `ResourceClaimTemplate` → scheduled pod → `ibstat` | Anson |
| 0:22–0:26 | Benchmarks on ND GB300-v6: cross-NUMA vs aligned vs dual-NIC | Anson |
| 0:26–0:29 | Gaps, roadmap, how to contribute | Both |
| 0:29–0:30 | Q&A pointer + links | Both |

### Speaker Bios

**Anson Qian** is a Software Engineer on the Azure Kubernetes Service (AKS) team at Microsoft, focused on Kubernetes networking and AI infrastructure. He co-authored the AKS engineering blog post on DRANET and contributes to `kubernetes-sigs/dranet`, working on RDMA device discovery and topology-aware scheduling for distributed AI training on AKS.

**Gaurav Ghildiyal** *(or Antonio Ojea)* is a Software Engineer at Google working on Kubernetes networking. A maintainer-level contributor to `kubernetes-sigs/dranet` and active in SIG-Network, *(he/they)* focuses on upstream DRA-for-networking design and its integration with GKE's AI infrastructure.

### Speaker Video / Audio Sample
*(Attach a previous talk link or record a 2–3 min Loom demoing a `ResourceClaimTemplate` being scheduled and the resulting `/dev/infiniband` device appearing inside the pod.)*

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
