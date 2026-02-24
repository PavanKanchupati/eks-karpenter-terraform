variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "devopsshack-cluster"
}

variable "cluster_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "ssh_key_name" {
  description = "SSH key pair name for node access"
  type        = string
  default     = "DevSecOps"
}