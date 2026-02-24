# Karpenter EKS Architecture

## 🏗️ Overview

This document describes the architecture of our Karpenter-based EKS cluster autoscaling solution.

## 📊 High-Level Architecture
┌─────────────────────────────────────────────────────────────┐
│ Kubernetes Cluster │
├─────────────────────────────────────────────────────────────┤
│ ┌─────────────────┐ ┌─────────────────┐ │
│ │ System Nodes │ │ Karpenter Nodes │ │
│ │ (t3.large x2) │ │ (t3.xlarge) │ │
│ └─────────────────┘ └─────────────────┘ │
│ │ ▲ │
│ ▼ │ │
│ ┌─────────────────┐ ┌─────────────────┐ │
│ │ Karpenter │───▶│ EC2NodeClass │ │
│ │ Controller │ │ - AL2023 AMI │ │
│ └─────────────────┘ │ - Subnet tags │ │
│ │ │ - SG tags │ │
│ ▼ └─────────────────┘ │
│ ┌─────────────────┐ │
│ │ NodePool │ │
│ │ - Requirements │ │
│ │ - Limits │ │
│ │ - Disruption │ │
│ └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
│
▼
┌─────────────────────────────────────────────────────────────┐
│ AWS Cloud │
├─────────────────────────────────────────────────────────────┤
│ ┌─────────────────┐ ┌─────────────────┐ │
│ │ VPC │ │ IAM Roles │ │
│ │ - Public subnets│ │ - Node role │ │
│ │ - Private subnets│ │ - Controller │ │
│ │ - NAT Gateway │ │ role (IRSA) │ │
│ │ - VPC Endpoints │ └─────────────────┘ │
│ │ (SSM, EC2) │ │
│ └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘


## 🧩 Key Components

### 1. **EKS Cluster**
- Version: 1.35
- Encryption: KMS for secrets
- Endpoint: Private + Public access

### 2. **Network Infrastructure**
- **VPC CIDR**: 10.0.0.0/16
- **Public Subnets**: For load balancers, NAT
- **Private Subnets**: For worker nodes
- **VPC Endpoints**: SSM, EC2, EKS for private subnet communication

### 3. **IAM Roles**
| Role | Purpose | Trusts |
|------|---------|--------|
| `KarpenterNodeRole` | EC2 instances | EC2 service |
| `KarpenterControllerRole` | Karpenter pods | OIDC (IRSA) |

### 4. **Karpenter Components**

#### EC2NodeClass (`ec2nodeclass.yaml`)
- **AMI**: AL2023 (version-pinned)
- **Instance Profile**: `KarpenterNodeInstanceProfile`
- **Subnet Selection**: Based on `karpenter.sh/discovery` tag
- **Security Groups**: Based on same tag
- **UserData**: None (AMI handles bootstrap)

#### NodePool (`nodepool.yaml`)
- **Instance Types**: t3.medium, t3.large, t3.xlarge
- **Capacity Types**: on-demand (spot-ready)
- **Disruption Policy**: `WhenEmptyOrUnderutilized` after 1m
- **Limits**: 20 CPU cores total

## 🔄 Workflow

1. **Unschedulable pod** appears in cluster
2. **Karpenter controller** detects it
3. **NodePool** evaluated for requirements
4. **EC2NodeClass** provides launch configuration
5. **EC2 instance** launched via AWS APIs
6. **Node joins** cluster via bootstrap script
7. **Pod scheduled** on new node
8. **Consolidation** removes empty nodes after 1m

## 🔐 Security Considerations

- **IRSA**: Karpenter controller uses IAM roles for service accounts
- **Least Privilege**: Controller has only necessary EC2/IAM permissions
- **VPC Endpoints**: No public internet required for AWS API calls
- **Encryption**: KMS for secrets, EBS encryption default

## 📈 Scaling Behavior

| Scenario | Expected Nodes | Timeframe |
|----------|---------------|-----------|
| 5 pods (1 CPU each) | 1-2 t3.xlarge | 2-3 minutes |
| 10 pods | 2-3 t3.xlarge | 3-5 minutes |
| 15 pods | 3-4 t3.xlarge | 4-6 minutes |

## 🧪 Test Workload

The `inflate.yaml` deployment:
- 5 replicas
- 1 CPU, 1.5Gi memory per pod
- Uses pause container (no actual workload)
- Tests Karpenter scaling

## 📊 Monitoring Points

- **Karpenter logs**: `kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter`
- **NodeClaims**: `kubectl get nodeclaims -n karpenter -w`
- **Nodes**: `kubectl get nodes -w`
- **AWS Console**: EC2 instances, CloudWatch metrics

## 🧹 Cleanup

Run `./scripts/cleanup.sh` to:
1. Delete test deployment
2. Remove NodePool and EC2NodeClass
3. Terminate all Karpenter instances
4. Uninstall Helm release

