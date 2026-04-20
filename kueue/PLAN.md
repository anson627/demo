# Kueue Feature Proposal Evaluation

All four are **issue-stage proposals** in `kubernetes-sigs/kueue` — no merged KEPs, no design docs, no PRs. Good contribution targets for Wayve.

## 1. KEP-9876 — Cross-CQ Minimum Guaranteed Runtime ([#9876](https://github.com/kubernetes-sigs/kueue/issues/9876))
- **Solves:** `minAdmitDuration` shielding borrowed workloads from cross-CQ fair-share preemption so they get useful runtime before nominal-quota reclaim.
- **Concern:** Trades reclaim responsiveness for progress; can starve the rightful nominal-quota owner during the window. Tightly coupled to KEP-1714 fair sharing.
- **Status:** Pure proposal, unassigned.

## 2. KEP-8522 — Within-CQ Guaranteed Runtimes ([#8522](https://github.com/kubernetes-sigs/kueue/issues/8522))
- **Solves:** Same-priority round-robin inside one CQ — after `minAdmitDuration`, long-running jobs become preemptible by equal-priority pending peers and are requeued.
- **Concern:** Forced preemption wastes work for non-checkpointable jobs; conflicts with KEP-3125 (maximum-execution-time) and gang scheduling. Needs job-level requeue semantics.
- **Status:** Assigned (`sohankunkerkar`), no PR yet. Sibling to #9876 — likely co-designed.

## 3. KEP-9734 — Usage-Based Fair Sharing ([#9734](https://github.com/kubernetes-sigs/kueue/issues/9734))
- **Solves:** Half-life-decayed historical usage at cohort level, complementing point-in-time DRS so bursty tenants aren't punished and long-idle tenants don't snap back to full priority.
- **Concern:** Most ambitious, least developed. Persistent state across restarts; tunable half-life is a policy footgun; observability/debugging gets harder. Extends KEP-1714 (history was explicitly out-of-scope) and KEP-4136.
- **Status:** Unassigned proposal.

## 4. Temporary Quota Overrides ([#8654](https://github.com/kubernetes-sigs/kueue/issues/8654), alt [#8869](https://github.com/kubernetes-sigs/kueue/issues/8869))
- **Solves:** Time-windowed nominal/borrow/lend quota changes for events, on-call surges, HPC migration. Modeled on kube-throttler `TemporaryThresholdOverrides` and Slurm reservations.
- **Design tension:** Embedded `ClusterQueue.spec` fields (simple, colocated) vs. standalone `ResourceQuotaLease` CRD in #8869 (independent lifecycle/RBAC, preserves nominal quota as a real boundary, avoids privileged "uber-uber" escalation per KEP-8826).
- **Status:** Most mature of the four — `priority/important-longterm`, active design debate, no merged direction.

## Recommendation for Wayve Contribution
- **Best entry point:** #8654 (Temporary Quota Overrides) — clearest user value, active discussion to plug into.
- **Best paired effort:** #9876 + #8522 — explicitly complementary, should be co-designed as one runtime-guarantee KEP.
- **Defer:** #9734 — needs more upstream alignment on KEP-1714 history extension before design work pays off.
