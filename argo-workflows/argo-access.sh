#!/bin/bash

# Argo Workflows Secure Access Script
# This script helps you securely access Argo UI via port forwarding

set -e

NAMESPACE="argo"
PORT="2746"
LOCAL_PORT="${1:-2746}"

echo "🔒 Argo Workflows Secure Access"
echo "================================"

# Check if Argo server service exists
if ! kubectl get svc argo-server -n $NAMESPACE &>/dev/null; then
    echo "❌ Error: argo-server service not found in namespace '$NAMESPACE'"
    echo "   Make sure Argo Workflows is installed."
    exit 1
fi

# Check service type
SERVICE_TYPE=$(kubectl get svc argo-server -n $NAMESPACE -o jsonpath='{.spec.type}')
echo "📋 Service Type: $SERVICE_TYPE"

if [ "$SERVICE_TYPE" = "LoadBalancer" ]; then
    echo "⚠️  Warning: argo-server is exposed as LoadBalancer (external access)"
    echo "   Consider changing to ClusterIP for better security:"
    echo "   kubectl patch svc argo-server -n $NAMESPACE -p '{\"spec\": {\"type\": \"ClusterIP\"}}'"
    echo ""
fi

# Start port forwarding
echo "🚀 Starting secure port forward to Argo UI..."
echo "   Local URL: https://localhost:$LOCAL_PORT"
echo "   (You may need to accept the self-signed certificate warning)"
echo ""
echo "💡 Tip: Press Ctrl+C to stop the port forward"
echo ""

# Trap to handle cleanup
trap 'echo "🛑 Port forward stopped"; exit 0' INT

kubectl port-forward svc/argo-server -n $NAMESPACE $LOCAL_PORT:$PORT