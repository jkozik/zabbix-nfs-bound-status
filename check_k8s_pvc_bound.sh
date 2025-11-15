#!/bin/bash
################################################################################
# check_k8s_pvc_bound.sh
#
# Zabbix external check script to verify Kubernetes PVC bound status
#
# Usage: check_k8s_pvc_bound.sh <pvc-name> [namespace]
# Returns: 1 if PVC is bound, 0 if not bound or missing
#
# Author: Jack Kozik
# Created: 2025-01-15
# Purpose: Monitor NFS-backed PVCs for weather station services
################################################################################

PVC_NAME=$1
NAMESPACE=${2:-default}

# Path to kubeconfig - UPDATE THIS if your path is different
KUBECONFIG_PATH="/home/jkozik/.kube/config"

# Validate parameters
if [ -z "$PVC_NAME" ]; then
    echo "0"  # Missing parameter
    exit 0
fi

# Check if kubeconfig exists
if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo "0"  # Config not found
    exit 0
fi

# Check PVC status using explicit kubeconfig
STATUS=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)

if [ "$STATUS" == "Bound" ]; then
    echo 1  # Bound - OK
else
    echo 0  # Not bound or doesn't exist - Problem
fi
