variable "spine_count" {
  description = "Number of spine devices"
  type        = number
  default     = 4
  validation {
    condition     = var.spine_count >= 2 && var.spine_count <= 8
    error_message = "Spine count must be between 2 and 8."
  }
}

variable "leaf_count" {
  description = "Number of leaf devices"
  type        = number
  default     = 60
  validation {
    condition     = var.leaf_count >= 4 && var.leaf_count <= 256
    error_message = "Leaf count must be between 4 and 256."
  }
}

variable "racks" {
  description = "Number of racks in the datacenter"
  type        = number
  default     = 6
  validation {
    condition     = var.racks >= 1 && var.racks <= 128
    error_message = "Number of racks must be between 1 and 128."
  }
}

variable "asn_base" {
  description = "Base ASN for the fabric (spines start from asn_base, leaves from asn_base+100)"
  type        = number
  default     = 65000
  validation {
    condition     = var.asn_base >= 64512 && var.asn_base <= 65534
    error_message = "ASN base must be in private range (64512-65534)."
  }
}

variable "spine_loopback_range" {
  description = "IP range for spine loopback addresses (CIDR)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "leaf_loopback_range" {
  description = "IP range for leaf loopback addresses (CIDR)"
  type        = string
  default     = "10.0.1.0/16"
}

variable "vtep_range" {
  description = "IP range for VXLAN VTEP addresses (CIDR)"
  type        = string
  default     = "10.0.128.0/24"
}

variable "p2p_link_range" {
  description = "IP range for P2P spine-leaf links (CIDR)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "management_range" {
  description = "IP range for management interfaces (CIDR)"
  type        = string
  default     = "10.0.100.0/24"
}

variable "access_range" {
  description = "IP range for access/server-facing interfaces (CIDR)"
  type        = string
  default     = "10.2.0.0/16"
}

variable "vlan_vni_mapping" {
  description = "VLAN to VNI mapping for EVPN"
  type = list(object({
    vlan_id        = number
    vrf_name       = string
    vni            = number
    gateway_subnet = string  # CIDR notation for IRB subnet
  }))
  default = [
    {
      vlan_id        = 100
      vrf_name       = "VRF_100"
      vni            = 10100
      gateway_subnet = "10.100.0.0/24"
    },
    {
      vlan_id        = 200
      vrf_name       = "VRF_200"
      vni            = 10200
      gateway_subnet = "10.200.0.0/24"
    },
    {
      vlan_id        = 300
      vrf_name       = "VRF_300"
      vni            = 10300
      gateway_subnet = "10.300.0.0/24"
    },
  ]
}

variable "bgp_import_policy" {
  description = "BGP import policy names"
  type        = list(string)
  default     = ["ACCEPT-ALL"]
}

variable "bgp_export_policy" {
  description = "BGP export policy names"
  type        = list(string)
  default     = ["ACCEPT-ALL"]
}

variable "routing_policies" {
  description = "Routing policies to apply to all devices"
  type = list(object({
    name = string
    terms = list(object({
      name       = string
      actions    = list(string)
    }))
  }))
  default = [
    {
      name = "ACCEPT-ALL"
      terms = [
        {
          name    = "accept-all"
          actions = ["accept"]
        }
      ]
    }
  ]
}

variable "firewall_filters" {
  description = "Firewall filters to apply to all devices"
  type = list(object({
    name = string
    terms = list(object({
      name            = string
      from_conditions = list(string)
      then_actions    = list(string)
    }))
  }))
  default = [
    {
      name = "STORM-CONTROL"
      terms = [
        {
          name            = "unknown-unicast"
          from_conditions = []
          then_actions    = ["policer STORM-CONTROL-UNI", "accept"]
        },
        {
          name            = "broadcast"
          from_conditions = []
          then_actions    = ["policer STORM-CONTROL-BC", "accept"]
        },
      ]
    }
  ]
}

variable "ntp_servers" {
  description = "NTP server addresses"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "syslog_hosts" {
  description = "Syslog server addresses"
  type        = list(string)
  default     = []
}

variable "dns_servers" {
  description = "DNS server addresses"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "domain_name" {
  description = "DNS domain name"
  type        = string
  default     = "datacenter.local"
}

variable "snmp_communities" {
  description = "SNMP community configuration"
  type = list(object({
    name       = string
    permission = optional(string, "read-only")
  }))
  default = [
    {
      name       = "public"
      permission = "read-only"
    }
  ]
}
