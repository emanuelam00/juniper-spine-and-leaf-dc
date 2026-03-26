variable "spine_count" {
  description = "Number of spine devices"
  type        = number
}

variable "leaf_count" {
  description = "Number of leaf devices"
  type        = number
}

variable "racks" {
  description = "Number of racks"
  type        = number
}

variable "asn_base" {
  description = "Base ASN for the fabric"
  type        = number
}

variable "spine_loopback_range" {
  description = "IP range for spine loopbacks"
  type        = string
}

variable "leaf_loopback_range" {
  description = "IP range for leaf loopbacks"
  type        = string
}

variable "vtep_range" {
  description = "IP range for VXLAN VTEPs"
  type        = string
}

variable "p2p_link_range" {
  description = "IP range for P2P spine-leaf links"
  type        = string
}

variable "management_range" {
  description = "IP range for management interfaces"
  type        = string
}

variable "access_range" {
  description = "IP range for access/server-facing interfaces"
  type        = string
}

variable "vlan_vni_mapping" {
  description = "VLAN to VNI mapping for EVPN"
  type = list(object({
    vlan_id        = number
    vrf_name       = string
    vni            = number
    gateway_subnet = string
  }))
}

variable "bgp_import_policy" {
  description = "BGP import policies"
  type        = list(string)
}

variable "bgp_export_policy" {
  description = "BGP export policies"
  type        = list(string)
}

variable "routing_policies" {
  description = "Routing policies"
  type = list(object({
    name = string
    terms = list(object({
      name       = string
      actions    = list(string)
    }))
  }))
}

variable "firewall_filters" {
  description = "Firewall filters"
  type = list(object({
    name = string
    terms = list(object({
      name            = string
      from_conditions = list(string)
      then_actions    = list(string)
    }))
  }))
}

variable "ntp_servers" {
  description = "NTP servers"
  type        = list(string)
}

variable "syslog_hosts" {
  description = "Syslog servers"
  type        = list(string)
}

variable "dns_servers" {
  description = "DNS servers"
  type        = list(string)
}

variable "domain_name" {
  description = "DNS domain name"
  type        = string
}

variable "snmp_communities" {
  description = "SNMP communities"
  type = list(object({
    name       = string
    permission = optional(string)
  }))
}
