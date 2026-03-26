# Fabric sizing
spine_count = 4
leaf_count  = 60
racks       = 6

# Autonomous System Numbers
# Spines use 65000-65003, Leaves use 65100-65159
asn_base = 65000

# IP address ranges
spine_loopback_range = "10.0.0.0/24"       # 10.0.0.1 - 10.0.0.254
leaf_loopback_range  = "10.0.1.0/16"       # 10.0.1.1 - 10.0.255.254
vtep_range           = "10.0.128.0/24"     # 10.0.128.1 - 10.0.128.254
p2p_link_range       = "10.1.0.0/16"       # 240 * /30 subnets for 4 spines x 60 leaves
management_range     = "10.0.100.0/24"     # 10.0.100.100 - 10.0.100.200
access_range         = "10.2.0.0/16"       # 10.2.0.0 - 10.2.255.255

# VLAN to VNI mapping (example configuration)
vlan_vni_mapping = [
  {
    vlan_id        = 100
    vrf_name       = "PROD_VRF"
    vni            = 10100
    gateway_subnet = "10.100.0.0/24"
  },
  {
    vlan_id        = 200
    vrf_name       = "DEV_VRF"
    vni            = 10200
    gateway_subnet = "10.200.0.0/24"
  },
  {
    vlan_id        = 300
    vrf_name       = "TEST_VRF"
    vni            = 10300
    gateway_subnet = "10.300.0.0/24"
  },
  {
    vlan_id        = 400
    vrf_name       = "MGMT_VRF"
    vni            = 10400
    gateway_subnet = "10.400.0.0/24"
  },
]

# BGP policies
bgp_import_policy = [
  "ACCEPT-ALL"
]

bgp_export_policy = [
  "ACCEPT-ALL"
]

# Routing policies
routing_policies = [
  {
    name = "ACCEPT-ALL"
    terms = [
      {
        name    = "accept-all"
        actions = ["accept"]
      }
    ]
  },
  {
    name = "REJECT-ALL"
    terms = [
      {
        name    = "reject-all"
        actions = ["reject"]
      }
    ]
  }
]

# Firewall filters for storm control
firewall_filters = [
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
      {
        name            = "multicast"
        from_conditions = []
        then_actions    = ["policer STORM-CONTROL-MC", "accept"]
      },
    ]
  }
]

# System settings
ntp_servers = [
  "10.0.100.50",
  "10.0.100.51"
]

syslog_hosts = [
  "10.0.100.100"
]

dns_servers = [
  "10.0.100.53",
  "10.0.100.54"
]

domain_name = "dc.example.com"

# SNMP configuration
snmp_communities = [
  {
    name       = "public"
    permission = "read-only"
  },
  {
    name       = "private"
    permission = "read-write"
  }
]
