# Pain Points – Iteration 0

The overarching theme of Iteration 0 is that a fully manual Kubernetes setup
is extremely **error-prone**, even in a lab environment. This is intentional,
but it exposes where structure and tooling normally protect you.

---

## 1. Lack of upfront planning

At the beginning, I did not have a clear plan for the cluster layout.
Even for a lab, thinking through networking, certificates, and node roles
ahead of time significantly reduces rework.

**Lesson:**  
Planning is not overengineering — it is acceleration.

---

## 2. Certificate Authority and kubeconfigs

Managing the CA and generating kubeconfigs was the most tedious part of
the setup. This is also where the most learning happened.

The positive side is that it forces a deep understanding of how:
- TLS
- authentication
- RBAC authorization

work together in Kubernetes.

The downside is that **any mistake in certificates requires regenerating
both the certificate and the kubeconfig**, which is slow and easy to get wrong.

**Lesson:**  
Manual PKI is valuable for learning, but fragile without structure.

---

## 3. Networking friction

Networking felt sluggish and brittle. While basic routing can be set up,
it is not persistent and often requires manual intervention.

This makes it clear why production clusters rely on CNIs like Cilium —
not for convenience, but for correctness and reliability.

**Lesson:**  
Networking abstractions exist because raw networking does not scale.

---

## 4. Session management

Not using `tmux` was a mistake. While not strictly required, managing
multiple nodes without session persistence caused unnecessary friction.

**Lesson:**  
Tooling that improves workflow directly improves accuracy.

---

## 5. Automation (or lack thereof)

Many steps could have been automated. This was a conscious decision —
Iteration 0 intentionally avoids automation to expose every moving part.

However, the cost in repetition and error potential is significant.

**Lesson:**  
Automation is not about laziness; it is about reducing entropy.
.
