output "fabric_summary" {
  description = "Fabric configuration summary"
  value = {
    spine_count  = var.spine_count
    leaf_count   = var.leaf_count
    total_devices = var.spine_count + var.leaf_count
    racks        = var.racks
    asn_base     = var.asn_base
  }
}

output "spines" {
  description = "Spine device configurations"
  value = {
    for name, spine in module.spines : name => {
      hostname      = spine.device_id
      loopback_ip   = spine.loopback_ip
      management_ip = spine.management_ip
      bgp_asn       = spine.bgp_asn
      router_id     = spine.router_id
    }
  }
}

output "leaves" {
  description = "Leaf device configurations"
  value = {
    for name, leaf in module.leaves : name => {
      hostname      = leaf.device_id
      loopback_ip   = leaf.loopback_ip
      vtep_ip       = leaf.vtep_ip
      management_ip = leaf.management_ip
      bgp_asn       = leaf.bgp_asn
      router_id     = leaf.router_id
      evpn_config   = leaf.evpn_config
    }
  }
}

output "ip_ranges" {
  description = "IP address ranges used in the fabric"
  value = {
    spine_loopback     = var.spine_loopback_range
    leaf_loopback      = var.leaf_loopback_range
    vtep               = var.vtep_range
    p2p_links          = var.p2p_link_range
    management         = var.management_range
    access             = var.access_range
  }
}

output "vlan_vni_mapping" {
  description = "VLAN to VNI mapping for EVPN"
  value       = var.vlan_vni_mapping
}

output "bgp_config" {
  description = "BGP configuration across the fabric"
  value = {
    spine_asns = [for name, spine in module.spines : spine.bgp_asn]
    leaf_asns  = [for name, leaf in module.leaves : leaf.bgp_asn]
    policies   = {
      import = var.bgp_import_policy
      export = var.bgp_export_policy
    }
  }
}
