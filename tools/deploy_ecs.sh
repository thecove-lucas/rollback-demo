#!/bin/bash
#
# deploy_ecs.sh: Simulated stand-in for a real ECS deploy script. Switches the
# fake ECS service to TASK_NAME, waits a couple of seconds like a rollout would, and exits 0. With
# SIMULATE_FAILURE=true it behaves like a circuit breaker rollback instead: the service stays on
# its current revision and the script exits 1 with the same message the real script prints.
#
# Usage:
#   REGION=<aws-region> CLUSTER_NAME=<cluster> SERVICE_NAME=<service> TASK_NAME=<task def> \
#   [SIMULATE_FAILURE=true] ./deploy_ecs.sh

set -euo pipefail

: "${CLUSTER_NAME:?CLUSTER_NAME required}"
: "${SERVICE_NAME:?SERVICE_NAME required}"
: "${TASK_NAME:?TASK_NAME required}"

echo "Forcing new deployment: cluster=$CLUSTER_NAME service=$SERVICE_NAME task=$TASK_NAME"

for attempt in 1 2; do
  echo "⏳ [$attempt/2] $SERVICE_NAME rolling out ${TASK_NAME##*/} (simulated)"
  sleep 1
done

if [ "${SIMULATE_FAILURE:-false}" = true ]; then
  printf "\033[31m❌ Service %s deployment FAILED or was rolled back (status=ACTIVE): ECS deployment circuit breaker: tasks failed to start. (simulated)\033[0m\n" "$SERVICE_NAME"
  exit 1
fi

aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --task-definition "$TASK_NAME"
echo "✅ Service $SERVICE_NAME is serving the new revision (simulated)"
