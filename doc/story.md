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

**Action:** I started by training myself to handle customer-reported incidents directly, so I could build firsthand intuition for where the real pain was. Through this triage work, I identified that a large portion of incidents were related to instability under overload or degraded experience under heavy usage — performance problems, not functional bugs. I escalated to leadership to request prioritization and investment in performance engineering, but got pushed back with a request for more data. So I created a project called Telescope — a benchmarking framework that measures performance above and below the AKS layer across compute, network, and storage. I designed it to be cloud-agnostic, so the same benchmarks could run against AWS and GCP, giving us competitive comparisons to identify performance gaps and prioritize which areas to focus on first.

**Result:** Telescope gave leadership the data they needed to greenlight investment. The competitive benchmarks made it clear where AKS lagged and where it led, turning vague quality concerns into a prioritized roadmap. That roadmap led to concrete work across multiple dimensions of the platform: control plane improvements such as etcd sharding, API server autoscaling, and controller/scheduler tuning improved AKS scaling upper limit and speed by 10x; networking improvements raised throughput and reduced latency; and storage improvements sped up disk attach/detach operations and improved IOPS. Telescope turned an ambiguous quality charter into a measurable engineering program with visible results across compute, network, and storage.

## Align cross-functional

### Telescope — Legal, Ethics, and Compliance Guardrails

**Challenge:** Once Telescope started producing competitive benchmark data, part of the project moved into uncomfortable territory. We were benchmarking competitor clouds at meaningful scale, which can feel slightly sketchy even when the technical intent is legitimate. Legal was concerned that if our GCP scenarios were too aggressive, we could be accused of harming service stability or crossing a line from fair measurement into abuse. I was uncomfortable with that risk too. I did not want the team to normalize tests that I could not reasonably defend as responsible.

**Action:** I addressed that discomfort directly instead of treating it as just a technical problem. I added auditing features into Telescope so we could identify which team ran which test scenarios, when they ran them, and at what scale. That gave us a practical compliance mechanism: if a scenario looked too aggressive, we could trace ownership and review it with the team instead of relying on trust that everyone would self-regulate. I also kept the framework opinionated around controlled quota, capped concurrency, isolated region. so we were not drifting toward a "push until something breaks" culture.

**Result:** Telescope stayed viable without becoming something I would have been uncomfortable defending. Legal had auditability and a concrete review path instead of relying on informal promises, and engineering had clearer boundaries on what counted as acceptable benchmarking behavior. The project still lived near a gray area, but the controls gave legal a practical way to unblock the project while retaining some control if something went wrong.

### Telescope — Marketing, Transparency, and Access Control

**Challenge:** Telescope also created a different cross-functional tension with PM and marketing. Strong benchmark results were valuable for showing Azure's advantages to customers, but weaker results were equally valuable internally because they highlighted where we needed to improve. I was uncomfortable with the idea of turning the project into selective storytelling by only showing the favorable charts.

**Action:** I pushed for a model that separated internal engineering truth from external communication. We implemented permission controls on the benchmark results and dashboard so raw internal data was visible only to the right audiences. At the same time, instead of directly handing customers curated benchmark data where Azure looked strongest, I open-sourced Telescope so customers could run the same tests themselves and inspect the methodology objectively. That gave PM and marketing a responsible way to talk about performance while keeping the engineering dataset complete.

**Result:** We avoided forcing Telescope into a false choice between marketing value and technical honesty. PM had a credible story for customers, engineering kept access to the full dataset including weak areas, and open-sourcing the framework improved trust because customers could evaluate the tool and methodology directly rather than depending only on our presentation of the results.

## Resolve conflicts

### Network Optimization — Increase Packet Buffer vs Increase MTU

**Challenge:** During a networking optimization effort, customer workloads were hitting packet drops, lower throughput, and higher latency under bursty traffic. The team agreed on the problem but not on the fix. One camp wanted to increase packet buffers so the system could absorb short bursts better. The other wanted to increase MTU, the maximum size of each network packet. A larger MTU means fewer packets are needed to send the same amount of data, which often improves efficiency. Both ideas were reasonable, but each came with trade-offs.

**Action:** I resolved the conflict by moving the discussion away from theory and toward production-like evidence. I convinced the team to build benchmarks and tests that mimicked real customer traffic patterns, especially bursty workloads, and to evaluate both approaches under the same scenarios. From there I led a careful trade-off review. I showed that increasing packet buffers can absorb bursts, but it consumes memory, can reduce memory available to user space depending on which buffers are enlarged, and still does not remove packet-rate and CPU pressure. I also showed that increasing MTU can improve throughput and latency by reducing packet overhead, but only if the VM hardware and the full network path can correctly support larger packets. That gave us a way to compare the options based on realistic behavior instead of whichever theory sounded loudest.

**Result:** The benchmarks gave the team a path to agreement. We decided to increase packet buffer sizes first, scaled proportionally to each VM's allocatable memory, because that was broadly safe and improved burst tolerance without overcommitting smaller machines. We then enabled larger MTU only for specific VM types whose hardware could reliably support bigger packets. That let us improve throughput and latency where the platform could handle it, without forcing a one-size-fits-all change across the fleet. The conflict was resolved by benchmarking real scenarios and choosing a pragmatic combination of both approaches.

## Own failures

### Jumbo Frame Rollout Incident — MTU Optimization

**Challenge:** Multiple AKS customers reported degraded network performance caused by packet drops. Joint investigation revealed the root cause: bursts of high packet volume in short time windows were overflowing kernel network buffers, leading to dropped packets and retransmissions.

**Action:** I proposed enabling jumbo frames by increasing the default MTU from 1500 to 9000 in the node image, which reduces packet count per payload and alleviates buffer pressure. I convinced the team not to decide from theory alone and ran extensive benchmarks across both the packet buffer and MTU approaches under multiple scenarios — intra-cluster pod-to-pod, pod-to-service, and ingress/egress — to validate the trade-offs, confirm the performance gains, and check for side effects. The data showed MTU was the stronger approach, so we began a phased region-by-region rollout.

**Result:** During rollout, a few customers reported incidents where traffic to specific external endpoints — notably Apple device services — started failing. I immediately investigated and identified the root cause: those external servers did not support jumbo frames and could not handle MTU path discovery (PMTUD) properly, causing oversized packets to be silently dropped. I quickly rolled back the node image change to restore service, then re-implemented the optimization as a user-configurable per-route setting rather than a global default. This gave customers the performance benefit where it was safe while avoiding breakage against endpoints that couldn't negotiate larger MTUs. The experience reinforced for me that even well-tested infrastructure changes can have blind spots at the boundary with systems you don't control — and that speed of rollback matters as much as speed of rollout.

