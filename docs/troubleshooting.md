markdown
# 🔧 Troubleshooting Guide

## Common Issues and Solutions

### 1. EC2NodeClass Stuck at `Unknown`

**Symptoms:**
kubectl get ec2nodeclass default
NAME READY AGE
default Unknown 5m

text

**Check:**
```bash
kubectl describe ec2nodeclass default
Common Causes:

Issue	Solution
Missing instance profile	Create instance profile in AWS
IAM permissions missing	Add iam:TagInstanceProfile to controller role
Subnet tags incorrect	Verify karpenter.sh/discovery tag on subnets
Security group tags incorrect	Verify same tag on security groups
2. Nodes Not Joining Cluster
Symptoms:

NodeClaims stuck at Unknown

EC2 instances running but not in kubectl get nodes

Check aws-auth:

bash
kubectl get configmap aws-auth -n kube-system -o yaml | grep -A5 rolearn
You must see:

yaml
- rolearn: arn:aws:iam::ACCOUNT:role/KarpenterNodeRole-cluster
  username: system:node:{{EC2PrivateDNSName}}
  groups:
  - system:bootstrappers
  - system:nodes
Fix:

bash
kubectl edit configmap aws-auth -n kube-system
# Add the Karpenter node role if missing
3. Instance Profile Missing
Symptoms:

text
Error: creating instance profile: AccessDenied
Check:

bash
aws iam get-instance-profile --instance-profile-name KarpenterNodeInstanceProfile-cluster
Fix via Terraform:

hcl
resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile-${var.cluster_name}"
  role = aws_iam_role.karpenter_node_role.name
}
4. Karpenter Controller Pods CrashLooping
Check logs:

bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
Common Causes:

Error	Solution
Unauthorized	Check IRSA annotation on service account
AccessDenied	Add missing IAM permissions
Cluster not found	Verify cluster name in Helm values
Fix IRSA:

bash
kubectl describe pod -n karpenter -l app.kubernetes.io/name=karpenter | grep -A2 Annotations
# Should show: eks.amazonaws.com/role-arn: arn:aws:iam::...
5. AMI Discovery Fails
Symptoms:

text
failed to discover any AMIs for alias
Check:

bash
# Get correct AMI ID
aws ssm get-parameter --name "/aws/service/eks/optimized-ami/1.35/amazon-linux-2023/x86_64/standard/recommended/image_id"
Fix EC2NodeClass:

yaml
amiSelectorTerms:
  - id: "ami-0ca399aa6e8e2ce55"  # Use specific ID instead of alias
6. Nodes Not Scaling Up
Check pending pods:

bash
kubectl get pods --all-namespaces --field-selector status.phase=Pending
Check NodePool limits:

bash
kubectl get nodepool default -o yaml | grep -A5 limits
Check Karpenter logs:

bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep -i "provision\|pod"
7. Nodes Not Scaling Down
Check disruption settings:

bash
kubectl get nodepool default -o yaml | grep -A10 disruption
Check if pods have PDBs:

bash
kubectl get pdb --all-namespaces
Force consolidation:

bash
# Delete empty nodes manually
kubectl delete node <node-name>
# Karpenter will terminate the instance
8. Spot Instances Not Working
Check interruption queue:

bash
aws sqs list-queues --queue-name-prefix ${CLUSTER_NAME}
Verify IAM permissions:

bash
aws iam list-attached-role-policies --role-name KarpenterControllerRole-${CLUSTER_NAME}
9. VPC Endpoint Issues (Private Clusters)
Test connectivity:

bash
# From a pod in the cluster
kubectl run test --image=public.ecr.aws/amazonlinux/amazonlinux:latest --rm -it -- bash
curl https://ssm.ap-south-1.amazonaws.com
Verify endpoints:

bash
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=${VPC_ID}"
10. Resource Limits Reached
Check limits:

bash
kubectl get nodepool default -o yaml | grep -A5 limits
Adjust if needed:

bash
kubectl edit nodepool default
# Increase cpu limit or remove
📋 Quick Diagnostic Commands
bash
# One-liner to check everything
echo "=== KARPENTER PODS ===" && \
kubectl get pods -n karpenter && \
echo -e "\n=== EC2NODECLASS ===" && \
kubectl get ec2nodeclass -n karpenter default -o wide && \
echo -e "\n=== NODEPOOL ===" && \
kubectl get nodepool -n karpenter default -o wide && \
echo -e "\n=== AWS-AUTH (CRITICAL) ===" && \
kubectl get configmap aws-auth -n kube-system -o yaml | grep -A5 rolearn | head -10 && \
echo -e "\n=== PENDING PODS ===" && \
kubectl get pods --all-namespaces --field-selector status.phase=Pending
🆘 Getting Help
If issues persist:

Check Karpenter GitHub Issues

Review AWS EKS Documentation

Join Karpenter Slack

text

---

## ✅ **Final Step: Make Scripts Executable**

```bash
chmod +x scripts/install.sh
chmod +x scripts/verify.sh
chmod +x scripts/cleanup.sh