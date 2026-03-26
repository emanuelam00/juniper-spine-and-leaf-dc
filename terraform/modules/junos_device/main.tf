terraform {
  required_providers {
    junos = {
      source  = "juniper/junos"
      version = "~> 2.0"
    }
  }
}

# System Configuration
resource "junos_system" "this" {
  provider = junos

  hostname                 = var.hostname
  ntp_servers              = var.ntp_servers
  ntp_boot_server          = var.ntp_boot_server
  syslog_hosts             = var.syslog_hosts
  domain_name              = var.domain_name
  domain_search            = var.domain_search
  name_servers             = var.dns_servers
  snmp_community           = var.snmp_communities
  snmp_trap_options        = var.snmp_trap_options
}

# Management Interface Configuration
resource "junos_interface" "management" {
  provider = junos

  name         = "me0"
  description  = "Management Interface"
  mtu          = 1500

  inet_address {
    address = var.management_ip
    prefix  = 24
  }
}

# Loopback Interface Configuration
resource "junos_interface" "loopback" {
  provider = junos

  name         = "lo0"
  description  = "Loopback Interface"

  inet_address {
    address = var.loopback_ip
    prefix  = 32
  }

  # Secondary loopback for VXLAN VTEP (for leaf devices)
  dynamic "inet_address" {
    for_each = var.role == "leaf" && var.vtep_ip != null ? [var.vtep_ip] : []
    content {
      address = inet_address.value
      prefix  = 32
    }
  }
}

# Physical Interfaces for P2P links
resource "junos_interface" "p2p_links" {
  provider = junos

  for_each = { for idx, iface in var.interfaces : iface.name => iface }

  name         = each.value.name
  description  = each.value.description
  mtu          = lookup(each.value, "mtu", 1500)
  speed        = lookup(each.value, "speed", "100g")
  hold_time_up = lookup(each.value, "hold_time_up", 6)

  inet_address {
    address = split("/", each.value.ip_address)[0]
    prefix  = split("/", each.value.ip_address)[1]
  }
}

# Aggregated Ethernet Interfaces (LAG) - for leaf-to-access connectivity
resource "junos_interface" "ae_lag" {
  provider = junos

  for_each = { for idx, ae in var.aggregated_ethernet : ae.name => ae }

  name        = each.value.name
  description = each.value.description

  dynamic "inet_address" {
    for_each = lookup(each.value, "ip_address", null) != null ? [each.value.ip_address] : []
    content {
      address = split("/", inet_address.value)[0]
      prefix  = split("/", inet_address.value)[1]
    }
  }

  dynamic "inet6_address" {
    for_each = lookup(each.value, "ipv6_address", null) != null ? [each.value.ipv6_address] : []
    content {
      address = split("/", inet6_address.value)[0]
      prefix  = split("/", inet6_address.value)[1]
    }
  }
}

# IRB Interfaces (Integrated Routing and Bridging) for EVPN
resource "junos_interface" "irb" {
  provider = junos

  for_each = { for idx, irb in var.irb_interfaces : irb.name => irb }

  name        = each.value.name
  description = each.value.description

  dynamic "inet_address" {
    for_each = lookup(each.value, "ip_address", null) != null ? [each.value.ip_address] : []
    content {
      address = split("/", inet_address.value)[0]
      prefix  = split("/", inet_address.value)[1]
    }
  }

  dynamic "inet6_address" {
    for_each = lookup(each.value, "ipv6_address", null) != null ? [each.value.ipv6_address] : []
    content {
      address = split("/", inet6_address.value)[0]
      prefix  = split("/", inet6_address.value)[1]
    }
  }
}

# BGP Configuration
resource "junos_bgp" "this" {
  provider = junos

  asn            = var.bgp_asn
  router_id      = var.router_id
  cluster_id     = lookup(var.bgp_options, "cluster_id", null)
  graceful_restart_time = lookup(var.bgp_options, "graceful_restart_time", 120)

  # BGP Groups (one per tier or neighbor type)
  dynamic "group" {
    for_each = var.bgp_groups
    content {
      name                     = group.value.name
      type                     = group.value.type
      local_address            = group.value.local_address
      local_as                 = lookup(group.value, "local_as", null)
      peer_as                  = group.value.peer_as
      import_policy            = lookup(group.value, "import_policy", [])
      export_policy            = lookup(group.value, "export_policy", [])
      multipath                = lookup(group.value, "multipath", true)
      family_inet              = lookup(group.value, "family_inet", true)
      family_inet6             = lookup(group.value, "family_inet6", false)
      family_evpn              = lookup(group.value, "family_evpn", var.role == "leaf")
      bfd_liveness_detection   = lookup(group.value, "bfd_liveness_detection", {})

      # BGP Neighbors within this group
      dynamic "neighbor" {
        for_each = group.value.neighbors
        content {
          ip_address = neighbor.value.ip_address
          description = lookup(neighbor.value, "description", "")
        }
      }
    }
  }
}

# Routing Policies (route filters, prefix lists)
resource "junos_routing_policy" "this" {
  provider = junos

  for_each = { for policy in var.routing_policies : policy.name => policy }

  name = each.value.name

  # This is a simplified policy resource
  # In practice, you'd use local_file and junos_configuration for complex policies
  # or use the junos provider's policy resources for specific policy types
}

# Route Policy for ECMP and prefix filtering (using raw Junos config)
resource "junos_configuration" "route_policies" {
  provider = junos

  for_each = { for idx, policy in var.routing_policies : policy.name => policy }

  clean = false
  lines = [
    "policy-options policy-statement ${each.value.name} {",
    join("", [for term in each.value.terms : "  term ${term.name} { ${join("", [for action in term.actions : "${action} "])} } "]),
    "}"
  ]
}

# Firewall Filters for storm control and ACLs
resource "junos_configuration" "firewall_filters" {
  provider = junos

  for_each = { for filter in var.firewall_filters : filter.name => filter }

  clean = false
  lines = concat(
    [
      "firewall {",
      "  filter ${each.value.name} {",
    ],
    [
      for term in each.value.terms : "    term ${term.name} { from { ${join(" ", term.from_conditions)} } then { ${join(" ", term.then_actions)} } }"
    ],
    [
      "  }",
      "}",
    ]
  )
}

# Storm Control (on leaf interfaces)
resource "junos_configuration" "storm_control" {
  provider = junos

  count = var.role == "leaf" ? 1 : 0
  clean = false

  lines = concat(
    ["interfaces {"],
    [for iface in var.interfaces : "  ${iface.name} { storm-control { default } }"],
    ["}"]
  )
}

# EVPN Configuration (for leaf devices)
resource "junos_configuration" "evpn_config" {
  provider = junos

  count = var.role == "leaf" ? 1 : 0
  clean = false

  lines = concat(
    ["protocols {"],
    ["  evpn {"],
    ["    encapsulation vxlan;"],
    [for vrf in var.evpn_config.vrfs : "    vrf ${vrf.name} { vni ${vrf.vni}; }"],
    ["  }"],
    ["  bgp {"],
    ["    group EVPN {"],
    ["      family evpn;"],
    [for neighbor in var.evpn_config.spine_neighbors : "      neighbor ${neighbor.ip} { description \"${neighbor.hostname}\"; }"],
    ["    }"],
    ["  }"],
    ["}"]
  )
}

# VXLAN Configuration (for leaf devices)
resource "junos_configuration" "vxlan_config" {
  provider = junos

  count = var.role == "leaf" ? 1 : 0
  clean = false

  lines = concat(
    ["vteps {"],
    ["  vtep ${var.vtep_ip} {"],
    ["    vxlan {"],
    [for vni_config in var.evpn_config.vni_mappings : "      vni ${vni_config.vni} { vrf-target ${vni_config.vrf_target}; }"],
    ["    }"],
    ["  }"],
    ["}"]
  )
}

# Monitoring and Statistics
resource "junos_configuration" "monitoring" {
  provider = junos

  count = length(var.syslog_hosts) > 0 ? 1 : 0
  clean = false

  lines = concat(
    ["system {"],
    [for host in var.syslog_hosts : "  syslog { host ${host} { any any; } }"],
    ["  processes {"],
    ["    accounting {"],
    ["      interval 60;"],
    ["    }"],
    ["  }"],
    ["}"]
  )
}

# LLDP Configuration
resource "junos_configuration" "lldp" {
  provider = junos

  clean = false
  lines = [
    "protocols {",
    "  lldp {",
    "    management-address ${var.loopback_ip};",
    "    interface all;",
    "  }",
    "}",
  ]
}

# Device SSH and Telemetry (optional but useful)
resource "junos_configuration" "system_services" {
  provider = junos

  clean = false
  lines = [
    "system {",
    "  services {",
    "    ssh;",
    "    netconf {",
    "      ssh;",
    "    }",
    "    rest {",
    "      enable-gzip-compression;",
    "    }",
    "  }",
    "  login {",
    "    idle-timeout 15;",
    "  }",
    "}",
  ]
}
