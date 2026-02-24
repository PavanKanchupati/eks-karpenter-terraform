#!/bin/bash
# cleanup.sh - Remove Karpenter and test resources
# Usage: ./cleanup.sh

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="${NAMESPACE:-karpenter}"
CLUSTER_NAME="${CLUSTER_NAME:-devopsshack-cluster}"

echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}🧹 Cleaning up Karpenter Resources${NC}"
echo -e "${BLUE}========================================${NC}"

# Confirm with user
read -p "Are you sure you want to delete all Karpenter resources? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cleanup cancelled${NC}"
    exit 0
fi

# 1. Delete test deployment if exists
echo -e "\n${YELLOW}📦 Deleting test deployment...${NC}"
kubectl delete deployment inflate --timeout=30s 2>/dev/null || true

# 2. Delete NodePool and EC2NodeClass
echo -e "\n${YELLOW}📦 Deleting NodePool and EC2NodeClass...${NC}"
kubectl delete -f ../manifests/nodepool.yaml --timeout=30s 2>/dev/null || true
kubectl delete -f ../manifests/ec2nodeclass.yaml --timeout=30s 2>/dev/null || true

# 3. Delete all nodeclaims (terminates instances)
echo -e "\n${YELLOW}📦 Deleting nodeclaims...${NC}"
kubectl delete nodeclaims --all --timeout=30s 2>/dev/null || true

# 4. Wait for instances to terminate
echo -e "\n${YELLOW}⏳ Waiting for instances to terminate...${NC}"
sleep 10

# 5. Check AWS for remaining instances
INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:karpenter.sh/discovery,Values=${CLUSTER_NAME}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[*].Instances[*].[InstanceId,State.Name]" \
    --output text)

if [ -n "$INSTANCES" ]; then
    echo -e "${YELLOW}⚠️  Found running instances:${NC}"
    echo "$INSTANCES"
    read -p "Terminate these instances? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for id in $(echo "$INSTANCES" | awk '{print $1}'); do
            aws ec2 terminate-instances --instance-ids "$id" &>/dev/null
        done
        echo -e "${GREEN}✅ Instances terminated${NC}"
    fi
fi

# 6. Uninstall Karpenter Helm release
echo -e "\n${YELLOW}📦 Uninstalling Karpenter Helm release...${NC}"
helm uninstall karpenter -n ${NAMESPACE} 2>/dev/null || true

# 7. Delete namespace
echo -e "\n${YELLOW}📦 Deleting namespace...${NC}"
kubectl delete namespace ${NAMESPACE} --timeout=30s 2>/dev/null || true

# 8. Optional: Remove aws-auth entry (be careful!)
echo -e "\n${YELLOW}⚠️  aws-auth cleanup (optional)${NC}"
echo "The Karpenter node role entry in aws-auth was not removed automatically."
echo "To remove it manually: kubectl edit configmap aws-auth -n kube-system"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}✅ Cleanup complete${NC}"
echo -e "${BLUE}========================================${NC}"