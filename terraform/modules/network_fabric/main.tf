terraform {
  required_providers {
    junos = {
      source  = "juniper/junos"
      version = "~> 2.0"
    }
  }
}

# Calculate IP ranges for P2P links and loopback addresses
locals {
  # Parse IP ranges for different network segments
  spine_loopback_base   = cidrhost(var.spine_loopback_range, 0)
  leaf_loopback_base    = cidrhost(var.leaf_loopback_range, 0)
  p2p_link_base         = cidrhost(var.p2p_link_range, 0)

  # Create a map of all spines
  spines = {
    for i in range(var.spine_count) : "spine-${i + 1}" => {
      index        = i
      hostname     = "spine-${i + 1}"
      loopback_ip  = cidrhost(var.spine_loopback_range, i + 1)
      management_ip = cidrhost(var.management_range, 100 + i + 1)
      asn          = var.asn_base + (10 * 0) + i  # Spines use asn_base + 0-9
    }
  }

  # Create a map of all leaves
  leaves = {
    for i in range(var.leaf_count) : "leaf-${i + 1}" => {
      index         = i
      hostname      = "leaf-${i + 1}"
      rack_id       = floor(i / (var.leaf_count / var.racks))
      loopback_ip   = cidrhost(var.leaf_loopback_range, i + 1)
      vtep_ip       = cidrhost(var.vtep_range, i + 1)
      management_ip = cidrhost(var.management_range, 200 + i + 1)
      asn           = var.asn_base + (100 + i)  # Leaves use asn_base + 100+
    }
  }

  # Generate P2P links between spines and leaves
  # Each leaf connects to all spines with two links for redundancy
  p2p_links = merge([
    for leaf_idx, leaf_info in local.leaves : {
      for spine_idx, spine_info in local.spines : "${leaf_info.hostname}-to-${spine_info.hostname}" => {
        leaf_hostname  = leaf_info.hostname
        spine_hostname = spine_info.hostname
        leaf_index     = leaf_idx
        spine_index    = spine_idx
        # Allocate /30 subnets for P2P links
        link_index     = (leaf_idx * var.spine_count) + spine_idx
        subnet_base    = cidrhost(var.p2p_link_range, (local.link_index * 4))
        leaf_ip        = cidrhost(var.p2p_link_range, (local.link_index * 4) + 1)
        spine_ip       = cidrhost(var.p2p_link_range, (local.link_index * 4) + 2)
      }
    }
  ]...)
}

# Spine Devices
module "spines" {
  for_each = local.spines

  source = "../junos_device"

  hostname      = each.value.hostname
  management_ip = "${each.value.management_ip}/24"
  loopback_ip   = each.value.loopback_ip
  router_id     = each.value.loopback_ip
  bgp_asn       = each.value.asn
  role          = "spine"

  # P2P interfaces to leaves
  interfaces = [
    for link_name, link_info in local.p2p_links :
    {
      name        = "et-${link_info.spine_index}/${link_info.leaf_index}"
      description = "P2P to ${link_info.leaf_hostname}"
      ip_address  = "${link_info.spine_ip}/30"
      speed       = "100g"
      mtu         = 9200
      hold_time_up = 6
    }
    if link_info.spine_hostname == each.key
  ]

  # BGP Configuration
  bgp_groups = [
    {
      name          = "SPINE-LEAVES"
      type          = "external"
      local_address = each.value.loopback_ip
      peer_as       = 65001  # Will be overridden per neighbor in real deployment
      multipath     = true
      family_inet   = true
      family_evpn   = true
      import_policy = var.bgp_import_policy
      export_policy = var.bgp_export_policy
      bfd_liveness_detection = {
        minimum_interval = 300
        multiplier       = 3
      }
      neighbors = [
        for link_name, link_info in local.p2p_links :
        {
          ip_address  = link_info.leaf_ip
          description = "Leaf ${link_info.leaf_hostname}"
        }
        if link_info.spine_hostname == each.key
      ]
    }
  ]

  # Routing policies
  routing_policies = var.routing_policies

  # Firewall filters
  firewall_filters = var.firewall_filters

  # System settings
  ntp_servers   = var.ntp_servers
  syslog_hosts  = var.syslog_hosts
  dns_servers   = var.dns_servers
  domain_name   = var.domain_name

  # SNMP
  snmp_communities = var.snmp_communities
}

# Leaf Devices
module "leaves" {
  for_each = local.leaves

  source = "../junos_device"

  hostname      = each.value.hostname
  management_ip = "${each.value.management_ip}/24"
  loopback_ip   = each.value.loopback_ip
  vtep_ip       = each.value.vtep_ip
  router_id     = each.value.loopback_ip
  bgp_asn       = each.value.asn
  role          = "leaf"

  # P2P interfaces to spines
  interfaces = [
    for link_name, link_info in local.p2p_links :
    {
      name        = "et-${link_info.spine_index}/${link_info.leaf_index}"
      description = "P2P to ${link_info.spine_hostname}"
      ip_address  = "${link_info.leaf_ip}/30"
      speed       = "100g"
      mtu         = 9200
      hold_time_up = 6
    }
    if link_info.leaf_hostname == each.key
  ]

  # Access/Server interfaces (LAGs)
  aggregated_ethernet = [
    for rack_idx in range(var.racks) : {
      name        = "ae${rack_idx}"
      description = "Access LAG for Rack ${rack_idx}"
      ip_address  = "${cidrhost(var.access_range, (each.value.index * var.racks) + rack_idx)}/24"
    }
    if each.value.rack_id == rack_idx
  ]

  # IRB interfaces for EVPN
  irb_interfaces = [
    for vrf in var.vlan_vni_mapping :
    {
      name        = "irb.${vrf.vlan_id}"
      description = "IRB for VRF ${vrf.vrf_name}"
      ip_address  = "${cidrhost(vrf.gateway_subnet, each.value.index + 1)}/24"
    }
  ]

  # BGP Configuration
  bgp_groups = [
    {
      name          = "LEAF-SPINES"
      type          = "external"
      local_address = each.value.loopback_ip
      peer_as       = 65001  # Will be overridden per neighbor
      multipath     = true
      family_inet   = true
      family_evpn   = true
      import_policy = var.bgp_import_policy
      export_policy = var.bgp_export_policy
      bfd_liveness_detection = {
        minimum_interval = 300
        multiplier       = 3
      }
      neighbors = [
        for link_name, link_info in local.p2p_links :
        {
          ip_address  = link_info.spine_ip
          description = "Spine ${link_info.spine_hostname}"
        }
        if link_info.leaf_hostname == each.key
      ]
    }
  ]

  # EVPN configuration
  evpn_config = {
    vrfs = [
      for vrf in var.vlan_vni_mapping : {
        name = vrf.vrf_name
        vni  = vrf.vni
      }
    ]
    vni_mappings = [
      for vrf in var.vlan_vni_mapping : {
        vni        = vrf.vni
        vrf_target = "${var.asn_base}:${vrf.vni}"
      }
    ]
    spine_neighbors = [
      for spine_name, spine_info in local.spines : {
        ip       = spine_info.loopback_ip
        hostname = spine_name
      }
    ]
  }

  # Routing policies
  routing_policies = var.routing_policies

  # Firewall filters
  firewall_filters = var.firewall_filters

  # System settings
  ntp_servers       = var.ntp_servers
  syslog_hosts      = var.syslog_hosts
  dns_servers       = var.dns_servers
  domain_name       = var.domain_name
  snmp_communities  = var.snmp_communities

  depends_on = [module.spines]
}
