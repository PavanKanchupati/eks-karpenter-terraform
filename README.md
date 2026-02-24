# EKS Karpenter Terraform

Production-ready Karpenter autoscaling setup for EKS clusters.

## 📋 Prerequisites

- AWS CLI configured
- Terraform >= 1.0
- kubectl installed
- helm installed

## 🚀 Quick Start

```bash
# Clone the repo
git clone https://github.com/YOUR_USERNAME/eks-karpenter-terraform.git
cd eks-karpenter-terraform

# Deploy infrastructure
cd terraform
terraform init
terraform apply -auto-approve

# Install Karpenter
cd ../scripts
./install.sh

# Verify installation
./verify.sh

# Test with sample app
kubectl apply -f ../manifests/inflate.yaml