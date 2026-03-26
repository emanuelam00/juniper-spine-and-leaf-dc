# Backend configuration for storing Terraform state
# Supports both local and remote backends

# Uncomment one of the backend configurations below:

# ============================================================================
# Option 1: Local Backend (default, for development/testing only)
# ============================================================================
# This stores state locally in a file. NOT suitable for production with
# multiple team members or CI/CD pipelines.
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }

# ============================================================================
# Option 2: Consul Backend (recommended for production)
# ============================================================================
# Stores state in HashiCorp Consul, enabling remote state sharing and
# automatic locking for safe concurrent operations.
terraform {
  backend "consul" {
    address      = "consul.dc.example.com:8500"
    scheme       = "https"
    path         = "terraform/datacenter-fabric"
    gzip         = true

    # Uncomment to enable HTTPS with client certificates
    # ca_file      = "/etc/consul/ca.crt"
    # cert_file    = "/etc/consul/client.crt"
    # key_file     = "/etc/consul/client.key"
  }
}

# ============================================================================
# Option 3: AWS S3 Backend with DynamoDB Locking
# ============================================================================
# Use this if your datacenter infrastructure is on AWS or in a hybrid setup.
# Terraform will automatically manage state locking using DynamoDB.
#
# PREREQUISITES:
# 1. Create S3 bucket: terraform-state-datacenter
# 2. Enable versioning on the bucket
# 3. Create DynamoDB table "terraform-locks" with primary key "LockID"
# 4. Set AWS credentials via environment variables or ~/.aws/credentials
#
# terraform {
#   backend "s3" {
#     bucket         = "terraform-state-datacenter"
#     key            = "datacenter-fabric/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "terraform-locks"
#   }
# }

# ============================================================================
# Option 4: Terraform Cloud/Enterprise Backend
# ============================================================================
# Use this for enterprise deployments with advanced features like VCS
# integration, team management, policy enforcement (Sentinel), and more.
#
# terraform {
#   cloud {
#     organization = "my-organization"
#     hostnames    = ["app.terraform.io"]
#     token        = var.terraform_cloud_token  # Set via TF_CLOUD_TOKEN env var
#
#     workspaces {
#       name = "datacenter-fabric-production"
#     }
#   }
# }

# ============================================================================
# Option 5: HTTP Backend (Generic Remote Backend)
# ============================================================================
# Use this for custom HTTP-based state storage servers.
#
# terraform {
#   backend "http" {
#     address        = "https://state-server.dc.example.com/terraform-state"
#     lock_address   = "https://state-server.dc.example.com/terraform-state/lock"
#     unlock_address = "https://state-server.dc.example.com/terraform-state/lock"
#     username       = var.http_backend_username
#     password       = var.http_backend_password
#     skip_cert_verification = false
#   }
# }
