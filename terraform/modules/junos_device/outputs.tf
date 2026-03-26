output "device_id" {
  description = "Device identifier (hostname)"
  value       = var.hostname
}

output "loopback_ip" {
  description = "Loopback IP address"
  value       = var.loopback_ip
}

output "management_ip" {
  description = "Management IP address"
  value       = split("/", var.management_ip)[0]
}

output "bgp_asn" {
  description = "BGP Autonomous System Number"
  value       = var.bgp_asn
}

output "router_id" {
  description = "BGP Router ID"
  value       = var.router_id
}

output "role" {
  description = "Device role (spine or leaf)"
  value       = var.role
}

output "vtep_ip" {
  description = "VXLAN VTEP IP address"
  value       = var.vtep_ip
}

output "interfaces" {
  description = "Configured interfaces"
  value = {
    loopback = var.loopback_ip
    management = split("/", var.management_ip)[0]
    p2p = [for iface in var.interfaces : {
      name = iface.name
      ip   = split("/", iface.ip_address)[0]
    }]
  }
}

output "bgp_config" {
  description = "BGP configuration summary"
  value = {
    asn      = var.bgp_asn
    router_id = var.router_id
    groups   = [for group in var.bgp_groups : group.name]
  }
}

output "evpn_config" {
  description = "EVPN configuration (leaf only)"
  value       = var.role == "leaf" ? var.evpn_config : null
}
