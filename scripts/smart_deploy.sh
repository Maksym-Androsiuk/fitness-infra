#!/bin/bash
set -e

IMAGE_NAME=$1
DEPLOYMENT_NAME="wger-app"
NAMESPACE="default"
TIMEOUT_SECONDS=120

echo "🚀 Starting deployment of $IMAGE_NAME..."

# 1. Update the image (Trigger Rollout)
# Використовуємо set image для імперативного оновлення
kubectl set image deployment/$DEPLOYMENT_NAME wger=$IMAGE_NAME -n $NAMESPACE

# 2. Wait for Rollout to complete
echo "⏳ Waiting for rollout to finish..."
if ! kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=${TIMEOUT_SECONDS}s; then
    echo "❌ Rollout timed out!"
    echo "🔄 Rolling back..."
    kubectl rollout undo deployment/$DEPLOYMENT_NAME -n $NAMESPACE
    exit 1
fi

echo "✅ Rollout status OK. Starting deep health checks..."

# 3. Deep Health Check & Log Analysis
# Отримуємо нові поди (беремо останні створені)
NEW_PODS=$(kubectl get pods -n $NAMESPACE -l app=wger -o jsonpath="{.items[*].metadata.name}")

for POD in $NEW_PODS; do
    echo "🔍 Checking Pod: $POD"
    
    # Check for Restarts
    RESTARTS=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath="{.status.containerStatuses[0].restartCount}")
    if [ "$RESTARTS" -gt 0 ]; then
        echo "⚠️  Pod $POD has restarted $RESTARTS times! Unstable."
        ROLLBACK_NEEDED=true
        break
    fi

    # Check Logs for "CRITICAL" or "Traceback" (Python specific errors)
    # Беремо останні 50 рядків логів
    LOGS=$(kubectl logs $POD -n $NAMESPACE --tail=50)
    if echo "$LOGS" | grep -q -E "Traceback|CRITICAL|Fatal error"; then
        echo "❌ Critical error found in logs of $POD"
        echo "--- Log Snippet ---"
        echo "$LOGS" | grep -E "Traceback|CRITICAL"
        echo "-------------------"
        ROLLBACK_NEEDED=true
        break
    fi
done

# 4. Final Verification and Rollback Decision
if [ "$ROLLBACK_NEEDED" = true ]; then
    echo "🚨 Health checks failed. Initiating rollback..."
    kubectl rollout undo deployment/$DEPLOYMENT_NAME -n $NAMESPACE
    echo "🔄 Rollback initiated successfully."
    exit 1
else
    echo "🎉 Deployment Successful! App is stable, logs are clean."
    exit 0
fi