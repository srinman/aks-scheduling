# Kueue vs Hadoop Ecosystem - Architecture Comparison

## Executive Summary

Kueue's architecture shares significant similarities with Hadoop's resource management and scheduling ecosystem, particularly **YARN** (Yet Another Resource Negotiator), **Capacity Scheduler**, **Fair Scheduler**, and **MapReduce**. Both systems manage distributed workloads, enforce quotas, provide multi-tenancy, and implement fair sharing across competing users.

This document compares Kueue with Hadoop's big data processing frameworks to understand the architectural parallels and differences.

---

## Side-by-Side Comparison

| **Hadoop Concept** | **Kueue Equivalent** | **Purpose** |
|-------------------|---------------------|-------------|
| **YARN ResourceManager** | **Kueue Controller** | Central coordinator for resource allocation |
| **YARN NodeManager** | **Kubelet** | Agent on each node managing resources |
| **Application Master** | **Job Controller** | Manages lifecycle of individual job |
| **Container** | **Pod** | Unit of execution with resource allocation |
| **Queue (Capacity/Fair)** | **LocalQueue + ClusterQueue** | Organize and prioritize workloads |
| **Capacity Scheduler** | **ClusterQueue with nominalQuota** | Guaranteed capacity per queue |
| **Fair Scheduler** | **ClusterQueue with fairSharing** | Proportional resource sharing |
| **Preemption** | **ClusterQueue preemption policy** | Reclaim resources for high priority |
| **Resource Pool** | **ResourceFlavor** | Logical grouping of resources |
| **Label-based Scheduling** | **NodeSelector + ResourceFlavor** | Direct work to specific nodes |
| **DominantResourceFairness (DRF)** | **Multi-resource quota (CPU+Memory)** | Fair sharing across resource types |
| **MapReduce Job** | **Kubernetes Job** | Batch job definition |
| **Spark Application** | **Job with multiple pods** | Distributed processing job |
| **Job Submission** | **kubectl apply** | How users submit work |
| **ACLs (Access Control Lists)** | **RBAC + Namespaces** | Security and authorization |
| **Queue Hierarchy** | **Cohort with multiple ClusterQueues** | Nested resource organization |
| **Elasticity** | **borrowingLimit** | Use idle capacity from other queues |
| **Max Capacity** | **nominalQuota + borrowingLimit** | Maximum resources a queue can use |
| **Federation** | **MultiKueue** | Multiple clusters sharing workload |

---

## Detailed Architectural Comparison

### 1. Resource Manager: YARN ↔ Kueue Controller

#### **Hadoop: YARN ResourceManager**

```
┌─────────────────────────────────────────────────┐
│         YARN ResourceManager                    │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │  ApplicationsManager                      │ │
│  │  • Accepts application submissions        │ │
│  │  • Assigns ApplicationMaster container    │ │
│  │  • Tracks application lifecycle           │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │  Scheduler (Capacity/Fair/FIFO)           │ │
│  │  • Allocates resources to applications    │ │
│  │  • Enforces queue capacities              │ │
│  │  • Handles preemption                     │ │
│  │  • Manages elasticity                     │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │  Resource Tracker                         │ │
│  │  • Monitors NodeManager health            │ │
│  │  • Tracks available resources per node    │ │
│  │  • Handles node failures                  │ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

#### **Kueue: Controller**

```
┌─────────────────────────────────────────────────┐
│         Kueue Controller                        │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │  Job Watcher                              │ │
│  │  • Watches for new Jobs                   │ │
│  │  • Creates Workload objects               │ │
│  │  • Tracks job lifecycle                   │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │  Queue Manager                            │ │
│  │  • Manages LocalQueues and ClusterQueues  │ │
│  │  • Enforces quota limits                  │ │
│  │  • Handles preemption                     │ │
│  │  • Manages borrowing/lending              │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │  Admission Controller                     │ │
│  │  • Decides when to admit workloads        │ │
│  │  • Reserves quota in ClusterQueue         │ │
│  │  • Unsuspends jobs when admitted          │ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

**Key Similarities:**
- Both are central coordinators for resource allocation
- Both track available resources across the cluster
- Both enforce queue policies and quotas
- Both handle job lifecycle management
- Both support preemption for resource reclamation

**Key Differences:**
- YARN manages containers directly; Kueue works with Kubernetes scheduler
- YARN has ApplicationMaster per job; Kubernetes has Job controller
- YARN is monolithic; Kueue is Kubernetes-native (CRDs, controllers)

---

### 2. Queue Systems: Capacity/Fair Scheduler ↔ ClusterQueue

#### **Hadoop: Capacity Scheduler Configuration**

```xml
<configuration>
  <!-- Root Queue -->
  <property>
    <name>yarn.scheduler.capacity.root.queues</name>
    <value>production,engineering,marketing</value>
  </property>
  
  <!-- Production Queue (40% capacity) -->
  <property>
    <name>yarn.scheduler.capacity.root.production.capacity</name>
    <value>40</value>
  </property>
  <property>
    <name>yarn.scheduler.capacity.root.production.maximum-capacity</name>
    <value>70</value>  <!-- Can grow to 70% -->
  </property>
  <property>
    <name>yarn.scheduler.capacity.root.production.user-limit-factor</name>
    <value>2</value>
  </property>
  
  <!-- Engineering Queue (35% capacity) -->
  <property>
    <name>yarn.scheduler.capacity.root.engineering.capacity</name>
    <value>35</value>
  </property>
  <property>
    <name>yarn.scheduler.capacity.root.engineering.maximum-capacity</name>
    <value>80</value>
  </property>
  
  <!-- Marketing Queue (25% capacity) -->
  <property>
    <name>yarn.scheduler.capacity.root.marketing.capacity</name>
    <value>25</value>
  </property>
  <property>
    <name>yarn.scheduler.capacity.root.marketing.maximum-capacity</name>
    <value>50</value>
  </property>
  
  <!-- Enable Preemption -->
  <property>
    <name>yarn.resourcemanager.scheduler.monitor.enable</name>
    <value>true</value>
  </property>
  <property>
    <name>yarn.resourcemanager.scheduler.monitor.policies</name>
    <value>org.apache.hadoop.yarn.server.resourcemanager.monitor.capacity.ProportionalCapacityPreemptionPolicy</value>
  </property>
</configuration>
```

#### **Kueue: ClusterQueue Configuration**

```yaml
# Production ClusterQueue (40% = 40 CPUs out of 100 total)
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: production-cq
spec:
  cohort: company-wide
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
        nominalQuota: 40          # Guaranteed: 40%
        borrowingLimit: 30        # Can grow to 70 CPUs (40+30)
      - name: memory
        nominalQuota: 160Gi

---
# Engineering ClusterQueue (35% = 35 CPUs)
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: engineering-cq
spec:
  cohort: company-wide
  preemption:
    reclaimWithinCohort: Any
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 35
        borrowingLimit: 45        # Can grow to 80 CPUs
      - name: memory
        nominalQuota: 140Gi

---
# Marketing ClusterQueue (25% = 25 CPUs)
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: marketing-cq
spec:
  cohort: company-wide
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 25
        borrowingLimit: 25        # Can grow to 50 CPUs
      - name: memory
        nominalQuota: 100Gi

---
# LocalQueues map to ClusterQueues
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: prod-queue
  namespace: production
spec:
  clusterQueue: production-cq

---
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: eng-queue
  namespace: engineering
spec:
  clusterQueue: engineering-cq

---
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: mktg-queue
  namespace: marketing
spec:
  clusterQueue: marketing-cq
```

**Capacity Mapping:**

| **YARN Concept** | **Kueue Equivalent** | **Example** |
|------------------|---------------------|-------------|
| `capacity` | `nominalQuota` | Guaranteed 40% |
| `maximum-capacity` | `nominalQuota + borrowingLimit` | Can grow to 70% |
| Queue elasticity | `borrowingLimit` | Borrow from idle queues |
| Preemption | `preemption.reclaimWithinCohort` | Reclaim borrowed resources |
| Queue hierarchy | `cohort` | Group queues for sharing |

---

### 3. Fair Scheduler: Hadoop ↔ Kueue Fair Sharing

#### **Hadoop: Fair Scheduler Configuration**

```xml
<allocations>
  <!-- Pool for Production workloads -->
  <pool name="production">
    <minResources>10240 mb, 10 vcores</minResources>
    <maxResources>40960 mb, 40 vcores</maxResources>
    <maxRunningApps>50</maxRunningApps>
    <weight>3.0</weight>                    <!-- 3x weight -->
    <schedulingPolicy>fair</schedulingPolicy>
    <aclSubmitApps>prod_users</aclSubmitApps>
  </pool>
  
  <!-- Pool for Engineering workloads -->
  <pool name="engineering">
    <minResources>8192 mb, 8 vcores</minResources>
    <maxResources>30720 mb, 30 vcores</maxResources>
    <weight>2.0</weight>                    <!-- 2x weight -->
    <schedulingPolicy>fair</schedulingPolicy>
  </pool>
  
  <!-- Pool for Ad-hoc queries -->
  <pool name="adhoc">
    <minResources>2048 mb, 2 vcores</minResources>
    <maxResources>10240 mb, 10 vcores</maxResources>
    <weight>1.0</weight>                    <!-- 1x weight -->
    <schedulingPolicy>fifo</schedulingPolicy>
  </pool>
  
  <!-- Default pool -->
  <pool name="default">
    <weight>1.0</weight>
  </pool>
  
  <!-- Fair Share Preemption -->
  <fairSharePreemptionEnabled>true</fairSharePreemptionEnabled>
  <fairSharePreemptionThreshold>0.5</fairSharePreemptionThreshold>
</allocations>
```

#### **Kueue: Fair Sharing with Weights**

```yaml
# Production ClusterQueue (3x weight)
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: production-cq
spec:
  cohort: company-wide
  fairSharing:
    weight: 3.0                    # 3x fair share weight
  preemption:
    reclaimWithinCohort: Any
    withinClusterQueue: LowerPriority
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 40          # Minimum guarantee
      - name: memory
        nominalQuota: 160Gi

---
# Engineering ClusterQueue (2x weight)
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: engineering-cq
spec:
  cohort: company-wide
  fairSharing:
    weight: 2.0                    # 2x fair share weight
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 30
      - name: memory
        nominalQuota: 120Gi

---
# Ad-hoc ClusterQueue (1x weight, FIFO)
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: adhoc-cq
spec:
  cohort: company-wide
  queueingStrategy: StrictFIFO     # Like FIFO in Hadoop
  fairSharing:
    weight: 1.0                    # 1x fair share weight
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 10
      - name: memory
        nominalQuota: 40Gi
```

**Fair Sharing Behavior:**

Both systems:
- Track resource usage over time per queue/pool
- Allocate resources proportional to weights when contended
- Allow queues to exceed fair share when others are idle
- Preempt to restore fair share when queue falls below threshold
- Guarantee minimum resources (minResources / nominalQuota)

**Example Calculation:**
```
Total CPUs: 100
Production weight: 3.0
Engineering weight: 2.0
Ad-hoc weight: 1.0
Total weight: 6.0

Fair share allocation:
- Production: 100 * (3.0/6.0) = 50 CPUs
- Engineering: 100 * (2.0/6.0) = 33 CPUs
- Ad-hoc: 100 * (1.0/6.0) = 17 CPUs
```

---

### 4. Job Submission: MapReduce/Spark ↔ Kubernetes Job

#### **Hadoop: MapReduce Job Submission**

```java
// MapReduce job configuration
Configuration conf = new Configuration();
Job job = Job.getInstance(conf, "word count");

// Set queue
job.setQueueName("production");

// Resource requirements
job.getConfiguration().set("mapreduce.map.memory.mb", "2048");
job.getConfiguration().set("mapreduce.map.cpu.vcores", "2");
job.getConfiguration().set("mapreduce.reduce.memory.mb", "4096");
job.getConfiguration().set("mapreduce.reduce.cpu.vcores", "4");

// Job configuration
job.setJarByClass(WordCount.class);
job.setMapperClass(TokenizerMapper.class);
job.setCombinerClass(IntSumReducer.class);
job.setReducerClass(IntSumReducer.class);
job.setNumReduceTasks(10);

// Submit
job.submit();
```

**Spark on YARN:**
```bash
spark-submit \
  --master yarn \
  --deploy-mode cluster \
  --queue production \
  --num-executors 50 \
  --executor-cores 4 \
  --executor-memory 8G \
  --driver-memory 4G \
  --conf spark.yarn.submit.waitAppCompletion=true \
  wordcount.py
```

#### **Kueue: Kubernetes Job Submission**

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: word-count
  namespace: production
  labels:
    kueue.x-k8s.io/queue-name: prod-queue
    kueue.x-k8s.io/priority-class: high-priority
spec:
  parallelism: 50                    # Like num-executors
  completions: 50
  suspend: true                      # Kueue controls execution
  template:
    metadata:
      labels:
        app: word-count
    spec:
      containers:
      - name: worker
        image: spark:3.5
        command: ["spark-submit"]
        args:
          - "--master"
          - "k8s://https://kubernetes.default.svc"
          - "wordcount.py"
        resources:
          requests:
            cpu: "4"                 # Like executor-cores
            memory: "8Gi"            # Like executor-memory
          limits:
            cpu: "4"
            memory: "8Gi"
      restartPolicy: Never
```

**Alternative: Spark Operator with Kueue:**
```yaml
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: word-count-spark
  namespace: production
  labels:
    kueue.x-k8s.io/queue-name: prod-queue
spec:
  type: Python
  mode: cluster
  image: spark:3.5
  mainApplicationFile: local:///opt/spark/work-dir/wordcount.py
  sparkVersion: 3.5.0
  driver:
    cores: 2
    memory: "4Gi"
    serviceAccount: spark
  executor:
    instances: 50
    cores: 4
    memory: "8Gi"
  batchScheduler: kueue              # Use Kueue for scheduling
```

---

### 5. Resource Allocation Flow

#### **Hadoop YARN: Application Lifecycle**

```
1. Client submits application to ResourceManager
         ↓
2. RM allocates container for ApplicationMaster (AM)
         ↓
3. AM registers with RM
         ↓
4. AM requests containers for tasks
         ↓
5. RM's Scheduler allocates containers based on:
   • Queue capacity
   • Available resources
   • Fair share / priority
         ↓
6. NodeManager launches containers
         ↓
7. Tasks execute
         ↓
8. AM monitors task progress
         ↓
9. AM releases containers as tasks complete
         ↓
10. AM unregisters, application completes
```

#### **Kueue: Job Lifecycle**

```
1. User submits Job (suspended) to Kubernetes
         ↓
2. Kueue Controller creates Workload object
         ↓
3. Workload queued in LocalQueue
         ↓
4. Kueue checks ClusterQueue quota
         ↓
5. If quota available:
   • Workload admitted
   • Quota reserved in ClusterQueue
   • Job unsuspended
         ↓
6. Kubernetes Job Controller creates Pods
         ↓
7. Kubernetes Scheduler places Pods on Nodes
         ↓
8. Kubelet starts containers
         ↓
9. Job executes
         ↓
10. Pods complete
         ↓
11. Kueue releases quota
         ↓
12. Workload marked finished
```

**Key Parallel:**
- YARN AM requests containers → Kueue reserves quota for Job
- YARN Scheduler allocates → Kueue admits workload
- NodeManager launches → Kubernetes Scheduler places pods
- Both track lifecycle from submission to completion

---

### 6. Preemption Mechanisms

#### **Hadoop: Capacity Scheduler Preemption**

```xml
<property>
  <name>yarn.resourcemanager.scheduler.monitor.enable</name>
  <value>true</value>
</property>

<property>
  <name>yarn.resourcemanager.scheduler.monitor.policies</name>
  <value>org.apache.hadoop.yarn.server.resourcemanager.monitor.capacity.ProportionalCapacityPreemptionPolicy</value>
</property>

<!-- Preemption threshold -->
<property>
  <name>yarn.resourcemanager.monitor.capacity.preemption.observe_only</name>
  <value>false</value>
</property>

<!-- Max percentage that can be preempted per round -->
<property>
  <name>yarn.resourcemanager.monitor.capacity.preemption.max_total_preemption_per_round</name>
  <value>0.1</value>  <!-- 10% per round -->
</property>
```

**Scenario:**
```
Production queue: capacity=40%, currently using 20%
Engineering queue: capacity=35%, currently using 60% (borrowed)

Production job submitted needing 30%
→ Engineering is over capacity and production is under
→ Preempt 10% of containers from engineering
→ Allocate freed resources to production
```

#### **Kueue: ClusterQueue Preemption**

```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: production-cq
spec:
  cohort: company-wide
  preemption:
    withinClusterQueue: LowerPriority
    reclaimWithinCohort: Any          # Can reclaim borrowed resources
    borrowWithinCohort:
      policy: LowerPriority
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 40
        borrowingLimit: 30

---
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: engineering-cq
spec:
  cohort: company-wide
  preemption:
    reclaimWithinCohort: Never        # Can be preempted
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 35
        borrowingLimit: 45
```

**Scenario:**
```
Production CQ: nominalQuota=40, currently using 20
Engineering CQ: nominalQuota=35, currently using 60 (borrowed 25)

Production high-priority job submitted needing 30 CPUs
→ Engineering is borrowing and production needs resources
→ Kueue preempts engineering workload (deletes pods)
→ Engineering workload re-queued
→ Production workload admitted with 30 CPUs
```

**Comparison:**

| **Feature** | **Hadoop YARN** | **Kueue** |
|-------------|-----------------|-----------|
| Preemption unit | Container | Pod (entire workload) |
| Gradual preemption | Yes (10% per round) | No (entire workload) |
| Re-queue preempted | Yes, automatically | Yes, automatically |
| Preemption triggers | Queue under capacity | Priority or reclaim |
| Grace period | Configurable | Based on pod termination |

---

### 7. Multi-Resource Fairness: DRF

#### **Hadoop: Dominant Resource Fairness (DRF)**

```
Cluster: 100 CPUs, 400GB RAM

User A: Runs CPU-heavy jobs
  - Job needs: 2 CPUs, 1GB RAM per task
  - Dominant resource: CPU (2% of cluster)

User B: Runs memory-heavy jobs
  - Job needs: 0.5 CPUs, 10GB RAM per task
  - Dominant resource: Memory (2.5% of cluster)

Fair Scheduler with DRF:
• Equalizes dominant resource share across users
• User A gets ~50 tasks (100 CPUs, 50GB)
• User B gets ~40 tasks (20 CPUs, 400GB)
• Each user's dominant resource ≈ 50% of cluster
```

#### **Kueue: Multi-Resource Quota**

```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: shared-cq
spec:
  fairSharing:
    weight: 1.0
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 100
      - name: memory
        nominalQuota: 400Gi

---
# CPU-heavy job (like User A)
apiVersion: batch/v1
kind: Job
metadata:
  name: cpu-heavy
  labels:
    kueue.x-k8s.io/queue-name: shared-queue
spec:
  parallelism: 50
  suspend: true
  template:
    spec:
      containers:
      - name: worker
        resources:
          requests:
            cpu: "2"              # Dominant: CPU
            memory: "1Gi"

---
# Memory-heavy job (like User B)
apiVersion: batch/v1
kind: Job
metadata:
  name: memory-heavy
  labels:
    kueue.x-k8s.io/queue-name: shared-queue
spec:
  parallelism: 40
  suspend: true
  template:
    spec:
      containers:
      - name: worker
        resources:
          requests:
            cpu: "500m"           # 0.5 CPU
            memory: "10Gi"        # Dominant: Memory
```

**Kueue's Approach:**
- Tracks CPU and memory usage separately
- Admits workloads if **both** resources are available
- Fair sharing applies to both dimensions
- No explicit DRF algorithm (relies on quota enforcement)

**Key Difference:**
- YARN DRF: Sophisticated multi-resource fairness algorithm
- Kueue: Simple multi-resource quota tracking
- YARN is more advanced for heterogeneous workloads

---

### 8. Label-Based Scheduling

#### **Hadoop: Node Labels**

```xml
<!-- Configure node labels -->
<property>
  <name>yarn.node-labels.enabled</name>
  <value>true</value>
</property>

<property>
  <name>yarn.node-labels.fs-store.root-dir</name>
  <value>hdfs://namenode:8020/yarn/node-labels</value>
</property>
```

**Assign labels to nodes:**
```bash
yarn rmadmin -addToClusterNodeLabels "GPU,SSD,HIGHMEM"
yarn rmadmin -replaceLabelsOnNode "node1=GPU,SSD"
yarn rmadmin -replaceLabelsOnNode "node2=HIGHMEM"
```

**Queue with label access:**
```xml
<property>
  <name>yarn.scheduler.capacity.root.gpu-queue.accessible-node-labels</name>
  <value>GPU</value>
</property>

<property>
  <name>yarn.scheduler.capacity.root.gpu-queue.accessible-node-labels.GPU.capacity</name>
  <value>100</value>
</property>
```

**Job requesting GPU nodes:**
```java
ApplicationSubmissionContext appContext = ...;
ResourceRequest request = ResourceRequest.newInstance(
    Priority.newInstance(1),
    "*",  // Any host
    Resource.newInstance(4096, 2),
    1,    // Number of containers
    true,
    "GPU" // Node label expression
);
```

#### **Kueue: ResourceFlavor with Node Selectors**

```yaml
# GPU ResourceFlavor
apiVersion: kueue.x-k8s.io/v1beta1
kind: ResourceFlavor
metadata:
  name: gpu-flavor
nodeLabels:
  accelerator: nvidia-tesla-v100
  disktype: ssd
nodeSelector:
  workload-type: gpu
tolerations:
- key: nvidia.com/gpu
  operator: Equal
  value: "true"
  effect: NoSchedule

---
# High Memory ResourceFlavor
apiVersion: kueue.x-k8s.io/v1beta1
kind: ResourceFlavor
metadata:
  name: highmem-flavor
nodeLabels:
  memory-class: high
nodeSelector:
  node-type: memory-optimized

---
# ClusterQueue with multiple flavors
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: ml-training-cq
spec:
  namespaceSelector: {}
  resourceGroups:
  - coveredResources: ["cpu", "memory", "nvidia.com/gpu"]
    flavors:
    - name: gpu-flavor
      resources:
      - name: cpu
        nominalQuota: 32
      - name: memory
        nominalQuota: 128Gi
      - name: nvidia.com/gpu
        nominalQuota: 8
    - name: highmem-flavor    # Fallback if GPU unavailable
      resources:
      - name: cpu
        nominalQuota: 64
      - name: memory
        nominalQuota: 512Gi

---
# Job requesting GPU resources
apiVersion: batch/v1
kind: Job
metadata:
  name: gpu-training
  labels:
    kueue.x-k8s.io/queue-name: ml-queue
spec:
  suspend: true
  template:
    spec:
      containers:
      - name: trainer
        image: tensorflow/tensorflow:latest-gpu
        resources:
          requests:
            cpu: "4"
            memory: "16Gi"
            nvidia.com/gpu: "1"  # Request GPU
          limits:
            nvidia.com/gpu: "1"
      restartPolicy: Never
```

**Comparison:**

| **Feature** | **Hadoop Node Labels** | **Kueue ResourceFlavor** |
|-------------|----------------------|-------------------------|
| Purpose | Direct work to specific nodes | Direct work to specific nodes |
| Configuration | XML + CLI commands | Kubernetes CRDs (YAML) |
| Flexibility | Labels on nodes | Labels, selectors, taints, tolerations |
| Queue mapping | Queue → Label access | ClusterQueue → Flavor |
| Fallback | Manual configuration | FlavorFungibility (automatic) |
| Resource types | Memory, CPU, custom | CPU, Memory, GPUs, custom resources |

---

### 9. Federation: Hadoop Federation ↔ MultiKueue

#### **Hadoop: YARN Federation**

```
┌─────────────────────────────────────────────────────┐
│           YARN Federation                           │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │  Router (AMRMProxy)                         │   │
│  │  • Receives job submissions                 │   │
│  │  • Routes to appropriate sub-cluster        │   │
│  │  • Implements policies (random, locality)   │   │
│  └─────────────────┬───────────────────────────┘   │
│                    │                               │
│       ┌────────────┼────────────┐                  │
│       │            │            │                  │
│  ┌────▼─────┐ ┌───▼──────┐ ┌──▼───────┐          │
│  │SubCluster│ │SubCluster│ │SubCluster│          │
│  │    A     │ │    B     │ │    C     │          │
│  │          │ │          │ │          │          │
│  │RM + YARN │ │RM + YARN │ │RM + YARN │          │
│  │Nodes     │ │Nodes     │ │Nodes     │          │
│  └──────────┘ └──────────┘ └──────────┘          │
│                                                     │
│  Features:                                         │
│  • Independent sub-clusters                        │
│  • Policy-based routing                            │
│  • Transparent to applications                     │
│  • State stored in shared store (ZooKeeper)        │
└─────────────────────────────────────────────────────┘
```

#### **Kueue: MultiKueue**

```
┌─────────────────────────────────────────────────────┐
│         MultiKueue Architecture                     │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │  Management Cluster (Control Plane)         │   │
│  │                                             │   │
│  │  MultiKueue Controller:                     │   │
│  │  • Accepts job submissions                  │   │
│  │  • Checks capacity across clusters          │   │
│  │  • Selects best cluster                     │   │
│  │  • Monitors job execution remotely          │   │
│  └─────────────────┬───────────────────────────┘   │
│                    │                               │
│       ┌────────────┼────────────┐                  │
│       │            │            │                  │
│  ┌────▼─────┐ ┌───▼──────┐ ┌──▼───────┐          │
│  │ Worker   │ │ Worker   │ │ Worker   │          │
│  │Cluster-A │ │Cluster-B │ │Cluster-C │          │
│  │ (AKS)    │ │ (EKS)    │ │ (GKE)    │          │
│  │          │ │          │ │          │          │
│  │Kueue     │ │Kueue     │ │Kueue     │          │
│  │Local     │ │Local     │ │Local     │          │
│  └──────────┘ └──────────┘ └──────────┘          │
│                                                     │
│  Features:                                         │
│  • Multi-cloud support                             │
│  • Capacity-based routing                          │
│  • Job monitoring from management cluster          │
│  • Automatic failover                              │
└─────────────────────────────────────────────────────┘
```

**Configuration:**

```yaml
# MultiKueue Config (Management Cluster)
apiVersion: kueue.x-k8s.io/v1alpha1
kind: MultiKueueCluster
metadata:
  name: worker-cluster-a
spec:
  kubeconfig:
    location: Secret
    locationName: worker-a-kubeconfig

---
apiVersion: kueue.x-k8s.io/v1alpha1
kind: MultiKueueCluster
metadata:
  name: worker-cluster-b
spec:
  kubeconfig:
    location: Secret
    locationName: worker-b-kubeconfig

---
# ClusterQueue with MultiKueue
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: multikueue-cq
spec:
  queueingStrategy: BestEffortFIFO
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 100
```

**Comparison:**

| **Feature** | **Hadoop Federation** | **MultiKueue** |
|-------------|----------------------|----------------|
| Purpose | Scale beyond single RM | Multi-cluster workload distribution |
| Routing | Policy-based (random, hash, locality) | Capacity-based (admits where quota available) |
| Sub-cluster independence | Yes | Yes |
| Transparency | Yes (via Router) | Yes (via management cluster) |
| State management | ZooKeeper | Kubernetes API server |
| Cross-cloud | No (single Hadoop deployment) | Yes (AKS, EKS, GKE, on-prem) |

---

### 10. Resource Isolation and Multi-Tenancy

#### **Hadoop: Queue ACLs and User Limits**

```xml
<!-- Queue ACLs -->
<property>
  <name>yarn.scheduler.capacity.root.production.acl_submit_applications</name>
  <value>prod_users,prod_admins</value>
</property>

<property>
  <name>yarn.scheduler.capacity.root.production.acl_administer_queue</name>
  <value>prod_admins</value>
</property>

<!-- User limits -->
<property>
  <name>yarn.scheduler.capacity.root.production.minimum-user-limit-percent</name>
  <value>25</value>  <!-- Each user guaranteed 25% of queue -->
</property>

<property>
  <name>yarn.scheduler.capacity.root.production.user-limit-factor</name>
  <value>2</value>  <!-- User can grow to 200% of user limit -->
</property>

<!-- Maximum applications per user per queue -->
<property>
  <name>yarn.scheduler.capacity.root.production.maximum-applications-per-user</name>
  <value>100</value>
</property>
```

#### **Kueue: RBAC and Namespaces**

```yaml
# Namespace for production team
apiVersion: v1
kind: Namespace
metadata:
  name: production

---
# RBAC: Who can submit jobs
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: job-submitter
  namespace: production
rules:
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["create", "get", "list", "delete"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: prod-users-binding
  namespace: production
subjects:
- kind: Group
  name: prod-users
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: job-submitter
  apiGroup: rbac.authorization.k8s.io

---
# LocalQueue for production namespace
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: prod-queue
  namespace: production
spec:
  clusterQueue: production-cq

---
# ResourceQuota (Kubernetes-native limit)
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "100"
    requests.memory: "400Gi"
    pods: "500"
    jobs.batch: "100"  # Max 100 jobs per namespace
```

**Comparison:**

| **Isolation Mechanism** | **Hadoop** | **Kueue** |
|------------------------|------------|-----------|
| Tenant isolation | Queues | Namespaces |
| Access control | ACLs (XML) | RBAC (Kubernetes) |
| User limits | User limit percent | ResourceQuota per namespace |
| Max apps per user | XML config | ResourceQuota (jobs.batch) |
| Admin permissions | Queue admin ACL | ClusterRole bindings |
| Fine-grained control | Per-queue XML | RBAC policies |

---

## Real-World Scenario: Complete Workflow Comparison

### **Scenario: Data Science Team Running Model Training**

#### **Hadoop Approach (Spark on YARN)**

```bash
# Step 1: User authenticates
kinit data-scientist@COMPANY.COM

# Step 2: Submit Spark job to YARN
spark-submit \
  --master yarn \
  --deploy-mode cluster \
  --queue datascience \                    # Queue assignment
  --num-executors 100 \
  --executor-cores 4 \
  --executor-memory 16G \
  --driver-memory 8G \
  --conf spark.yarn.maxAppAttempts=2 \
  --conf spark.dynamicAllocation.enabled=true \
  --conf spark.shuffle.service.enabled=true \
  --files config.json \
  --py-files dependencies.zip \
  train_model.py

# Step 3: YARN ResourceManager
# - Validates queue access (ACL check)
# - Checks queue capacity
# - If capacity available:
#   → Allocates container for Spark ApplicationMaster
# - If capacity exhausted:
#   → Job queues waiting for resources

# Step 4: ApplicationMaster starts
# - Requests 100 executor containers
# - RM allocates based on available capacity
# - May receive fewer than requested (elastic)

# Step 5: NodeManagers launch executors
# - Containers start on worker nodes
# - Spark driver coordinates computation

# Step 6: Model training runs
# - Shuffle data across executors
# - Checkpoints to HDFS
# - Logs to YARN logs aggregation

# Step 7: Job completes
# - AM releases containers
# - Resources returned to queue
# - Queued jobs can now run

# Monitor job
yarn application -status application_1234567890_0001
yarn logs -applicationId application_1234567890_0001
```

#### **Kueue Approach (Spark on Kubernetes)**

```yaml
# Step 1: User authenticates
# kubectl configured with user identity

# Step 2: Submit SparkApplication with Kueue
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: model-training
  namespace: datascience
  labels:
    kueue.x-k8s.io/queue-name: datascience-queue
    kueue.x-k8s.io/priority-class: medium-priority
spec:
  type: Python
  mode: cluster
  image: spark:3.5-python
  mainApplicationFile: s3://bucket/train_model.py
  sparkVersion: 3.5.0
  
  # Driver configuration
  driver:
    cores: 4
    coreLimit: "4"
    memory: "8Gi"
    labels:
      version: 3.5.0
    serviceAccount: spark
    
  # Executor configuration
  executor:
    instances: 100
    cores: 4
    coreLimit: "4"
    memory: "16Gi"
    labels:
      version: 3.5.0
    
  # Dynamic allocation (elastic)
  dynamicAllocation:
    enabled: true
    initialExecutors: 50
    minExecutors: 10
    maxExecutors: 100
  
  # Kueue will manage suspension
  batchScheduler: kueue
  batchSchedulerOptions:
    queue: datascience-queue

---
# Submit to Kubernetes
kubectl apply -f model-training.yaml

# Step 3: Kueue Controller
# - Creates Workload object
# - Checks ClusterQueue quota
# - Validates namespace RBAC
# - If quota available:
#   → Workload admitted
#   → Reserves quota (400 CPU, 1600Gi)
#   → SparkApplication unsuspended
# - If quota exhausted:
#   → Workload queued

# Step 4: Spark Operator creates pods
# - Driver pod created
# - Executor pods created (100 instances)
# - Kueue ensures quota not exceeded

# Step 5: Kubernetes Scheduler places pods
# - Binds pods to nodes with capacity
# - Respects resource requests/limits
# - Handles pod failures (restarts)

# Step 6: Model training runs
# - Spark driver coordinates
# - Data shuffled between executors
# - Checkpoints to cloud storage (S3/GCS/Azure)
# - Logs to stdout/stderr (collected by logging system)

# Step 7: Job completes
# - Executor pods terminate
# - Driver pod completes
# - Kueue releases quota from ClusterQueue
# - Queued workloads can now be admitted

# Monitor job
kubectl get sparkapplications -n datascience
kubectl get workloads -n datascience
kubectl logs model-training-driver -n datascience
kubectl describe workload job-model-training-xxx -n datascience
```

**Side-by-Side:**

| **Aspect** | **Hadoop/Spark on YARN** | **Kueue/Spark on Kubernetes** |
|------------|-------------------------|------------------------------|
| Submission | `spark-submit` CLI | `kubectl apply` YAML |
| Queue selection | `--queue` flag | `kueue.x-k8s.io/queue-name` label |
| Resource request | CLI flags | Pod resource requests |
| Admission control | YARN Scheduler | Kueue Controller |
| Execution | NodeManager launches containers | Kubelet launches pods |
| Dynamic scaling | YARN dynamic allocation | Kubernetes HPA / Spark dynamic allocation |
| Storage | HDFS | Cloud storage (S3, GCS, Azure Blob) |
| Logging | YARN log aggregation | Kubernetes logging (Fluentd, Loki) |
| Monitoring | YARN UI, Spark UI | Kubernetes Dashboard, Grafana |

---

## Key Similarities

### 1. **Central Resource Management**
- YARN ResourceManager ↔ Kueue Controller
- Both are central coordinators for admission control
- Both enforce quotas and policies

### 2. **Queue-Based Organization**
- YARN queues ↔ LocalQueue + ClusterQueue
- Hierarchical resource organization
- Multi-tenancy support

### 3. **Capacity and Fair Sharing**
- Capacity Scheduler ↔ ClusterQueue nominalQuota
- Fair Scheduler ↔ ClusterQueue fairSharing weights
- Guaranteed minimums with elastic growth

### 4. **Preemption**
- YARN preemption policies ↔ Kueue preemption config
- Reclaim resources for higher priority
- Re-queue preempted workloads

### 5. **Resource Borrowing**
- YARN queue elasticity ↔ Kueue borrowingLimit
- Use idle capacity from other queues
- Return when owner needs resources

### 6. **Label-Based Placement**
- YARN node labels ↔ Kueue ResourceFlavors
- Direct work to specific hardware
- GPU, SSD, high-memory node selection

### 7. **Federation/Multi-Cluster**
- YARN Federation ↔ MultiKueue
- Scale beyond single cluster
- Transparent routing

### 8. **Multi-Tenancy**
- YARN ACLs + user limits ↔ RBAC + Namespaces
- Isolation between teams
- Fair resource allocation

---

## Key Differences

| **Aspect** | **Hadoop/YARN** | **Kueue** |
|------------|-----------------|-----------|
| **Architecture** | Monolithic (RM + NM) | Distributed (Controllers + Scheduler) |
| **Platform** | Hadoop-specific | Kubernetes-native |
| **Execution Unit** | Container (JVM process) | Pod (container group) |
| **Scheduling** | YARN Scheduler does placement | Kueue admits, K8s Scheduler places |
| **Job Types** | MapReduce, Spark, Flink | Any Kubernetes workload (Jobs, Deployments, etc.) |
| **Storage** | HDFS-centric | Cloud-native (S3, PV, etc.) |
| **Configuration** | XML files | Kubernetes CRDs (YAML) |
| **API** | Java APIs | Kubernetes API (kubectl, REST) |
| **Elasticity** | Limited (fixed cluster) | Cloud-native (auto-scale nodes) |
| **Multi-Cloud** | Single Hadoop cluster | Native multi-cloud (AKS, EKS, GKE) |
| **Ecosystem** | Hadoop ecosystem | Cloud-native ecosystem |
| **Maturity** | 15+ years (mature) | 2-3 years (evolving) |

---

## What Kueue Can Learn from Hadoop

Some advanced Hadoop features that could enhance Kueue:

| **Hadoop Feature** | **Current Kueue Status** | **Potential Enhancement** |
|-------------------|-------------------------|--------------------------|
| **Dominant Resource Fairness (DRF)** | ❌ Not implemented | Sophisticated multi-resource fairness |
| **Gradual Preemption** | ❌ All-or-nothing | Preempt percentage per round |
| **Application-level Elasticity** | ⚠️ Requires external controller | YARN-style dynamic container allocation |
| **Historical Usage Tracking** | ❌ Limited | Fair share based on historical usage |
| **Queue Hierarchies** | ⚠️ Flat cohorts | Nested queues with inheritance |
| **Automatic Queue Creation** | ❌ Manual | Dynamic queue per user/project |
| **Per-User Limits** | ❌ Namespace-based only | Finer-grained user quotas |
| **Reservation System** | ❌ Not available | Reserve capacity for future jobs |

---

## Conclusion

Kueue and Hadoop/YARN share fundamental design principles for **distributed resource management** and **workload scheduling**. Both systems solve the same core problems:

1. ✅ **Multi-tenancy**: Isolate and fairly share resources
2. ✅ **Quota enforcement**: Prevent resource exhaustion
3. ✅ **Queueing**: Wait when resources unavailable
4. ✅ **Priority scheduling**: Important work first
5. ✅ **Preemption**: Reclaim resources dynamically
6. ✅ **Elasticity**: Borrow idle resources
7. ✅ **Federation**: Scale across multiple systems

### **Why the Similarity?**

These are **universal patterns** for distributed batch processing:
- YARN solved them for Hadoop (big data processing)
- Kueue solves them for Kubernetes (cloud-native workloads)

### **Modern Context:**

Kueue brings Hadoop's proven concepts to the **cloud-native era**:
- ✅ Kubernetes-native (not Hadoop-specific)
- ✅ Cloud elasticity (scale nodes dynamically)
- ✅ Multi-cloud support (AKS, EKS, GKE)
- ✅ Declarative management (YAML, GitOps)
- ✅ Broader workload types (not just MapReduce/Spark)
- ✅ Modern observability (Prometheus, Grafana)

### **Best of Both Worlds:**

For organizations familiar with Hadoop/YARN, Kueue provides a **familiar mental model** applied to Kubernetes. The concepts translate directly, making adoption easier for teams with big data experience.

**Lesson:** Proven patterns from big data (Hadoop/YARN) are being adapted for cloud-native platforms (Kubernetes/Kueue)! 🚀

---

## Further Reading

### Hadoop/YARN Resources:
- [Apache Hadoop YARN Documentation](https://hadoop.apache.org/docs/current/hadoop-yarn/hadoop-yarn-site/YARN.html)
- [YARN Capacity Scheduler](https://hadoop.apache.org/docs/current/hadoop-yarn/hadoop-yarn-site/CapacityScheduler.html)
- [YARN Fair Scheduler](https://hadoop.apache.org/docs/current/hadoop-yarn/hadoop-yarn-site/FairScheduler.html)
- [Dominant Resource Fairness Paper](https://cs.stanford.edu/~matei/papers/2011/nsdi_drf.pdf)
- [YARN Federation](https://hadoop.apache.org/docs/current/hadoop-yarn/hadoop-yarn-site/Federation.html)

### Kueue Resources:
- [Kueue Official Documentation](https://kueue.sigs.k8s.io/docs/)
- [Kueue GitHub Repository](https://github.com/kubernetes-sigs/kueue)
- [Fair Sharing in Kueue](https://kueue.sigs.k8s.io/docs/concepts/fair_sharing/)
- [MultiKueue Architecture](https://kueue.sigs.k8s.io/docs/concepts/multikueue/)
- [Spark on Kubernetes](https://spark.apache.org/docs/latest/running-on-kubernetes.html)
