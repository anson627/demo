# Story

## Principal
* strong signals (green flags):
  * Extreme Ownership: Candidate owns not only success but also failure. For example they identified a gap in delivery, took responsibility to fix it without being asked.
  * Data-Driven Results: Candidate defined success with measurable metrics (10% latency reduction, 50k USD saved). This shows candidate understands the business impact of their work.
  * Bias for Action: Candidate can show how they moved a project forward despite missing data or vague requirements. When speed is critical, they can deliver and refine later.
  * Deep Customer Obsession: Candidate frames technical decisions around the end-user's experience rather than technical vanity or personal preference.
  * High Coachability: Candidate describes past feedback they received, importantly: the specific steps they took to improve based on the feedback, ideally with examples after they succeed.
* weak signals (red flags):
  * Ambiguous Contribution: Overusing "we" instead of "I." If the interviewer can't pinpoint candidate’s specific role in a success.
  * Over-Engineering: Choosing complex, expensive solutions for simple problems just to use a specific tool. This suggests a lack of business sense.
  * Vague Success Metrics: Using words like "improved," "streamlined," or "helped" without providing a scale or a baseline for comparison.
  * Lack of Self-Awareness: Being unable to name a genuine professional weakness or a time candidate failed. Candidate needs to show they have ability to grow.

## Handle ambiguity

### Telescope — Building AKS Performance Benchmarking from Scratch

**Challenge:** I was hired by AKS with an ambiguous mission: "improve quality." There was no defined scope, no existing framework, and no clear prioritization of what to work on first. The mission was broad enough that it was easy to go in circles without delivering meaningful impact.

**Action:** I started by training myself to handle customer-reported incidents directly, so I could build firsthand intuition for where the real pain was. Through this triage work, I identified that a large portion of incidents were related to instability under overload or degraded experience under heavy usage — performance problems, not functional bugs. I escalated to leadership to request prioritization and investment in performance engineering, but got pushed back with a request for more data. So I created a project called Telescope — a benchmarking framework that measures performance above and below the AKS layer across compute, network, and storage. I designed it to be cloud-agnostic, so the same benchmarks could run against EKS and GKE, giving us competitive comparisons to identify performance gaps and prioritize which areas to focus on first. I later open-sourced the project to improve transparency with customers and incentivize external contributions of high-quality test scenarios.

**Result:** Telescope gave leadership the data they needed to greenlight investment. The competitive benchmarks made it clear where AKS lagged and where it led, turning vague quality concerns into a prioritized roadmap. The work that followed — driven by Telescope's findings — helped improve AKS scaling upper limit and speed by 10x. The project also became a reusable asset: open-sourcing it built trust with customers and attracted contributions that expanded benchmark coverage beyond what our team could have built alone.

## Owns failures

### Jumbo Frame Rollout Incident — MTU Optimization

**Challenge:** Multiple AKS customers reported degraded network performance caused by packet drops. Joint investigation revealed the root cause: bursts of high packet volume in short time windows were overflowing kernel network buffers, leading to dropped packets and retransmissions.

**Action:** I proposed enabling jumbo frames by increasing the default MTU from 1500 to 9000 in the node image, which reduces packet count per payload and alleviates buffer pressure. Before rolling out, we ran extensive benchmarks across multiple scenarios — intra-cluster pod-to-pod, pod-to-service, and ingress/egress — to validate the performance gains and confirm no side effects. The results were strong, so we began a phased region-by-region rollout.

**Result:** During rollout, a few customers reported incidents where traffic to specific external endpoints — notably Apple device services — started failing. I immediately investigated and identified the root cause: those external servers did not support jumbo frames and could not handle MTU path discovery (PMTUD) properly, causing oversized packets to be silently dropped. I quickly rolled back the node image change to restore service, then re-implemented the optimization as a user-configurable per-route setting rather than a global default. This gave customers the performance benefit where it was safe while avoiding breakage against endpoints that couldn't negotiate larger MTUs. The experience reinforced for me that even well-tested infrastructure changes can have blind spots at the boundary with systems you don't control — and that speed of rollback matters as much as speed of rollout.

## Resolve conflicts

### Networking Optimization — Cilium/eBPF vs Kubeproxy/iptables

**Challenge:** During a networking optimization initiative, a partner team advocated strongly for replacing iptables with Cilium as the default CNI across AKS, claiming Cilium performs O(1) routing lookup in kernel mode via eBPF while traditional Kubeproxy with iptables performs O(n) lookup in user space. The proposal was gaining momentum based on this narrative alone, without production data to back it up. If adopted prematurely, it would have affected the infrastructure stack for tens of thousands of clusters.

**Action:** I pushed back on the proposal and convinced stakeholders to run a rigorous, controlled benchmark before making any commitment. I helped define the test methodology so we could compare both solutions under realistic production conditions — measuring not just raw network throughput and latency, but also the impact on cluster scalability and control plane health at large node counts.

**Result:** The benchmark showed that Cilium's default configuration provided only marginal improvement in network performance over iptables. More critically, it revealed a significant downside: Cilium's per-node agent placed exponential list-watch load on the Kubernetes control plane, which negatively impacted the cluster size upper limit and scaling speed — a direct threat to our hyperscale customers. By insisting on a data-driven decision, we avoided adopting a solution that would have degraded the platform's core scalability promise, and instead focused engineering effort on targeted iptables optimizations that delivered measurable gains without the control plane trade-offs.

