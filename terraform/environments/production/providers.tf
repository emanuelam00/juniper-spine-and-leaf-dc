terraform {
  required_providers {
    junos = {
      source  = "juniper/junos"
      version = "~> 2.0"
    }
  }

  # Uncomment to use remote state backend
  # backend "consul" {
  #   address = "consul.dc.example.com:8500"
  #   path    = "terraform/datacenter-fabric"
  # }

  # Alternative: AWS S3 backend
  # backend "s3" {
  #   bucket         = "terraform-state-datacenter"
  #   key            = "datacenter-fabric/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

# Provider configuration for Junos devices
# Note: Device-specific credentials should be provided via environment variables
# or Terraform variable files (*.tfvars) for security reasons

# IMPORTANT: Do not hardcode credentials here. Use one of:
# 1. Environment variables: JUNOS_HOST, JUNOS_USERNAME, JUNOS_PASSWORD
# 2. SSH key authentication: JUNOS_SSHKEY
# 3. Variable files with sensitive data marked as sensitive
# 4. CI/CD secrets management

provider "junos" {
  # Device-specific provider instances will be created per device
  # Configuration inherited from junos_provider variable in each module
}

# Example: Multiple provider aliases for different device groups
# Uncomment and customize as needed

# provider "junos" {
#   alias    = "spine-1"
#   host     = "10.0.0.101"
#   username = var.junos_username
#   password = var.junos_password
#   port     = 830
#   sshkey   = var.junos_sshkey
# }

# provider "junos" {
#   alias    = "leaf-1"
#   host     = "10.0.1.1"
#   username = var.junos_username
#   password = var.junos_password
#   port     = 830
#   sshkey   = var.junos_sshkey
# }
