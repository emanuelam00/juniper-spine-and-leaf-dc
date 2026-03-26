variable "hostname" {
  description = "Device hostname"
  type        = string
}

variable "management_ip" {
  description = "Management interface IP address with CIDR (e.g., 10.0.1.1/24)"
  type        = string
}

variable "loopback_ip" {
  description = "Loopback (lo0) IP address without prefix (e.g., 10.0.0.1)"
  type        = string
}

variable "vtep_ip" {
  description = "VXLAN VTEP IP address for leaf devices"
  type        = string
  default     = null
}

variable "router_id" {
  description = "BGP Router ID (typically same as loopback_ip)"
  type        = string
}

variable "role" {
  description = "Device role in the fabric (spine or leaf)"
  type        = string
  validation {
    condition     = contains(["spine", "leaf"], var.role)
    error_message = "Role must be either 'spine' or 'leaf'."
  }
}

variable "bgp_asn" {
  description = "BGP Autonomous System Number"
  type        = number
  validation {
    condition     = var.bgp_asn >= 1 && var.bgp_asn <= 4294967295
    error_message = "BGP ASN must be between 1 and 4294967295."
  }
}

variable "router_id" {
  description = "BGP Router ID"
  type        = string
}

variable "interfaces" {
  description = "Physical interface configurations"
  type = list(object({
    name         = string
    description  = string
    ip_address   = string  # CIDR notation, e.g., "10.1.1.1/30"
    speed        = optional(string, "100g")
    mtu          = optional(number, 1500)
    hold_time_up = optional(number, 6)
  }))
  default = []
}

variable "aggregated_ethernet" {
  description = "Aggregated Ethernet (LAG) interface configurations"
  type = list(object({
    name         = string
    description  = string
    ip_address   = optional(string)
    ipv6_address = optional(string)
  }))
  default = []
}

variable "irb_interfaces" {
  description = "IRB (Integrated Routing and Bridging) interface configurations"
  type = list(object({
    name         = string
    description  = string
    ip_address   = optional(string)
    ipv6_address = optional(string)
  }))
  default = []
}

variable "bgp_groups" {
  description = "BGP groups and neighbors configuration"
  type = list(object({
    name                   = string
    type                   = string  # internal or external
    local_address          = string
    peer_as                = number
    local_as               = optional(number)
    import_policy          = optional(list(string), [])
    export_policy          = optional(list(string), [])
    multipath              = optional(bool, true)
    family_inet            = optional(bool, true)
    family_inet6           = optional(bool, false)
    family_evpn            = optional(bool, false)
    bfd_liveness_detection = optional(map(any), {})
    neighbors = list(object({
      ip_address  = string
      description = optional(string, "")
    }))
  }))
}

variable "routing_policies" {
  description = "Routing policies for route filtering and path selection"
  type = list(object({
    name = string
    terms = list(object({
      name       = string
      actions    = list(string)
    }))
  }))
  default = []
}

variable "firewall_filters" {
  description = "Firewall filters for ACLs and storm control"
  type = list(object({
    name = string
    terms = list(object({
      name            = string
      from_conditions = list(string)
      then_actions    = list(string)
    }))
  }))
  default = []
}

variable "evpn_config" {
  description = "EVPN configuration for leaf devices"
  type = object({
    vrfs = list(object({
      name = string
      vni  = number
    }))
    vni_mappings = list(object({
      vni        = number
      vrf_target = string  # e.g., "65000:100"
    }))
    spine_neighbors = list(object({
      ip       = string
      hostname = string
    }))
  })
  default = {
    vrfs = []
    vni_mappings = []
    spine_neighbors = []
  }
}

variable "bgp_options" {
  description = "BGP global options"
  type = object({
    cluster_id             = optional(string)
    graceful_restart_time  = optional(number, 120)
  })
  default = {}
}

variable "ntp_servers" {
  description = "NTP server IP addresses"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "ntp_boot_server" {
  description = "NTP boot server IP"
  type        = string
  default     = "8.8.8.8"
}

variable "syslog_hosts" {
  description = "Syslog server IP addresses"
  type        = list(string)
  default     = []
}

variable "dns_servers" {
  description = "DNS server IP addresses"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "domain_name" {
  description = "Domain name for DNS"
  type        = string
  default     = "example.com"
}

variable "domain_search" {
  description = "DNS search domains"
  type        = list(string)
  default     = ["example.com"]
}

variable "snmp_communities" {
  description = "SNMP community strings"
  type = list(object({
    name       = string
    permission = optional(string, "read-only")
  }))
  default = []
}

variable "snmp_trap_options" {
  description = "SNMP trap options"
  type = object({
    hosts = optional(list(string), [])
  })
  default = {}
}

variable "junos_provider" {
  description = "Junos provider configuration (optional, can be set in provider block)"
  type = object({
    host     = optional(string)
    username = optional(string)
    password = optional(string)
    port     = optional(number, 830)
    sshkey   = optional(string)
  })
  default = {}
  sensitive = true
}
