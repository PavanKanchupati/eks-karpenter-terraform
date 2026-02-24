#!/bin/bash
# install.sh - Complete Karpenter installation script
# Usage: ./scripts/install.sh [dev|prod]

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-devopsshack-cluster}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
KARPENTER_VERSION="${KARPENTER_VERSION:-1.9.0}"
K8S_VERSION="${K8S_VERSION:-1.35}"
NAMESPACE="${NAMESPACE:-karpenter}"
ENVIRONMENT="${1:-dev}"  # dev or prod

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}🚀 Installing Karpenter (${ENVIRONMENT})${NC}"
echo -e "${BLUE}========================================${NC}"

# Check prerequisites
check_prerequisites() {
    echo -e "\n${YELLOW}📋 Checking prerequisites...${NC}"
    
    command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}❌ kubectl not found${NC}" >&2; exit 1; }
    command -v helm >/dev/null 2>&1 || { echo -e "${RED}❌ helm not found${NC}" >&2; exit 1; }
    command -v aws >/dev/null 2>&1 || { echo -e "${RED}❌ aws CLI not found${NC}" >&2; exit 1; }
    
    echo -e "${GREEN}✅ Prerequisites met${NC}"
}

# Get AL2023 AMI version
get_ami_version() {
    echo -e "\n${YELLOW}📦 Getting AL2023 version...${NC}"
    
    ALIAS_VERSION=$(aws ssm get-parameter \
        --name "/aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2023/x86_64/standard/recommended/image_id" \
        --query Parameter.Value \
        --output text 2>/dev/null | xargs -I {} aws ec2 describe-images \
        --image-ids {} \
        --query 'Images[0].Name' \
        --output text 2>/dev/null | sed -n 's/.*\(v[0-9]\+\).*/\1/p')
    
    if [ -z "$ALIAS_VERSION" ]; then
        echo -e "${YELLOW}⚠️  Could not determine AMI version, using 'latest'${NC}"
        ALIAS_VERSION="latest"
    fi
    
    echo -e "${GREEN}✅ Using AL2023 version: ${ALIAS_VERSION}${NC}"
}

# Create namespace
create_namespace() {
    echo -e "\n${YELLOW}📦 Creating namespace...${NC}"
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    name: ${NAMESPACE}
    pod-security.kubernetes.io/enforce: privileged
EOF
    
    echo -e "${GREEN}✅ Namespace created${NC}"
}

# Update values file with environment-specific settings
update_values() {
    echo -e "\n${YELLOW}📝 Updating Helm values for ${ENVIRONMENT}...${NC}"
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Create a temporary values file with substitutions
    sed -e "s/\${AWS_ACCOUNT_ID}/${AWS_ACCOUNT_ID}/g" \
        -e "s/\${CLUSTER_NAME}/${CLUSTER_NAME}/g" \
        -e "s/\${KARPENTER_VERSION}/${KARPENTER_VERSION}/g" \
        ../manifests/karpenter-values.yaml > /tmp/karpenter-values.yaml
    
    echo -e "${GREEN}✅ Values file updated${NC}"
}

# Install Karpenter with Helm
install_karpenter() {
    echo -e "\n${YELLOW}🚀 Installing Karpenter Helm chart...${NC}"
    
    helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
        --namespace ${NAMESPACE} \
        --values /tmp/karpenter-values.yaml \
        --version ${KARPENTER_VERSION} \
        --wait \
        --timeout 5m
    
    echo -e "${GREEN}✅ Karpenter installed${NC}"
}

# Apply CRDs
apply_crds() {
    echo -e "\n${YELLOW}📦 Applying EC2NodeClass and NodePool...${NC}"
    
    # Update EC2NodeClass with AMI version
    sed -i.bak "s/al2023@.*/al2023@${ALIAS_VERSION}/" ../manifests/ec2nodeclass.yaml
    
    kubectl apply -f ../manifests/ec2nodeclass.yaml
    kubectl apply -f ../manifests/nodepool.yaml
    
    echo -e "${GREEN}✅ CRDs applied${NC}"
}

# Verify installation
verify() {
    echo -e "\n${YELLOW}🔍 Verifying installation...${NC}"
    
    # Wait for pods to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=karpenter -n ${NAMESPACE} --timeout=60s
    
    # Check EC2NodeClass status
    if kubectl get ec2nodeclass default -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
        echo -e "${GREEN}✅ EC2NodeClass is Ready${NC}"
    else
        echo -e "${RED}❌ EC2NodeClass not Ready${NC}"
        exit 1
    fi
    
    # Check NodePool status
    if kubectl get nodepool default -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
        echo -e "${GREEN}✅ NodePool is Ready${NC}"
    else
        echo -e "${RED}❌ NodePool not Ready${NC}"
        exit 1
    fi
}

# Post-installation summary
summary() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${GREEN}✅ Installation complete!${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "📊 Next steps:"
    echo "   1. Deploy test workload:  kubectl apply -f ../manifests/inflate.yaml"
    echo "   2. Watch nodes join:      kubectl get nodes -w"
    echo "   3. Watch nodeclaims:      kubectl get nodeclaims -n ${NAMESPACE} -w"
    echo "   4. Run verification:      ./verify.sh"
    echo ""
    echo "📝 Useful commands:"
    echo "   - View Karpenter logs:    kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=karpenter"
    echo "   - Check EC2NodeClass:     kubectl describe ec2nodeclass default -n ${NAMESPACE}"
    echo "   - Scale test deployment:  kubectl scale deployment inflate --replicas=10"
    echo ""
    echo "🧹 Cleanup when done:        ./cleanup.sh"
}

# Main execution
main() {
    check_prerequisites
    get_ami_version
    create_namespace
    update_values
    install_karpenter
    apply_crds
    verify
    summary
}

main "$@"