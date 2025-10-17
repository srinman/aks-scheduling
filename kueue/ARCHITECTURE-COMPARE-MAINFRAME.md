# Kueue vs Mainframe Batch Systems - Architecture Comparison

## Executive Summary

**"The best ideas never die—they get modernized and adapted to new platforms!"**

This document compares Kueue with mainframe batch systems to help understand the architectural parallels.

---

## Side-by-Side Comparison

| **Mainframe Concept** | **Kueue Equivalent** | **Purpose** |
|----------------------|---------------------|-------------|
| **JES2/JES3** | **Kueue Controller** | Job queue management and scheduling |
| **Job Class** | **LocalQueue + WorkloadPriorityClass** | Job categorization and routing |
| **Initiator** | **Kubernetes Scheduler** | Executes jobs when resources available |
| **Service Class** | **ClusterQueue** | Resource pool with guaranteed resources |
| **WLM (Workload Manager)** | **ClusterQueue + Cohort** | Dynamic resource allocation and priorities |
| **SYSOUT Class** | *N/A (handled by logging)* | Output management |
| **JCL (Job Control Language)** | **Job YAML + Labels** | Job definition and requirements |
| **Job Entry** | **Job Submission (kubectl apply)** | How jobs enter the system |
| **Job Queue** | **Workload Queue** | Jobs waiting for resources |
| **Performance Group** | **ResourceFlavor + NodeSelector** | Resource characteristics/partitioning |
| **Goal Mode** | **QueueingStrategy + Preemption** | Response time and throughput goals |
| **Resource Group** | **ResourceGroup in ClusterQueue** | Grouping resources (CPU, memory, etc.) |
| **SMF Records** | **Prometheus Metrics** | Job accounting and monitoring |
| **RACF/Security** | **RBAC + Namespaces** | Access control and isolation |
| **LPAR** | **Kubernetes Node/Node Pool** | Physical/logical resource partitioning |
| **Parallel Sysplex** | **Multi-cluster (MultiKueue)** | Multiple systems sharing workload |

---

## Detailed Architectural Comparison

### 1. Job Entry Subsystem (JES2/JES3) ↔ Kueue Controller

#### **Mainframe: JES2/JES3**
```
┌─────────────────────────────────────────────┐
│            JES2/JES3                        │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │  Job Entry                          │   │
│  │  • Accepts jobs via internal reader │   │
│  │  • Validates JCL                    │   │
│  │  • Assigns job number (JOBxxxxx)    │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │  Job Queue Management               │   │
│  │  • Queues by CLASS                  │   │
│  │  • Priority ordering                │   │
│  │  • Holds and releases               │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │  Job Selection                      │   │
│  │  • Matches to initiators            │   │
│  │  • Checks resource availability     │   │
│  │  • Submits to execution             │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

#### **Kueue: Controller**
```
┌─────────────────────────────────────────────┐
│         Kueue Controller                    │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │  Job Watcher                        │   │
│  │  • Watches for new Jobs             │   │
│  │  • Validates queue labels           │   │
│  │  • Creates Workload object          │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │  Queue Management                   │   │
│  │  • Queues in LocalQueue             │   │
│  │  • Priority ordering                │   │
│  │  • Suspend/Unsuspend control        │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │  Admission Control                  │   │
│  │  • Checks ClusterQueue quota        │   │
│  │  • Reserves resources               │   │
│  │  • Unsuspends job for execution     │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

**Key Similarities:**
- Both accept jobs into a managed queue
- Both validate job definitions before queuing
- Both perform admission control based on resources
- Both track job lifecycle from submission to completion

---

### 2. Job Class ↔ LocalQueue + Priority

#### **Mainframe: Job Class**
```jcl
//PAYROLL  JOB (ACCT123),'WEEKLY PAYROLL',
//         CLASS=A,              ← High priority production
//         MSGCLASS=X,
//         MSGLEVEL=(1,1),
//         TIME=10,
//         REGION=4M

//BACKUP   JOB (ACCT456),'NIGHTLY BACKUP',
//         CLASS=B,              ← Lower priority batch
//         MSGCLASS=X,
//         TIME=120

//DEVTEST  JOB (ACCT789),'DEV TESTING',
//         CLASS=C,              ← Development/test work
//         MSGCLASS=X,
//         TIME=5
```

**Classes Define:**
- Priority (A > B > C)
- Resource allocation
- Which initiators can run them
- Scheduling preference

#### **Kueue: LocalQueue + Priority**
```yaml
# High priority production
apiVersion: batch/v1
kind: Job
metadata:
  labels:
    kueue.x-k8s.io/queue-name: production-queue
    kueue.x-k8s.io/priority-class: high-priority
spec:
  parallelism: 10
  template:
    spec:
      containers:
      - name: payroll
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"

---
# Lower priority batch
apiVersion: batch/v1
kind: Job
metadata:
  labels:
    kueue.x-k8s.io/queue-name: batch-queue
    kueue.x-k8s.io/priority-class: medium-priority
spec:
  parallelism: 5
  template:
    spec:
      containers:
      - name: backup

---
# Development/test
apiVersion: batch/v1
kind: Job
metadata:
  labels:
    kueue.x-k8s.io/queue-name: dev-queue
    kueue.x-k8s.io/priority-class: low-priority
```

**Parallel Concepts:**
- LocalQueue = Job Class routing
- WorkloadPriorityClass = Job CLASS priority
- Namespace = Accounting/project separation
- Labels = Job categorization

---

### 3. Initiator ↔ Kubernetes Scheduler

#### **Mainframe: Initiator**
```
Initiator Configuration:
┌────────────────────────────────────────┐
│ INIT1: CLASS=(A,B), PRTY=15           │
│   Can run CLASS A or B jobs            │
│   High priority initiator              │
│                                        │
│ INIT2: CLASS=(B,C), PRTY=10           │
│   Can run CLASS B or C jobs            │
│   Medium priority                      │
│                                        │
│ INIT3: CLASS=(C), PRTY=5              │
│   Can only run CLASS C jobs            │
│   Low priority                         │
└────────────────────────────────────────┘

Function:
• Waits for jobs in assigned classes
• Claims job when available
• Allocates resources (memory, devices)
• Starts job execution
• Monitors completion
• Releases resources
```

#### **Kueue: Kubernetes Scheduler (Post-Admission)**
```
Kueue Flow:
┌────────────────────────────────────────┐
│ 1. Job submitted (suspended)           │
│ 2. Kueue checks ClusterQueue quota     │
│ 3. If quota available:                 │
│    - Workload marked "Admitted"        │
│    - Quota reserved                    │
│    - Job unsuspended                   │
│ 4. Kubernetes Scheduler:               │
│    - Selects appropriate node          │
│    - Checks node capacity              │
│    - Binds pod to node                 │
│    - Kubelet starts container          │
└────────────────────────────────────────┘

Key Difference:
• Kueue = Admission control (can it run?)
• K8s Scheduler = Placement (where to run?)
• Similar to JES2 + Initiator combined
```

**Parallel:**
- Initiator "claims" jobs → Kueue "admits" workloads
- Initiator checks resources → ClusterQueue checks quota
- Initiator starts execution → Scheduler places pods
- Both manage job lifecycle

---

### 4. Workload Manager (WLM) ↔ ClusterQueue + Cohort

#### **Mainframe: WLM (Workload Manager)**

```
Service Classes and Goals:
┌──────────────────────────────────────────────┐
│ Service Class: PROD                          │
│   Goal: 90% complete within 5 seconds        │
│   Importance: 1 (highest)                    │
│   Resources: Can use up to 80% CPU           │
│                                              │
│ Service Class: BATCH                         │
│   Goal: Discretionary (use leftover)        │
│   Importance: 3                              │
│   Resources: Can use remaining CPU           │
│                                              │
│ Service Class: DEV                           │
│   Goal: Velocity (throughput)               │
│   Importance: 4 (lowest)                     │
│   Resources: Minimum 10% CPU guaranteed      │
└──────────────────────────────────────────────┘

WLM Behavior:
• Monitors service class performance vs goals
• Adjusts dispatching priorities dynamically
• Moves resources between service classes
• Preempts lower importance work when needed
• Reports performance against goals
```

#### **Kueue: ClusterQueue + Cohort**

```yaml
# Production ClusterQueue (like PROD service class)
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: production-cq
spec:
  cohort: company-wide  # Can borrow/lend resources
  preemption:
    withinClusterQueue: LowerPriority
    reclaimWithinCohort: Any
    borrowWithinCohort:
      policy: LowerPriority
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 50        # Guaranteed: 50 CPUs
        borrowingLimit: 30      # Can borrow: +30 CPUs
      - name: memory
        nominalQuota: 200Gi

---
# Batch ClusterQueue (like BATCH service class)
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: batch-cq
spec:
  cohort: company-wide
  preemption:
    reclaimWithinCohort: Never  # Can be preempted
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 20
        borrowingLimit: 50      # Opportunistic use
        lendingLimit: 15        # Can lend to others

---
# Dev ClusterQueue (like DEV service class)
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: dev-cq
spec:
  cohort: company-wide
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 10        # Minimum guaranteed
        borrowingLimit: 20
```

**WLM vs Kueue Cohort Behavior:**

| **WLM Feature** | **Kueue Equivalent** | **Behavior** |
|-----------------|---------------------|--------------|
| Service Class | ClusterQueue | Resource pool definition |
| Importance Level | Priority in preemption policy | Determines who gets preempted |
| Resource Groups | Cohort | Share resources across queues |
| Goal Mode | QueueingStrategy | FIFO, priority-based, velocity |
| Dynamic Priority | Preemption + Borrowing | Adjust resource allocation |
| Discretionary | borrowingLimit | Use idle resources |
| Resource Isolation | nominalQuota | Guaranteed minimum |

**Key Similarity:**
Both systems dynamically adjust resource allocation based on:
- Workload demand
- Priority/Importance
- Performance goals
- Available capacity
- Fair sharing policies

---

### 5. Resource Management Comparison

#### **Mainframe: LPAR + WLM**
```
Physical Mainframe (z15)
├── LPAR1 (Production) - 60% CPU weight
│   ├── Service Class PROD (Importance 1)
│   ├── Service Class BATCH (Importance 3)
│   └── WLM manages priorities within LPAR
│
├── LPAR2 (Development) - 30% CPU weight
│   ├── Service Class DEV (Importance 4)
│   └── Service Class TEST (Importance 5)
│
└── LPAR3 (QA) - 10% CPU weight
    └── Service Class QA (Importance 3)

WLM can:
• Shift CPU between service classes within LPAR
• Adjust dispatching priority based on goals
• Preempt lower importance work
• Move work between systems (Sysplex)
```

#### **Kueue: Node Pools + ClusterQueues**
```
Kubernetes Cluster
├── Node Pool: Production (60 CPUs)
│   ├── ResourceFlavor: prod-flavor
│   ├── ClusterQueue: production-cq (nominalQuota: 50 CPU)
│   ├── ClusterQueue: batch-cq (nominalQuota: 20 CPU)
│   └── Cohort manages borrowing/lending
│
├── Node Pool: Development (30 CPUs)
│   ├── ResourceFlavor: dev-flavor
│   └── ClusterQueue: dev-cq (nominalQuota: 30 CPU)
│
└── Node Pool: QA (10 CPUs)
    ├── ResourceFlavor: qa-flavor
    └── ClusterQueue: qa-cq (nominalQuota: 10 CPU)

Kueue can:
• Share CPU quota between ClusterQueues via Cohort
• Adjust admission based on priority
• Preempt lower priority workloads
• Distribute work across clusters (MultiKueue)
```

---

### 6. Job Definition Language Comparison

#### **Mainframe: JCL (Job Control Language)**
```jcl
//PAYROLL  JOB (ACCT123),'WEEKLY PAYROLL',
//         CLASS=A,              ← Queue/Priority
//         MSGCLASS=X,
//         MSGLEVEL=(1,1),
//         NOTIFY=&SYSUID,
//         TIME=10,              ← Time limit
//         REGION=4M             ← Memory requirement
//*
//STEP1    EXEC PGM=PAYROLL01,
//         PARM='WEEKLY'
//SYSPRINT DD SYSOUT=*
//PAYFILE  DD DSN=PAY.MASTER.FILE,
//            DISP=SHR
//UPDTFILE DD DSN=PAY.UPDATE.FILE,
//            DISP=(NEW,CATLG),
//            SPACE=(CYL,(10,5)),
//            UNIT=SYSDA
```

#### **Kueue: Kubernetes Job YAML**
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: payroll
  namespace: finance                          # Like ACCT/USER
  labels:
    kueue.x-k8s.io/queue-name: production-queue  # Like CLASS
    kueue.x-k8s.io/priority-class: high-priority  # Priority
spec:
  activeDeadlineSeconds: 600               # Like TIME=10
  parallelism: 1
  completions: 1
  suspend: true                            # Kueue controls execution
  template:
    spec:
      containers:
      - name: payroll01                    # Like PGM=PAYROLL01
        image: payroll:v1.0
        args: ["--mode=WEEKLY"]            # Like PARM
        resources:
          requests:
            memory: "4Gi"                  # Like REGION=4M
            cpu: "2"
        volumeMounts:
        - name: pay-master
          mountPath: /data/master
        - name: pay-update
          mountPath: /data/update
      volumes:
      - name: pay-master                   # Like DD DSN=PAY.MASTER.FILE
        persistentVolumeClaim:
          claimName: pay-master-pvc
      - name: pay-update                   # Like DD DSN=PAY.UPDATE.FILE
        persistentVolumeClaim:
          claimName: pay-update-pvc
      restartPolicy: Never
```

**Conceptual Mapping:**
- `JOB` statement → Job metadata
- `CLASS` → `kueue.x-k8s.io/queue-name`
- `REGION` → `resources.requests.memory`
- `TIME` → `activeDeadlineSeconds`
- `EXEC PGM` → `container.image`
- `PARM` → `container.args`
- `DD` statement → `volumeMounts` + `volumes`
- `SYSOUT` → stdout/stderr (logging)

---

### 7. Fair Sharing and Priority

#### **Mainframe: WLM Fair Share**
```
Fair Share Configuration:
┌──────────────────────────────────────────┐
│ Report Class: FINANCE                    │
│   Fair Share: 40%                        │
│   Service Classes: PROD, BATCH           │
│                                          │
│ Report Class: MARKETING                  │
│   Fair Share: 30%                        │
│   Service Classes: ANALYTICS             │
│                                          │
│ Report Class: IT                         │
│   Fair Share: 30%                        │
│   Service Classes: DEV, TEST             │
└──────────────────────────────────────────┘

WLM adjusts priorities to meet fair share goals
over time (typically 3-5 minute intervals)
```

#### **Kueue: Fair Sharing**
```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: finance-cq
spec:
  cohort: company-wide
  fairSharing:
    weight: 40                    # Like Fair Share: 40%
  preemption:
    reclaimWithinCohort: Any
    borrowWithinCohort:
      policy: LowerPriority
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 40

---
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: marketing-cq
spec:
  cohort: company-wide
  fairSharing:
    weight: 30                    # Like Fair Share: 30%
  resourceGroups:
  - coveredResources: ["cpu"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 30

---
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: it-cq
spec:
  cohort: company-wide
  fairSharing:
    weight: 30
  resourceGroups:
  - coveredResources: ["cpu"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 30
```

**Fair Sharing Behavior:**
- Both systems track resource usage over time
- Adjust priorities to meet target allocations
- Allow temporary over/under use
- Reclaim resources when needed
- Preempt to maintain fairness

---

### 8. Parallel Execution and Sysplex

#### **Mainframe: Parallel Sysplex**
```
┌─────────────────────────────────────────────────────┐
│           Parallel Sysplex                          │
│                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐│
│  │   System A  │  │   System B  │  │   System C  ││
│  │   (z15)     │  │   (z15)     │  │   (z15)     ││
│  │             │  │             │  │             ││
│  │ JES2 Member │  │ JES2 Member │  │ JES2 Member ││
│  │             │  │             │  │             ││
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘│
│         │                │                │        │
│         └────────────────┴────────────────┘        │
│                          │                         │
│                   Shared Job Queue                 │
│                   Shared Spool                     │
│                   Coupling Facility                │
└─────────────────────────────────────────────────────┘

Features:
• Jobs can run on any system
• Workload balancing across systems
• Automatic failover
• Shared spool and job queue
• WLM routes work to best system
```

#### **Kueue: MultiKueue (Multi-Cluster)**
```
┌─────────────────────────────────────────────────────┐
│           MultiKueue Architecture                   │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │      Management Cluster (Hub)               │   │
│  │                                             │   │
│  │  ┌───────────────────────────────────────┐ │   │
│  │  │  MultiKueueCluster CRDs               │ │   │
│  │  │  • Cluster-A (us-east)                │ │   │
│  │  │  • Cluster-B (us-west)                │ │   │
│  │  │  • Cluster-C (eu-central)             │ │   │
│  │  └───────────────────────────────────────┘ │   │
│  │                                             │   │
│  │  MultiKueue Controller:                    │   │
│  │  • Receives job submissions                │   │
│  │  • Checks capacity across clusters         │   │
│  │  • Routes to cluster with resources        │   │
│  └─────────────────┬───────────────────────────┘   │
│                    │                               │
│       ┌────────────┼────────────┐                  │
│       │            │            │                  │
│  ┌────▼─────┐ ┌───▼──────┐ ┌──▼───────┐          │
│  │Cluster-A │ │Cluster-B │ │Cluster-C │          │
│  │(AKS)     │ │(EKS)     │ │(GKE)     │          │
│  │          │ │          │ │          │          │
│  │ Kueue    │ │ Kueue    │ │ Kueue    │          │
│  │ Worker   │ │ Worker   │ │ Worker   │          │
│  └──────────┘ └──────────┘ └──────────┘          │
└─────────────────────────────────────────────────────┘

Features:
• Jobs submitted to management cluster
• Routed to worker cluster with capacity
• Automatic failover between clusters
• Cross-cloud support (Azure, AWS, GCP)
• Federated queue management
```

**Parallel Concepts:**
- Sysplex systems → MultiKueue clusters
- JES2 shared queue → Management cluster queue
- WLM routing → MultiKueue admission controller
- Coupling facility → Management cluster coordination
- Automatic workload balancing in both

---

## Key Philosophical Similarities

### 1. **Separation of Admission and Execution**
- **Mainframe**: JES2 admits jobs, Initiators execute them
- **Kueue**: Kueue admits workloads, Kubernetes Scheduler executes them

### 2. **Resource Virtualization**
- **Mainframe**: Service classes define logical resource pools
- **Kueue**: ClusterQueues define logical quota pools

### 3. **Multi-Tenancy**
- **Mainframe**: Job classes, accounting codes, RACF
- **Kueue**: LocalQueues, namespaces, RBAC

### 4. **Fair Sharing Over Time**
- **Mainframe**: WLM tracks usage and adjusts priorities
- **Kueue**: Fair sharing weights in cohorts

### 5. **Priority and Preemption**
- **Mainframe**: Higher importance can preempt lower
- **Kueue**: Higher priority can preempt lower

### 6. **Queueing Discipline**
- **Mainframe**: FIFO within class, priority between classes
- **Kueue**: BestEffortFIFO or StrictFIFO with priorities

### 7. **Resource Borrowing**
- **Mainframe**: Discretionary workload uses idle resources
- **Kueue**: Borrowing within cohort

### 8. **Accounting and Monitoring**
- **Mainframe**: SMF records track everything
- **Kueue**: Prometheus metrics and events

---

## What's Different?

| **Aspect** | **Mainframe** | **Kueue** |
|------------|---------------|-----------|
| **Scale** | Single large system | Distributed microservices |
| **Granularity** | Job steps, heavyweight | Pods, lightweight containers |
| **Elasticity** | Fixed resources (LPAR) | Dynamic scaling (cloud) |
| **Heterogeneity** | Homogeneous processors | Mixed node types (CPU, GPU, spot) |
| **Networking** | Internal channels | Distributed network |
| **Storage** | DASD, tape | Distributed storage (PV, S3) |
| **Language** | JCL (procedural) | YAML (declarative) |
| **Evolution** | 50+ years refinement | Modern cloud-native (5 years) |

---

## Why the Similarity?

### **Proven Batch Processing Principles**

The mainframe solved batch workload management problems **decades ago**:

1. ✅ **Queue jobs when resources exhausted**
   - Don't let jobs fail due to capacity
   - Provide visibility into wait time

2. ✅ **Fair share resources across tenants**
   - Prevent resource hogging
   - Guarantee minimum allocations

3. ✅ **Priority-based scheduling**
   - Critical work gets resources first
   - Preempt lower priority when needed

4. ✅ **Separate logical quota from physical capacity**
   - Prevent oversubscription
   - Enable capacity planning

5. ✅ **Dynamic resource allocation**
   - Adapt to changing workload
   - Maximize utilization

6. ✅ **Multi-system workload distribution**
   - Balance load across systems
   - Provide high availability

### **Cloud-Native Adaptation**

Kueue brings these proven concepts to Kubernetes:
- Modern declarative API (YAML vs JCL)
- Cloud elasticity (scale nodes dynamically)
- Container-based execution
- Open source and extensible
- Multi-cloud and hybrid support

---

## Mainframe Concepts Not (Yet) in Kueue

Some advanced mainframe features that could inspire Kueue enhancements:

| **Mainframe Feature** | **Description** | **Kueue Status** |
|----------------------|-----------------|-----------------|
| **Automatic Service Class Adjustment** | WLM automatically adjusts service class based on performance | ❌ Manual configuration only |
| **Response Time Goals** | "90% of transactions complete in < 2 seconds" | ❌ No goal-based admission |
| **Velocity Goals** | "Maximize throughput" with dynamic priority | ⚠️ Partial (fairSharing) |
| **Discretionary Goals** | "Use whatever is left over" | ✅ borrowingLimit |
| **Policy-Based Automation** | Automatic policy changes based on time/conditions | ❌ Manual policy updates |
| **Sysplex-wide Enclaves** | CPU reservations across systems | ❌ Single cluster focus |
| **Job Dependencies (JCL COND)** | Wait for previous job completion | ⚠️ Requires external tool (Argo, Airflow) |
| **Automatic Restart** | System-managed restart on failure | ⚠️ Kubernetes Job controller |
| **SMF Detailed Accounting** | Every CPU second accounted | ⚠️ Prometheus metrics (less granular) |

---

## Real-World Example: Side-by-Side

### **Scenario: Run Weekly Payroll (High Priority) and Backups (Low Priority)**

#### **Mainframe Approach**
```jcl
// ────────────────────────────────────────────
// High Priority Payroll
// ────────────────────────────────────────────
//PAYROLL  JOB (PROD),'PAYROLL',
//         CLASS=A,              ← Highest priority
//         MSGCLASS=X,
//         TIME=30,
//         REGION=16M
//STEP1    EXEC PGM=PAY001
//SYSPRINT DD SYSOUT=*
//INPUT    DD DSN=PAY.INPUT,DISP=SHR
//OUTPUT   DD DSN=PAY.OUTPUT,DISP=(NEW,CATLG)

// ────────────────────────────────────────────
// Low Priority Backup
// ────────────────────────────────────────────
//BACKUP   JOB (BATCH),'BACKUP',
//         CLASS=C,              ← Lower priority
//         MSGCLASS=X,
//         TIME=480
//STEP1    EXEC PGM=BACKUP01
//TAPE     DD DSN=BACKUP.TAPE,
//            DISP=(NEW,KEEP),
//            UNIT=TAPE

WLM Behavior:
1. Both jobs submitted
2. PAYROLL (Class A) gets resources first
3. BACKUP (Class C) runs if resources available
4. If PAYROLL submitted while BACKUP running:
   - WLM raises PAYROLL priority
   - Can preempt BACKUP if needed
   - BACKUP re-queued
```

#### **Kueue Approach**
```yaml
# ────────────────────────────────────────────
# High Priority Payroll
# ────────────────────────────────────────────
apiVersion: batch/v1
kind: Job
metadata:
  name: payroll
  namespace: finance
  labels:
    kueue.x-k8s.io/queue-name: production-queue
    kueue.x-k8s.io/priority-class: high-priority
spec:
  activeDeadlineSeconds: 1800  # 30 minutes
  suspend: true
  template:
    spec:
      containers:
      - name: payroll
        image: payroll:v1
        resources:
          requests:
            cpu: "4"
            memory: "16Gi"
      restartPolicy: Never

---
# ────────────────────────────────────────────
# Low Priority Backup
# ────────────────────────────────────────────
apiVersion: batch/v1
kind: Job
metadata:
  name: backup
  namespace: operations
  labels:
    kueue.x-k8s.io/queue-name: batch-queue
    kueue.x-k8s.io/priority-class: low-priority
spec:
  activeDeadlineSeconds: 28800  # 8 hours
  suspend: true
  template:
    spec:
      containers:
      - name: backup
        image: backup:v1
        resources:
          requests:
            cpu: "2"
            memory: "8Gi"
      restartPolicy: Never

---
# ClusterQueue with preemption enabled
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: cluster-queue
spec:
  preemption:
    withinClusterQueue: LowerPriority
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 10

Kueue Behavior:
1. Both jobs submitted
2. PAYROLL (high-priority) admitted first if quota available
3. BACKUP (low-priority) admitted if remaining quota
4. If PAYROLL submitted while BACKUP running and no quota:
   - Kueue preempts BACKUP (deletes pods)
   - PAYROLL admitted immediately
   - BACKUP re-queued
```

**Result: Nearly Identical Behavior!**

---

## Conclusion

**Your observation is spot-on!** Kueue is essentially a **cloud-native reimplementation of mainframe batch systems** (JES2/JES3 + WLM) for Kubernetes environments. The architectural patterns, resource management principles, and fair sharing concepts are remarkably similar.

### **Why Reinvent the Wheel?**

The mainframe solved these problems 50+ years ago because they are **fundamental to batch workload management**:
- Limited resources
- Multiple competing users
- Need for fairness
- Priority requirements
- Efficient utilization

### **Modern Context:**

Kueue brings these proven patterns to the **cloud-native world**:
- ✅ Kubernetes-native (YAML, CRDs, controllers)
- ✅ Distributed and scalable
- ✅ Container-based workloads
- ✅ Multi-cloud support
- ✅ Open source
- ✅ Declarative management

### **The Circle of Innovation:**

```
1960s-1970s: Mainframe batch systems invented
             (JES, WLM, job classes, initiators)
                      ↓
2000s-2010s: Cloud computing emerges
             (Initial chaos, no workload management)
                      ↓
2020s:       Kubernetes becomes standard
             (Need batch management again!)
                      ↓
             Kueue: Modern implementation
             of proven mainframe concepts
```

**Lesson:** The best ideas never die—they get modernized and adapted to new platforms! 🎯

---

## Further Reading

### Mainframe Resources:
- [IBM z/OS JES2 Introduction](https://www.ibm.com/docs/en/zos/2.4.0?topic=introduction-jes2-overview)
- [IBM Workload Manager (WLM)](https://www.ibm.com/docs/en/zos/2.4.0?topic=introduction-workload-manager)
- [JCL Reference](https://www.ibm.com/docs/en/zos/2.4.0?topic=jcl-introduction)

### Kueue Resources:
- [Kueue Official Documentation](https://kueue.sigs.k8s.io/docs/)
- [Kueue GitHub Repository](https://github.com/kubernetes-sigs/kueue)
- [Fair Sharing Concepts](https://kueue.sigs.k8s.io/docs/concepts/fair_sharing/)
- [MultiKueue Architecture](https://kueue.sigs.k8s.io/docs/concepts/multikueue/)
