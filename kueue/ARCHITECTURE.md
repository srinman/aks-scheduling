# Kueue Architecture - Complete Guide

## Overview

Kueue is a Kubernetes-native job queueing system that sits between your workload submissions (Jobs, etc.) and the Kubernetes scheduler. It provides quota management, fair sharing, and priority-based scheduling across multiple tenants.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                               │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      Namespace: team-a                           │   │
│  │                                                                   │   │
│  │  ┌──────────────┐         ┌────────────────┐                    │   │
│  │  │   Job/Pod    │────────▶│  LocalQueue    │                    │   │
│  │  │              │         │  (team-a-queue)│                    │   │
│  │  │ label:       │         │                │                    │   │
│  │  │ queue-name   │         └────────┬───────┘                    │   │
│  │  └──────────────┘                  │                            │   │
│  │                                    │ Maps to                    │   │
│  └────────────────────────────────────┼────────────────────────────┘   │
│                                       │                                 │
│  ┌────────────────────────────────────▼────────────────────────────┐   │
│  │              Cluster-Scoped: ClusterQueue                        │   │
│  │              (cluster-queue)                                     │   │
│  │                                                                   │   │
│  │  ┌──────────────────────────────────────────────────────────┐   │   │
│  │  │  Quota Management:                                        │   │   │
│  │  │  • CPU: 9 (nominal)                                       │   │   │
│  │  │  • Memory: 36Gi (nominal)                                 │   │   │
│  │  │  • Strategy: BestEffortFIFO                               │   │   │
│  │  │  • Preemption: LowerPriority                              │   │   │
│  │  └──────────────────────────────────────────────────────────┘   │   │
│  │                          │                                        │   │
│  │                          │ Uses                                  │   │
│  │                          ▼                                        │   │
│  │              ┌───────────────────────┐                           │   │
│  │              │   ResourceFlavor      │                           │   │
│  │              │   (default-flavor)    │                           │   │
│  │              │                       │                           │   │
│  │              │  Represents resource  │                           │   │
│  │              │  characteristics      │                           │   │
│  │              └───────────┬───────────┘                           │   │
│  └──────────────────────────┼───────────────────────────────────────┘   │
│                             │                                            │
│                             │ Maps to                                    │
│                             ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Physical Nodes                                │   │
│  │                                                                   │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │   │
│  │  │  Node 1  │  │  Node 2  │  │  Node 3  │  │  Node 4  │        │   │
│  │  │          │  │          │  │          │  │          │        │   │
│  │  │ 4 CPU    │  │ 4 CPU    │  │ 4 CPU    │  │ 4 CPU    │        │   │
│  │  │ 16Gi RAM │  │ 16Gi RAM │  │ 16Gi RAM │  │ 16Gi RAM │        │   │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Kueue Controller                              │   │
│  │                                                                   │   │
│  │  • Watches for new Jobs/Workloads                                │   │
│  │  • Checks quota availability in ClusterQueue                     │   │
│  │  • Manages admission (suspend/unsuspend)                         │   │
│  │  • Handles preemption when enabled                               │   │
│  │  • Updates Workload status                                       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Object Relationships and Data Flow

```
User Submits Job
       │
       ▼
┌──────────────────┐
│   Job            │  1. User creates a Job with label:
│   (suspend:true) │     kueue.x-k8s.io/queue-name: team-a-queue
└────────┬─────────┘
         │
         │ Kueue watches Job, creates Workload
         ▼
┌──────────────────┐
│   Workload       │  2. Kueue automatically creates a Workload object
│   (job-xxx)      │     representing the resource requirements
└────────┬─────────┘
         │
         │ References
         ▼
┌──────────────────┐
│  LocalQueue      │  3. Workload is associated with LocalQueue
│  (team-a-queue)  │     (namespace-scoped, tenant-specific)
└────────┬─────────┘
         │
         │ Maps to
         ▼
┌──────────────────┐
│  ClusterQueue    │  4. LocalQueue references ClusterQueue
│  (cluster-queue) │     (cluster-scoped, shared resource pool)
│                  │
│  ┌────────────┐  │
│  │Quota Check │  │  5. ClusterQueue checks:
│  │            │  │     • Available quota (CPU, memory)
│  │CPU: 9      │  │     • Queueing strategy (FIFO)
│  │Used: 3     │  │     • Priority
│  │Free: 6     │  │     • Preemption rules
│  └────────────┘  │
└────────┬─────────┘
         │
         │ Uses
         ▼
┌──────────────────┐
│ ResourceFlavor   │  6. ClusterQueue allocates from ResourceFlavor
│ (default-flavor) │     (defines resource characteristics)
└────────┬─────────┘
         │
         │ Represents
         ▼
┌──────────────────┐
│  Physical Nodes  │  7. ResourceFlavor maps to actual node resources
│  (Node Pool)     │     (capacity managed by Kubernetes)
└──────────────────┘

         │
         │ If quota available:
         ▼
┌──────────────────┐
│  Workload        │  8. Workload marked as "Admitted"
│  Status: Admitted│     Quota reserved in ClusterQueue
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Job             │  9. Kueue unsuspends the Job
│  (suspend:false) │     Job controller creates Pods
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Pods Running    │  10. Kubernetes scheduler places pods on nodes
│  on Nodes        │      Job executes to completion
└──────────────────┘
```

---

## Core Components Deep Dive

### 1. **Job** (User Submitted Workload)
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: my-job
  namespace: team-a
  labels:
    kueue.x-k8s.io/queue-name: team-a-queue  # Routes to LocalQueue
spec:
  suspend: true  # Important! Prevents immediate pod creation
  parallelism: 3
  template:
    spec:
      containers:
      - name: worker
        resources:
          requests:
            cpu: "1"
            memory: "512Mi"
```

**Key Points:**
- User creates Jobs with `suspend: true`
- Label `kueue.x-k8s.io/queue-name` routes to specific LocalQueue
- Kueue unsuspends when admitted
- Supports: Job, CronJob, RayJob, MPIJob, PyTorchJob, etc.

---

### 2. **Workload** (Kueue's Internal Representation)
```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: Workload
metadata:
  name: job-my-job-xxxxx
  namespace: team-a
spec:
  queueName: team-a-queue
  podSets:
  - count: 3
    name: main
    template:
      spec:
        containers:
        - resources:
            requests:
              cpu: "1"
              memory: "512Mi"
status:
  admission:
    clusterQueue: cluster-queue
    podSetAssignments:
    - count: 3
      flavors:
        cpu: default-flavor
        memory: default-flavor
      resourceUsage:
        cpu: "3"
        memory: "1536Mi"
  conditions:
  - type: Admitted
    status: "True"
```

**Key Points:**
- **Automatically created** by Kueue when Job is submitted
- Represents resource requirements
- Tracks admission status and quota reservation
- Users typically don't create these manually

---

### 3. **LocalQueue** (Namespace-Scoped Queue)
```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: team-a-queue
  namespace: team-a
spec:
  clusterQueue: cluster-queue  # References cluster-wide queue
```

**Key Points:**
- **Namespace-scoped** - one per team/tenant
- Acts as entry point for workloads in a namespace
- Maps to a ClusterQueue for quota enforcement
- Multiple LocalQueues can reference the same ClusterQueue

**Use Cases:**
- Multi-tenancy (team-a-queue, team-b-queue)
- Department isolation
- Project-based resource allocation

---

### 4. **ClusterQueue** (Cluster-Wide Resource Pool)
```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: cluster-queue
spec:
  namespaceSelector: {}  # Which namespaces can use this queue
  queueingStrategy: BestEffortFIFO  # Or StrictFIFO
  preemption:
    withinClusterQueue: LowerPriority  # Enable preemption
    reclaimWithinCohort: Any
    borrowWithinCohort:
      policy: LowerPriority
  resourceGroups:
  - coveredResources: ["cpu", "memory", "nvidia.com/gpu"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 9        # Guaranteed quota
        borrowingLimit: 5      # Can borrow up to 5 more
      - name: memory
        nominalQuota: 36Gi
```

**Key Points:**
- **Cluster-scoped** - manages quota across namespaces
- Defines resource limits (CPU, memory, GPUs, etc.)
- Enforces queueing strategy (FIFO, priority-based)
- Handles preemption and borrowing
- Can be part of a **Cohort** for resource sharing

**Quota Types:**
- **nominalQuota**: Guaranteed resources
- **borrowingLimit**: Additional resources can borrow from cohort
- **lendingLimit**: Max resources can lend to others

---

### 5. **ResourceFlavor** (Resource Characteristics)
```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ResourceFlavor
metadata:
  name: default-flavor
nodeLabels:
  instance-type: standard-d4s-v3
  zone: us-east-1a
nodeSelector:
  workload-type: batch
tolerations:
- key: batch-workload
  operator: Equal
  value: "true"
  effect: NoSchedule
```

**Key Points:**
- **Cluster-scoped** - describes types of resources
- Maps to node characteristics (instance types, zones, GPUs)
- Can specify node selectors, labels, tolerations, taints
- Multiple flavors allow heterogeneous resources

**Common Use Cases:**
- **GPU flavors**: `gpu-a100`, `gpu-v100`
- **CPU flavors**: `spot-instances`, `on-demand`
- **Zone flavors**: `us-east-1a`, `us-west-2b`
- **Performance tiers**: `high-memory`, `compute-optimized`

---

### 6. **Nodes** (Physical/Virtual Infrastructure)
```
Physical Kubernetes Nodes
├── Node Pool 1 (default-flavor)
│   ├── node-1: 4 CPU, 16Gi RAM
│   ├── node-2: 4 CPU, 16Gi RAM
│   └── node-3: 4 CPU, 16Gi RAM
│
├── Node Pool 2 (gpu-flavor)
│   ├── gpu-node-1: 8 CPU, 32Gi RAM, 1x A100
│   └── gpu-node-2: 8 CPU, 32Gi RAM, 1x A100
│
└── Node Pool 3 (spot-flavor)
    ├── spot-node-1: 4 CPU, 16Gi RAM
    └── spot-node-2: 4 CPU, 16Gi RAM
```

**Key Points:**
- Actual compute resources in the cluster
- Managed by Kubernetes (not Kueue directly)
- ResourceFlavors map to node characteristics
- Kueue manages **logical quota**, Kubernetes manages **physical capacity**

---

## Advanced Concepts

### Cohort (Resource Sharing Between ClusterQueues)

```
┌─────────────────────────────────────────────────────────┐
│                    Cohort: research                      │
│                                                           │
│  ┌──────────────────┐        ┌──────────────────┐       │
│  │ ClusterQueue: ML │        │ ClusterQueue: AI │       │
│  │                  │        │                  │       │
│  │ Nominal: 10 CPU  │◄──────►│ Nominal: 10 CPU  │       │
│  │ Borrowing: 10    │ Borrow │ Borrowing: 10    │       │
│  │                  │        │                  │       │
│  │ (Can borrow from │        │ (Can borrow from │       │
│  │  AI if idle)     │        │  ML if idle)     │       │
│  └──────────────────┘        └──────────────────┘       │
│                                                           │
│  Total Cohort Resources: 20 CPU                          │
│  Flexible allocation based on demand                     │
└─────────────────────────────────────────────────────────┘
```

**Benefits:**
- Fair sharing when teams have variable load
- Borrow unused quota from other teams
- Automatic reclaim when owner needs resources
- Increases overall cluster utilization

---

### Workload Priority and Preemption

```
Priority Classes:
┌────────────────────────┐
│ WorkloadPriorityClass  │
│                        │
│ high-priority (100)    │  ← Preempts lower priority
│ medium-priority (50)   │
│ low-priority (10)      │  ← Gets preempted
└────────────────────────┘

Preemption Flow:
1. High-priority workload submitted
2. Insufficient quota available
3. Kueue identifies low-priority workload using resources
4. Low-priority workload evicted (pods deleted)
5. High-priority workload admitted immediately
6. Low-priority workload re-queued
```

---

## Complete Lifecycle Example

### Scenario: Team A submits 4 jobs to a cluster with 9 CPU quota

```
Time: T0 - Initial State
┌─────────────────────────────────┐
│ ClusterQueue: cluster-queue     │
│ Available: 9 CPU                │
│ Used: 0 CPU                     │
│ Pending Workloads: 0            │
└─────────────────────────────────┘

Time: T1 - Submit Job 1 (3 CPU)
┌─────────────────────────────────┐
│ ClusterQueue: cluster-queue     │
│ Available: 6 CPU (9-3)          │
│ Used: 3 CPU                     │
│ Pending Workloads: 0            │
│                                 │
│ ✅ Job 1: ADMITTED (3 CPU)      │
└─────────────────────────────────┘

Time: T2 - Submit Job 2 (3 CPU)
┌─────────────────────────────────┐
│ ClusterQueue: cluster-queue     │
│ Available: 3 CPU (9-6)          │
│ Used: 6 CPU                     │
│ Pending Workloads: 0            │
│                                 │
│ ✅ Job 1: RUNNING (3 CPU)       │
│ ✅ Job 2: ADMITTED (3 CPU)      │
└─────────────────────────────────┘

Time: T3 - Submit Job 3 (3 CPU)
┌─────────────────────────────────┐
│ ClusterQueue: cluster-queue     │
│ Available: 0 CPU (9-9)          │
│ Used: 9 CPU                     │
│ Pending Workloads: 0            │
│                                 │
│ ✅ Job 1: RUNNING (3 CPU)       │
│ ✅ Job 2: RUNNING (3 CPU)       │
│ ✅ Job 3: ADMITTED (3 CPU)      │
└─────────────────────────────────┘

Time: T4 - Submit Job 4 (3 CPU) - QUOTA EXCEEDED!
┌─────────────────────────────────┐
│ ClusterQueue: cluster-queue     │
│ Available: 0 CPU                │
│ Used: 9 CPU                     │
│ Pending Workloads: 1 ⏸️         │
│                                 │
│ ✅ Job 1: RUNNING (3 CPU)       │
│ ✅ Job 2: RUNNING (3 CPU)       │
│ ✅ Job 3: RUNNING (3 CPU)       │
│ ⏸️ Job 4: QUEUED (waiting)      │
└─────────────────────────────────┘

Time: T5 - Job 1 Completes
┌─────────────────────────────────┐
│ ClusterQueue: cluster-queue     │
│ Available: 3 CPU (9-6)          │
│ Used: 6 CPU                     │
│ Pending Workloads: 0            │
│                                 │
│ ✅ Job 1: COMPLETED             │
│ ✅ Job 2: RUNNING (3 CPU)       │
│ ✅ Job 3: RUNNING (3 CPU)       │
│ ✅ Job 4: ADMITTED (3 CPU) ← Auto-started!
└─────────────────────────────────┘
```

---

## Key Takeaways

### **Hierarchy**
```
Physical Nodes (Kubernetes)
    ↑
ResourceFlavor (describes node characteristics)
    ↑
ClusterQueue (manages quota across flavors)
    ↑
LocalQueue (namespace-specific entry point)
    ↑
Workload (Kueue's representation of Job)
    ↑
Job/Pod (user submitted workload)
```

### **Separation of Concerns**

| Layer | Responsibility |
|-------|---------------|
| **User** | Submit Jobs with resource requests |
| **LocalQueue** | Namespace isolation and routing |
| **ClusterQueue** | Quota enforcement and fairness |
| **ResourceFlavor** | Resource characteristics and mapping |
| **Workload** | Internal tracking and admission state |
| **Kueue Controller** | Admission control and queue management |
| **Kubernetes Scheduler** | Physical pod placement on nodes |

### **Why This Architecture?**

1. **Separation of logical quota from physical capacity**
   - Kueue: "You can use 9 CPUs" (logical quota)
   - Kubernetes: "I have 16 CPUs available" (physical capacity)
   - Prevents oversubscription and resource contention

2. **Multi-tenancy without complexity**
   - Each team gets a LocalQueue
   - Shared ClusterQueue enforces fair sharing
   - No need for separate clusters

3. **Flexibility with ResourceFlavors**
   - Run jobs on different hardware (GPU, CPU, spot instances)
   - Fungibility: Try GPU, fall back to CPU if unavailable
   - Cost optimization: Prefer spot, use on-demand if needed

4. **Workload lifecycle management**
   - Jobs don't immediately create pods (suspend: true)
   - Kueue controls when jobs start
   - Automatic cleanup and re-queuing

---

## Comparison with Traditional Kubernetes

### Without Kueue (Vanilla Kubernetes)
```
User → Job → Pods Created Immediately → Pending (if no capacity)
                                     ↓
                              Scheduler watches forever
                              No queue visibility
                              No quota management
                              Manual intervention needed
```

### With Kueue
```
User → Job → Workload Created → Queued in LocalQueue
                              ↓
                         ClusterQueue checks quota
                              ↓
                   Admitted when resources available
                              ↓
                         Job unsuspended
                              ↓
                    Pods created and scheduled
```

**Key Differences:**
- ✅ **Quota awareness**: Jobs wait in queue, not as pending pods
- ✅ **Visibility**: Know your position in queue
- ✅ **Fairness**: FIFO, priority, fair sharing policies
- ✅ **Efficiency**: No pod thrashing or scheduler overhead
- ✅ **Multi-tenancy**: Namespace isolation with shared resources

---

## Further Reading

- [Kueue Official Docs](https://kueue.sigs.k8s.io/docs/)
- [Concepts: ClusterQueue](https://kueue.sigs.k8s.io/docs/concepts/cluster_queue/)
- [Concepts: Cohort](https://kueue.sigs.k8s.io/docs/concepts/cohort/)
- [Fair Sharing](https://kueue.sigs.k8s.io/docs/concepts/fair_sharing/)
- [Preemption](https://kueue.sigs.k8s.io/docs/concepts/preemption/)
