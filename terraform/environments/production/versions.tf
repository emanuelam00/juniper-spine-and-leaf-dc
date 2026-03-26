terraform {
  required_version = ">= 1.3.0"

  required_providers {
    junos = {
      source  = "juniper/junos"
      version = "~> 2.0"
      # Version constraint explanation:
      # ~> 2.0 means >=2.0.0 and <3.0.0
      # Adjust based on your Junos provider version requirements
    }
  }
}

# Output Terraform version information (useful for debugging)
output "terraform_version" {
  value = "${data.terraform_remote_state.this[*].terraform_version}"
}
