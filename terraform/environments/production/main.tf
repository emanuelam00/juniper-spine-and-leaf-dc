module "datacenter_fabric" {
  source = "../../modules/network_fabric"

  # Fabric sizing
  spine_count = var.spine_count
  leaf_count  = var.leaf_count
  racks       = var.racks

  # Autonomous System Numbers
  asn_base = var.asn_base

  # IP ranges
  spine_loopback_range = var.spine_loopback_range
  leaf_loopback_range  = var.leaf_loopback_range
  vtep_range           = var.vtep_range
  p2p_link_range       = var.p2p_link_range
  management_range     = var.management_range
  access_range         = var.access_range

  # VLAN and VNI mappings
  vlan_vni_mapping = var.vlan_vni_mapping

  # BGP policies
  bgp_import_policy = var.bgp_import_policy
  bgp_export_policy = var.bgp_export_policy

  # Routing and firewall policies
  routing_policies = var.routing_policies
  firewall_filters = var.firewall_filters

  # Operational settings
  ntp_servers      = var.ntp_servers
  syslog_hosts     = var.syslog_hosts
  dns_servers      = var.dns_servers
  domain_name      = var.domain_name
  snmp_communities = var.snmp_communities
}
