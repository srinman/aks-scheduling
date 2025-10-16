# Kueue Simple Demo - Step by Step Guide

## What is Kueue?

Kueue is a Kubernetes-native job queueing system that manages quotas and decides when jobs should:
- **Wait** in a queue
- **Start** (be admitted and create pods)
- **Be preempted** (have pods deleted to make room for higher priority jobs)

### Key Concepts

1. **ResourceFlavor**: Describes available resources (e.g., CPU, GPU types, node pools)
2. **ClusterQueue**: Cluster-wide resource pool with quota limits
3. **LocalQueue**: Namespace-scoped queue that maps to a ClusterQueue
4. **Workload**: A job that needs to run (automatically created when you submit a Job)

### How it Works
```
Job submitted → LocalQueue → ClusterQueue (quota check) → Admitted → Pods created
```

---

## Step 1: Prepare Your AKS Cluster

### Check Current Node Capacity

```bash
# Check current nodes and their capacity
kubectl get nodes
kubectl describe nodes | grep -A 5 "Allocatable"

# Check total cluster capacity
kubectl top nodes
```

### Scale AKS Cluster (If Needed)

For this demo, we recommend having at least **3-4 nodes** with sufficient CPU capacity. If you need to scale your cluster:

```bash
# Get your cluster info
CLUSTER_NAME="democluster"
RESOURCE_GROUP="democlusterrg"
NODE_POOL_NAME="nodepool1"  # Usually 'nodepool1' or 'agentpool'

# Check current node pool
az aks nodepool list \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --output table

# Scale the node pool (example: scale to 4 nodes)
az aks nodepool scale \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --name $NODE_POOL_NAME \
  --node-count 4



# If cluster autoscaler is already enabled, update the min/max counts
az aks nodepool update \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --name $NODE_POOL_NAME \
  --update-cluster-autoscaler \
  --min-count 3 \
  --max-count 6
```

Verify nodes are ready:
```bash
kubectl get nodes
kubectl wait --for=condition=Ready node --all --timeout=300s
```

---

## Step 2: Install Kueue on AKS

```bash
helm install kueue oci://registry.k8s.io/kueue/charts/kueue \
  --version=0.14.1 \
  --namespace kueue-system \
  --create-namespace \
  --wait --timeout 300s
```

Verify installation:
```bash
kubectl get pods -n kueue-system
kubectl get crd | grep kueue
```

---

## Step 3: Create a ResourceFlavor

A ResourceFlavor represents a type of resource available in your cluster (like different node types).

```bash
kubectl apply -f - <<EOF
apiVersion: kueue.x-k8s.io/v1beta1
kind: ResourceFlavor
metadata:
  name: default-flavor
EOF
```

Verify:
```bash
kubectl get resourceflavors
```

---

## Step 4: Create a ClusterQueue

ClusterQueue defines the quota (CPU, memory) available for jobs.

**Note:** Adjust the quota based on your cluster size. The example below uses 9 CPUs and 36Gi memory. 
To see your cluster's total capacity:

```bash
# Check total allocatable resources across all nodes
kubectl get nodes -o json | jq '.items[] | {name:.metadata.name, cpu:.status.allocatable.cpu, memory:.status.allocatable.memory}'
```

Create the ClusterQueue:

```bash
kubectl apply -f - <<EOF
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: cluster-queue
spec:
  namespaceSelector: {}  # Allow all namespaces
  queueingStrategy: BestEffortFIFO
  preemption:
    withinClusterQueue: LowerPriority  # Enable preemption for lower priority workloads
  resourceGroups:
    - coveredResources: ["cpu", "memory"]
      flavors:
        - name: default-flavor
          resources:
            - name: cpu
              nominalQuota: 9    # 9 CPUs available
            - name: memory
              nominalQuota: 36Gi # 36GB memory available
EOF
```

**What this means:**
- We have 9 CPUs and 36Gi memory total quota
- Jobs will queue if they exceed this
- Uses FIFO (First In First Out) strategy
- **Preemption enabled**: Higher priority workloads can preempt lower priority ones

> **🚀 Why You Need Kueue:**
> 
> **Without Kueue** (vanilla Kubernetes):
> - Jobs are submitted directly and create pods immediately
> - If cluster capacity is exceeded, pods enter `Pending` state indefinitely
> - No central quota tracking across multiple jobs/namespaces
> - No automatic queueing - you must manually manage job submissions
> - No fair sharing or priority-based scheduling at the job level
> - ResourceQuotas are namespace-scoped and don't support job queueing
> - No way to see "queue position" or when a job will start
>
> **With Kueue**:
> - ✅ Central quota management across namespaces
> - ✅ Jobs automatically queue when quota is exhausted
> - ✅ Jobs automatically start when resources become available
> - ✅ Fair sharing and priority scheduling
> - ✅ Visibility into queue position and workload status
> - ✅ Prevents pod thrashing and cluster overload

Verify:
```bash
kubectl get clusterqueues
kubectl describe clusterqueue cluster-queue
```

**Expected output:**
```
NAME            COHORT   PENDING WORKLOADS
cluster-queue            0
```
- **COHORT**: Empty (not part of a cohort for resource sharing)
- **PENDING WORKLOADS**: Number of workloads waiting in queue (should be 0 initially)

> **Note:** If you see `PENDING WORKLOADS: 1`, it means there's a workload queued from a previous run. Clean it up with:
> ```bash
> kubectl delete jobs --all -A
> kubectl delete workloads --all -A
> ```

---

## Step 5: Create a Namespace and LocalQueue

```bash
# Create namespace for our demo
kubectl create namespace team-a

# Create a LocalQueue in the namespace
kubectl apply -f - <<EOF
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  namespace: team-a
  name: team-a-queue
spec:
  clusterQueue: cluster-queue
EOF
```

**What this means:**
- `team-a` namespace can submit jobs
- Jobs reference the LocalQueue `team-a-queue`
- LocalQueue maps to `cluster-queue` for quota

Verify:
```bash
kubectl get localqueues -n team-a
```

---

## Step 6: Submit Jobs - Demo Quota Management

### Demo 6.1: Submit a Job Within Quota

```bash
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  namespace: team-a
  name: sample-job-1
  labels:
    kueue.x-k8s.io/queue-name: team-a-queue
spec:
  parallelism: 3
  completions: 3
  suspend: true  # Important: Kueue will unsuspend when admitted
  template:
    spec:
      containers:
      - name: dummy-job
        image: busybox:1.36
        command: ["sh", "-c", "echo 'Processing task...' && sleep 30"]
        resources:
          requests:
            cpu: "1"
            memory: "512Mi"
      restartPolicy: Never
EOF
```

**What happens:**
- 3 pods requested, each needs 1 CPU = 3 CPUs total
- We have 9 CPUs available ✅
- Job should be **admitted immediately**

Check status:
```bash
# List jobs
kubectl get jobs -n team-a

# Check workload status (Kueue creates this automatically)
kubectl get workloads -n team-a

# See detailed admission info
kubectl describe workload -n team-a
```

Watch pods start:
```bash
kubectl get pods -n team-a -w
```

---

### Demo 6.2: Submit More Jobs - Experience Queueing

```bash
# Submit second job (3 more CPUs)
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  namespace: team-a
  name: sample-job-2
  labels:
    kueue.x-k8s.io/queue-name: team-a-queue
spec:
  parallelism: 3
  completions: 3
  suspend: true
  template:
    spec:
      containers:
      - name: dummy-job
        image: busybox:1.36
        command: ["sh", "-c", "echo 'Processing task...' && sleep 30"]
        resources:
          requests:
            cpu: "1"
            memory: "512Mi"
      restartPolicy: Never
EOF

# Submit third job (3 more CPUs)
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  namespace: team-a
  name: sample-job-3
  labels:
    kueue.x-k8s.io/queue-name: team-a-queue
spec:
  parallelism: 3
  completions: 3
  suspend: true
  template:
    spec:
      containers:
      - name: dummy-job
        image: busybox:1.36
        command: ["sh", "-c", "echo 'Processing task...' && sleep 30"]
        resources:
          requests:
            cpu: "1"
            memory: "512Mi"
      restartPolicy: Never
EOF

# Submit fourth job (this will queue - not enough quota!)
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  namespace: team-a
  name: sample-job-4
  labels:
    kueue.x-k8s.io/queue-name: team-a-queue
spec:
  parallelism: 3
  completions: 3
  suspend: true
  template:
    spec:
      containers:
      - name: dummy-job
        image: busybox:1.36
        command: ["sh", "-c", "echo 'Processing task...' && sleep 30"]
        resources:
          requests:
            cpu: "1"
            memory: "512Mi"
      restartPolicy: Never
EOF
```

> **💡 Tip:** We use unique names (`sample-job-1`, `sample-job-2`, etc.) with `kubectl apply` following the declarative, idempotent approach. This is the recommended best practice for GitOps workflows.

**What happens:**
- Job 1: 3 CPUs used (3/9) ✅ Admitted
- Job 2: 3 CPUs used (6/9) ✅ Admitted
- Job 3: 3 CPUs used (9/9) ✅ Admitted
- Job 4: 3 CPUs needed but 0/9 available ⏸️ **Queued**

Check the queue:
```bash
# See all workloads and their status
kubectl get workloads -n team-a

# Check ClusterQueue status
kubectl describe clusterqueue cluster-queue

# Watch as jobs complete and the queued job starts
kubectl get pods -n team-a -w
```

---

## Step 7: Priority-Based Queueing Demo

Let's create jobs with different priorities to see priority scheduling in action.

### 7.1: Create WorkloadPriorityClasses

kubectl delete jobs -n team-a --all


```bash
# High priority
kubectl apply -f - <<EOF
apiVersion: kueue.x-k8s.io/v1beta1
kind: WorkloadPriorityClass
metadata:
  name: high-priority
value: 100
description: "High priority workloads"
EOF

# Low priority
kubectl apply -f - <<EOF
apiVersion: kueue.x-k8s.io/v1beta1
kind: WorkloadPriorityClass
metadata:
  name: low-priority
value: 10
description: "Low priority workloads"
EOF
```

Verify:
```bash
kubectl get workloadpriorityclasses
```

### 7.2: Clean up previous jobs

```bash
kubectl delete jobs -n team-a --all
```

### 7.3: Submit low priority job first

```bash
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  namespace: team-a
  name: low-priority-job
  labels:
    kueue.x-k8s.io/queue-name: team-a-queue
    kueue.x-k8s.io/priority-class: low-priority
spec:
  parallelism: 8
  completions: 8
  suspend: true
  template:
    spec:
      containers:
      - name: dummy-job
        image: busybox:1.36
        command: ["sh", "-c", "echo 'Low priority task' && sleep 60"]
        resources:
          requests:
            cpu: "1"
            memory: "512Mi"
      restartPolicy: Never
EOF
```

**This uses 8 CPUs, leaving only 1 CPU available.**

kubectl get workloads -n team-a


### 7.4: Submit high priority job

```bash
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  namespace: team-a
  name: high-priority-job
  labels:
    kueue.x-k8s.io/queue-name: team-a-queue
    kueue.x-k8s.io/priority-class: high-priority
spec:
  parallelism: 5
  completions: 5
  suspend: true
  template:
    spec:
      containers:
      - name: dummy-job
        image: busybox:1.36
        command: ["sh", "-c", "echo 'High priority task' && sleep 30"]
        resources:
          requests:
            cpu: "1"
            memory: "512Mi"
      restartPolicy: Never
EOF
```

**What happens:**
- High priority job needs 5 CPUs but only 1 is available
- **With preemption enabled** (`withinClusterQueue: LowerPriority`), Kueue will:
  1. Detect insufficient quota for high-priority job
  2. Identify low-priority job is using resources
  3. Preempt (evict) 5 pods from the low-priority job
  4. Admit the high-priority job immediately
- You'll see low-priority pods terminating and high-priority pods starting

Check preemption in action:
```bash
kubectl get workloads -n team-a
kubectl describe workload -n team-a
kubectl get pods -n team-a
```

---

## Step 8: Monitor and Observe

### Check Queue Status

```bash
# See all queued and running workloads
kubectl get workloads -A

# Check ClusterQueue utilization
kubectl get clusterqueue cluster-queue -o yaml

# Check LocalQueue status
kubectl get localqueue -n team-a team-a-queue -o yaml
```

### Watch Real-time Changes

```bash
# Watch workloads
watch kubectl get workloads -n team-a

# Watch pods
watch kubectl get pods -n team-a

# Watch jobs
watch kubectl get jobs -n team-a
```

---

## Step 9: Cleanup

```bash
# Delete jobs
kubectl delete jobs -n team-a --all

# Delete namespace
kubectl delete namespace team-a

# Delete ClusterQueue
kubectl delete clusterqueue cluster-queue

# Delete ResourceFlavor
kubectl delete resourceflavor default-flavor

# Delete WorkloadPriorityClasses
kubectl delete workloadpriorityclasses high-priority low-priority

# Optional: Uninstall Kueue
# helm uninstall kueue -n kueue-system
```

---

## Key Takeaways

1. **Quota Management**: ClusterQueue enforces resource quotas across namespaces
2. **Queueing**: Jobs wait when quota is exhausted, automatically start when resources free up
3. **Priority**: Higher priority jobs can preempt lower priority ones
4. **Fair Sharing**: Multiple teams can share cluster resources fairly
5. **Automatic**: Kueue integrates seamlessly - just add labels to your jobs

---

## Common Commands Reference

```bash
# View all Kueue resources
kubectl get resourceflavors
kubectl get clusterqueues
kubectl get localqueues -A
kubectl get workloads -A
kubectl get workloadpriorityclasses

# Debug a queued workload
kubectl describe workload <workload-name> -n <namespace>

# Check why a job is not starting
kubectl get workload <workload-name> -n <namespace> -o yaml

# Check ClusterQueue quota usage
kubectl describe clusterqueue <clusterqueue-name>
```

---

## Next Steps

- Explore **Cohorts** for sharing quota between multiple ClusterQueues
- Try **Fair Sharing** policies for multi-tenant scenarios
- Implement **Admission Checks** for advanced gating
- Configure **Preemption** policies
- Set up **MultiKueue** for multi-cluster job dispatching

For more information, visit: https://kueue.sigs.k8s.io/docs/ 
