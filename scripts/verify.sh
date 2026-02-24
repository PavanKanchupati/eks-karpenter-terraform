#!/bin/bash
# verify.sh - Verify Karpenter installation
# Usage: ./verify.sh

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
echo -e "${GREEN}🔍 Verifying Karpenter Installation${NC}"
echo -e "${BLUE}========================================${NC}"

# 1. Check Karpenter pods
echo -e "\n${YELLOW}📦 Karpenter Pods:${NC}"
kubectl get pods -n ${NAMESPACE}

# 2. Check EC2NodeClass
echo -e "\n${YELLOW}📦 EC2NodeClass:${NC}"
kubectl get ec2nodeclass -n ${NAMESPACE} default -o wide

# 3. Check NodePool
echo -e "\n${YELLOW}📦 NodePool:${NC}"
kubectl get nodepool -n ${NAMESPACE} default -o wide

# 4. Check aws-auth ConfigMap (CRITICAL)
echo -e "\n${YELLOW}🔐 aws-auth ConfigMap (MUST see Karpenter role):${NC}"
kubectl get configmap aws-auth -n kube-system -o yaml | grep -A5 "rolearn" | head -10

if kubectl get configmap aws-auth -n kube-system -o yaml | grep -q "KarpenterNodeRole"; then
    echo -e "${GREEN}✅ Karpenter node role found in aws-auth${NC}"
else
    echo -e "${RED}❌ Karpenter node role MISSING from aws-auth!${NC}"
fi

# 5. Check Karpenter controller logs (last 10 lines)
echo -e "\n${YELLOW}📊 Recent Karpenter Logs:${NC}"
kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=karpenter --tail=10

# 6. Check for any pending pods that might trigger scaling
echo -e "\n${YELLOW}⏳ Pending Pods:${NC}"
kubectl get pods --all-namespaces --field-selector status.phase=Pending

# 7. Verify IAM roles
echo -e "\n${YELLOW}🔑 IAM Role Verification:${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if aws iam get-role --role-name "KarpenterNodeRole-${CLUSTER_NAME}" &>/dev/null; then
    echo -e "${GREEN}✅ Node role exists: KarpenterNodeRole-${CLUSTER_NAME}${NC}"
else
    echo -e "${RED}❌ Node role missing!${NC}"
fi

if aws iam get-role --role-name "KarpenterControllerRole-${CLUSTER_NAME}" &>/dev/null; then
    echo -e "${GREEN}✅ Controller role exists: KarpenterControllerRole-${CLUSTER_NAME}${NC}"
else
    echo -e "${RED}❌ Controller role missing!${NC}"
fi

# 8. Check instance profile
if aws iam get-instance-profile --instance-profile-name "KarpenterNodeInstanceProfile-${CLUSTER_NAME}" &>/dev/null; then
    echo -e "${GREEN}✅ Instance profile exists${NC}"
else
    echo -e "${RED}❌ Instance profile missing!${NC}"
fi

# 9. Summary
echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}✅ Verification Complete${NC}"
echo -e "${BLUE}========================================${NC}"

# If you have a test deployment, check its status
if kubectl get deployment inflate &>/dev/null; then
    echo -e "\n📊 Test deployment status:"
    kubectl get pods -l app=inflate -o wide
fi