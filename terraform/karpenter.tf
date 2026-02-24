############################
# Interruption Handling Queue
############################
resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.cluster_name}-interruption-queue"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com",
            "sqs.amazonaws.com"
          ]
        }
        Action   = "sqs:SendMessage"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-interruption-queue"
  }
}

############################
# Karpenter Node Role
############################
resource "aws_iam_role" "karpenter_node_role" {
  name = "KarpenterNodeRole-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "KarpenterNodeRole-${var.cluster_name}"
  }
}

# Node role policies (using simple count instead of for_each)
resource "aws_iam_role_policy_attachment" "karpenter_node_policies" {
  count = 4
  role  = aws_iam_role.karpenter_node_role.name

  policy_arn = element([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ], count.index)
}

############################
# Karpenter Controller Role (IRSA)
############################
resource "aws_iam_role" "karpenter_controller" {
  name = "KarpenterControllerRole-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:karpenter:karpenter"
          }
        }
      }
    ]
  })

  tags = {
    Name = "KarpenterControllerRole-${var.cluster_name}"
  }
}

# Controller policy (simplified for your style)
resource "aws_iam_role_policy" "karpenter_controller" {
  name = "KarpenterControllerPolicy-${var.cluster_name}"
  role = aws_iam_role.karpenter_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:TerminateInstances",
          "ec2:CreateLaunchTemplate",
          "ec2:DeleteLaunchTemplate",
          "ec2:CreateTags",
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory",
          "ssm:GetParameter",
          "pricing:GetProducts",
          "iam:PassRole",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:ListInstanceProfiles",
          "iam:TagInstanceProfile"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = aws_eks_cluster.eks.arn # Fixed: changed from .main to .eks
      }
    ]
  })
}

############################
# Tag Security Group for Karpenter
############################
resource "aws_ec2_tag" "karpenter_discovery_sg" {
  resource_id = aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id # Fixed: changed from .main to .eks
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

############################
# aws-auth ConfigMap (CRITICAL)
############################
resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.node_role.arn # Reference to your system node role
        username = "system:node:{{EC2PrivateDNSName}}"
        groups = [
          "system:bootstrappers",
          "system:nodes"
        ]
      },
      {
        rolearn  = aws_iam_role.karpenter_node_role.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups = [
          "system:bootstrappers",
          "system:nodes"
        ]
      }
    ])
  }

  force = true

  depends_on = [
    aws_eks_node_group.system,
    aws_iam_role.karpenter_node_role
  ]
}

############################
# Get AL2023 Version from SSM (for your YAML files)
############################
data "aws_ssm_parameter" "eks_ami" {
  name = "/aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
}

output "al2023_version" {
  description = "AL2023 version for your ec2nodeclass.yaml"
  value       = data.aws_ssm_parameter.eks_ami.value
  sensitive   = true # Add this line
}

############################
# Karpenter Instance Profile
############################
resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile-${var.cluster_name}"
  role = aws_iam_role.karpenter_node_role.name

  tags = {
    Name = "KarpenterNodeInstanceProfile-${var.cluster_name}"
  }
}