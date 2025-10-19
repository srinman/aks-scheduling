# Argo Workflows on AKS - Multi-Step Task Demo

## Files in this Repository

- `README.md` - This comprehensive guide
- `argo-rbac.yaml` - RBAC configuration for workflows
- `argo-access.sh` - Secure access script for Argo UI
- `data-processing-workflow.yaml` - Example multi-step workflow
- `parallel-processing-workflow.yaml` - Example parallel workflow  
- `conditional-workflow.yaml` - Example conditional workflow

## Introduction

Argo Workflows is a container-native workflow engine for orchestrating parallel jobs on Kubernetes. It is implemented as a Kubernetes CRD (Custom Resource Definition) and provides a rich set of features for defining complex, multi-step workflows.

This guide demonstrates:
- Installing Argo Workflows on Azure Kubernetes Service (AKS)
- Creating and running multi-step workflows
- Best practices for workflow orchestration

## Prerequisites

- Azure CLI installed and configured
- kubectl configured to connect to your AKS cluster
- Docker (optional, for building custom images)

## Installation

### 1. Install Argo Workflows

Create the Argo namespace and install the controller:

```bash
# Create namespace
kubectl create namespace argo

# Install Argo Workflows
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.4.4/install.yaml
```

### 2. Configure Argo Server for Internal Access

Keep Argo server as ClusterIP for security (default behavior):

```bash
# Verify the service is ClusterIP (default)
kubectl get svc argo-server -n argo

# The service should show TYPE as ClusterIP for internal-only access
```

### 3. Install Argo CLI

```bash
# Detect system architecture and download appropriate Argo CLI
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        ARGO_ARCH="amd64"
        ;;
    aarch64|arm64)
        ARGO_ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Download and install Argo CLI for detected architecture
curl -sLO https://github.com/argoproj/argo-workflows/releases/download/v3.4.4/argo-linux-${ARGO_ARCH}.gz
gunzip argo-linux-${ARGO_ARCH}.gz
chmod +x argo-linux-${ARGO_ARCH}
sudo mv argo-linux-${ARGO_ARCH} /usr/local/bin/argo

# Verify installation
argo version
```

### 4. Configure RBAC for Workflows

Create proper service account and permissions:

```bash
cat <<EOF > argo-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argo-workflow
  namespace: argo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: argo
  name: argo-workflow-role
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "watch", "patch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "watch"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
- apiGroups: ["argoproj.io"]
  resources: ["workflows", "workflowtemplates", "cronworkflows", "clusterworkflowtemplates"]
  verbs: ["get", "list", "watch", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argo-workflow-binding
  namespace: argo
subjects:
- kind: ServiceAccount
  name: argo-workflow
  namespace: argo
roleRef:
  kind: Role
  name: argo-workflow-role
  apiGroup: rbac.authorization.k8s.io
EOF

# Apply the RBAC configuration
kubectl apply -f argo-rbac.yaml
```

### 5. Verify Installation

```bash
# Check if Argo components are running
kubectl get pods -n argo

# Check Argo server status
kubectl get svc -n argo

# Verify service account creation
kubectl get sa argo-workflow -n argo
```

## Multi-Step Workflow Examples

### Example 1: Sequential Data Processing Pipeline

This example demonstrates a multi-step data processing workflow with dependencies:

```bash
cat <<EOF > data-processing-workflow.yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: data-processing-
  namespace: argo
spec:
  serviceAccountName: argo-workflow
  entrypoint: data-pipeline
  templates:
  - name: data-pipeline
    dag:
      tasks:
      - name: extract-data
        template: extract
      - name: transform-data
        template: transform
        dependencies: [extract-data]
        arguments:
          parameters:
          - name: input-data
            value: "{{tasks.extract-data.outputs.parameters.extracted-file}}"
      - name: load-data
        template: load
        dependencies: [transform-data]
        arguments:
          parameters:
          - name: processed-data
            value: "{{tasks.transform-data.outputs.parameters.transformed-file}}"
      - name: validate-data
        template: validate
        dependencies: [load-data]

  - name: extract
    container:
      image: alpine:latest
      command: [sh, -c]
      args: ["echo 'Extracting data from source...'; echo 'raw-data.csv' > /tmp/extracted.txt; sleep 10"]
    outputs:
      parameters:
      - name: extracted-file
        valueFrom:
          path: /tmp/extracted.txt

  - name: transform
    inputs:
      parameters:
      - name: input-data
    container:
      image: alpine:latest
      command: [sh, -c]
      args: ["echo 'Transforming {{inputs.parameters.input-data}}...'; echo 'processed-data.csv' > /tmp/transformed.txt; sleep 15"]
    outputs:
      parameters:
      - name: transformed-file
        valueFrom:
          path: /tmp/transformed.txt

  - name: load
    inputs:
      parameters:
      - name: processed-data
    container:
      image: alpine:latest
      command: [sh, -c]
      args: ["echo 'Loading {{inputs.parameters.processed-data}} to database...'; sleep 10"]

  - name: validate
    container:
      image: alpine:latest
      command: [sh, -c]
      args: ["echo 'Validating data integrity...'; sleep 5; echo 'Validation complete!'"]
EOF
```

### Example 2: Parallel Processing with Fan-out/Fan-in

This example shows parallel execution with synchronization:

```bash
cat <<EOF > parallel-processing-workflow.yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: parallel-processing-
  namespace: argo
spec:
  serviceAccountName: argo-workflow
  entrypoint: parallel-pipeline
  templates:
  - name: parallel-pipeline
    dag:
      tasks:
      - name: prepare-data
        template: prepare
      - name: process-batch-1
        template: process-batch
        dependencies: [prepare-data]
        arguments:
          parameters:
          - name: batch-id
            value: "1"
      - name: process-batch-2
        template: process-batch
        dependencies: [prepare-data]
        arguments:
          parameters:
          - name: batch-id
            value: "2"
      - name: process-batch-3
        template: process-batch
        dependencies: [prepare-data]
        arguments:
          parameters:
          - name: batch-id
            value: "3"
      - name: aggregate-results
        template: aggregate
        dependencies: [process-batch-1, process-batch-2, process-batch-3]

  - name: prepare
    container:
      image: alpine:latest
      command: [sh, -c]
      args: ["echo 'Preparing data for parallel processing...'; sleep 5"]

  - name: process-batch
    inputs:
      parameters:
      - name: batch-id
    container:
      image: alpine:latest
      command: [sh, -c]
      args: ["echo 'Processing batch {{inputs.parameters.batch-id}}...'; sleep $((RANDOM % 20 + 10))"]

  - name: aggregate
    container:
      image: alpine:latest
      command: [sh, -c]
      args: ["echo 'Aggregating results from all batches...'; sleep 8; echo 'Pipeline complete!'"]
EOF
```

### Example 3: Conditional Workflow with Error Handling

This example demonstrates conditional execution and retry logic:

```bash
cat <<EOF > conditional-workflow.yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: conditional-workflow-
  namespace: argo
spec:
  serviceAccountName: argo-workflow
  entrypoint: conditional-pipeline
  templates:
  - name: conditional-pipeline
    dag:
      tasks:
      - name: health-check
        template: health-check
      - name: deploy-app
        template: deploy
        dependencies: [health-check]
        when: "{{tasks.health-check.outputs.parameters.status}} == healthy"
      - name: rollback
        template: rollback
        dependencies: [health-check]
        when: "{{tasks.health-check.outputs.parameters.status}} != healthy"
      - name: run-tests
        template: test-suite
        dependencies: [deploy-app]

  - name: health-check
    container:
      image: alpine:latest
      command: [sh, -c]
      args: |
        - |
          echo "Checking system health..."
          if [ $((RANDOM % 2)) -eq 0 ]; then
            echo "healthy" > /tmp/status.txt
            echo "System is healthy"
          else
            echo "unhealthy" > /tmp/status.txt
            echo "System health check failed"
          fi
    outputs:
      parameters:
      - name: status
        valueFrom:
          path: /tmp/status.txt
    retryStrategy:
      limit: 2

  - name: deploy
    container:
      image: alpine:latest
      command: [sh, -c]
      args: ["echo 'Deploying application...'; sleep 10; echo 'Deployment successful!'"]

  - name: rollback
    container:
      image: alpine:latest
      command: [sh, -c]
      args: ["echo 'Rolling back to previous version...'; sleep 5; echo 'Rollback complete!'"]

  - name: test-suite
    container:
      image: alpine:latest
      command: [sh, -c]
      args: ["echo 'Running test suite...'; sleep 15; echo 'All tests passed!'"]
EOF
```

## Running the Workflows

### Submit and Monitor Workflows

```bash
# Submit the data processing workflow
argo submit data-processing-workflow.yaml -n argo

# Submit the parallel processing workflow
argo submit parallel-processing-workflow.yaml -n argo

# Submit the conditional workflow
argo submit conditional-workflow.yaml -n argo

# List running workflows
argo list -n argo

# Get workflow details
argo get <workflow-name> -n argo

# Watch workflow progress
argo watch <workflow-name> -n argo

# Get workflow logs
argo logs <workflow-name> -n argo
```

### Access Argo UI (ClusterIP - Internal Access Only)

Since we're using ClusterIP for security, access the UI through port forwarding:

```bash
# Port forward to access the UI locally (secure method)
kubectl port-forward svc/argo-server -n argo 2746:2746

# Access the UI at: https://localhost:2746
# Note: You may need to accept the self-signed certificate warning

# Alternative: Run in background
kubectl port-forward svc/argo-server -n argo 2746:2746 &

# To stop background port-forward
pkill -f "kubectl port-forward.*argo-server"
```

#### Using the Secure Access Script

For convenience, use the provided script:

```bash
# Make the script executable
chmod +x argo-access.sh

# Start secure access (default port 2746)
./argo-access.sh

# Or use a different local port
./argo-access.sh 8080
```

**Security Benefits of ClusterIP:**
- No external internet exposure
- Access only from within cluster or via port-forwarding
- Reduces attack surface
- Complies with internal-only security policies

### Alternative Secure Access Methods

#### Option 1: Access from within the cluster
```bash
# Create a temporary pod to access Argo UI from within cluster
kubectl run argo-access --rm -it --image=alpine/curl --restart=Never -- sh

# From within the pod:
curl -k https://argo-server.argo.svc.cluster.local:2746
```

#### Option 2: Ingress with Authentication (Production)
```bash
cat <<EOF > argo-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argo-server-ingress
  namespace: argo
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    # Add authentication annotations as needed
    # nginx.ingress.kubernetes.io/auth-type: basic
    # nginx.ingress.kubernetes.io/auth-secret: basic-auth
spec:
  tls:
  - hosts:
    - argo.your-internal-domain.com
    secretName: argo-tls
  rules:
  - host: argo.your-internal-domain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argo-server
            port:
              number: 2746
EOF

# Apply only if you have ingress controller and internal DNS
# kubectl apply -f argo-ingress.yaml
```

## Workflow Management Commands

### Useful Argo CLI Commands

```bash
# Delete a workflow
argo delete <workflow-name> -n argo

# Suspend a running workflow
argo suspend <workflow-name> -n argo

# Resume a suspended workflow
argo resume <workflow-name> -n argo

# Retry a failed workflow
argo retry <workflow-name> -n argo

# Stop a running workflow
argo stop <workflow-name> -n argo

# Get workflow logs for specific step
argo logs <workflow-name> -c <container-name> -n argo
```

## Best Practices

### 1. Resource Management

```bash
cat <<EOF > workflow-with-resources.yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: resource-managed-
  namespace: argo
spec:
  serviceAccountName: argo-workflow
  entrypoint: main
  templates:
  - name: main
    container:
      image: alpine:latest
      command: [sh, -c, "echo 'Processing with resource limits'; sleep 10"]
      resources:
        requests:
          memory: "64Mi"
          cpu: "100m"
        limits:
          memory: "128Mi"
          cpu: "200m"
EOF
```

### 2. Secrets and ConfigMaps

```bash
# Create a secret for the workflow
kubectl create secret generic workflow-secret --from-literal=api-key=your-api-key -n argo

cat <<EOF > workflow-with-secrets.yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: secure-workflow-
  namespace: argo
spec:
  serviceAccountName: argo-workflow
  entrypoint: secure-task
  templates:
  - name: secure-task
    container:
      image: alpine:latest
      command: [sh, -c]
      args: ["echo 'Using secret: $API_KEY'; sleep 5"]
      env:
      - name: API_KEY
        valueFrom:
          secretKeyRef:
            name: workflow-secret
            key: api-key
EOF
```

### 3. Artifacts and Volume Mounts

```bash
cat <<EOF > workflow-with-artifacts.yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: artifact-workflow-
  namespace: argo
spec:
  serviceAccountName: argo-workflow
  entrypoint: artifact-pipeline
  templates:
  - name: artifact-pipeline
    dag:
      tasks:
      - name: generate-artifact
        template: generator
      - name: consume-artifact
        template: consumer
        dependencies: [generate-artifact]
        arguments:
          artifacts:
          - name: input-artifact
            from: "{{tasks.generate-artifact.outputs.artifacts.result}}"

  - name: generator
    container:
      image: alpine:latest
      command: [sh, -c]
      args: ["echo 'Generated data' > /tmp/result.txt"]
    outputs:
      artifacts:
      - name: result
        path: /tmp/result.txt

  - name: consumer
    inputs:
      artifacts:
      - name: input-artifact
        path: /tmp/input.txt
    container:
      image: alpine:latest
      command: [sh, -c]
      args: ["echo 'Processing:'; cat /tmp/input.txt"]
EOF
```

## Cleanup

```bash
# Delete all workflows in the namespace
argo delete --all -n argo

# Remove Argo Workflows installation
kubectl delete -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.4.4/install.yaml

# Delete the namespace
kubectl delete namespace argo
```

## Troubleshooting

### Common Issues and Solutions

1. **Workflow stuck in pending**: Check resource quotas and node capacity
2. **Permission errors (pods "xxx" is forbidden)**: 
   - Ensure RBAC configuration is applied: `kubectl apply -f argo-rbac.yaml`
   - Verify service account exists: `kubectl get sa argo-workflow -n argo`
   - Check that workflows specify `serviceAccountName: argo-workflow`
3. **Image pull errors**: Verify image names and registry access
4. **Network issues**: Check service mesh and network policies
5. **Exec format error**: Install correct Argo CLI binary for your architecture (ARM64 vs AMD64)
6. **Cannot access Argo UI**: 
   - For ClusterIP (recommended): Use `kubectl port-forward svc/argo-server -n argo 2746:2746`
   - Check if service type: `kubectl get svc argo-server -n argo`
   - For LoadBalancer (not recommended for production): External IP may take time to provision

### Debug Commands

```bash
# Check Argo controller logs
kubectl logs -n argo deployment/workflow-controller

# Check Argo server logs
kubectl logs -n argo deployment/argo-server

# Describe a stuck workflow
kubectl describe workflow <workflow-name> -n argo

# Check events
kubectl get events -n argo --sort-by=.metadata.creationTimestamp
```

## Security Considerations

### Recommended Production Setup
- ✅ Use ClusterIP for Argo server (no internet exposure)
- ✅ Access via port-forwarding or internal ingress only
- ✅ Implement RBAC with least-privilege service accounts
- ✅ Use secrets for sensitive data, not environment variables
- ✅ Enable audit logging for workflow executions
- ✅ Regularly update Argo Workflows to latest stable version

### Service Types Comparison
| Type | Security | Access Method | Use Case |
|------|----------|---------------|----------|
| ClusterIP | ✅ High | Port-forward, Internal | Production (Recommended) |
| NodePort | ⚠️ Medium | Node IP:Port | Development only |
| LoadBalancer | ❌ Low | External IP | Not recommended |

## Next Steps

- Explore Argo Events for event-driven workflows
- Integrate with CI/CD pipelines
- Set up monitoring and alerting
- Implement custom workflow templates
- Scale workflows with cluster autoscaling
- Configure authentication and authorization
- Set up workflow notifications

For more advanced features and configurations, refer to the [official Argo Workflows documentation](https://argoproj.github.io/argo-workflows/).