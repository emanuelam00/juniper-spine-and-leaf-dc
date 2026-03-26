# Juniper JunOS Spine Switch Configurations

## Overview

This directory contains production-ready JunOS configurations for a 4-spine datacenter fabric using QFX5220-32CD switches with eBGP underlay and iBGP EVPN overlay routing.

## File Structure

```
configs/
├── spine/
│   ├── dc1-spine-01.conf      # Spine 1 configuration
│   ├── dc1-spine-02.conf      # Spine 2 configuration
│   ├── dc1-spine-03.conf      # Spine 3 configuration
│   └── dc1-spine-04.conf      # Spine 4 configuration
├── templates/
│   └── spine.conf.j2          # Jinja2 template for spine generation
└── CONFIGURATION_GUIDE.md     # This file
```

## Configuration Details

### Spine Specifications

All spines use identical design patterns with unique identifiers:

| Parameter | Spine-01 | Spine-02 | Spine-03 | Spine-04 |
|-----------|----------|----------|----------|----------|
| Hostname | dc1-spine-01 | dc1-spine-02 | dc1-spine-03 | dc1-spine-04 |
| Loopback IP | 10.0.0.1/32 | 10.0.0.2/32 | 10.0.0.3/32 | 10.0.0.4/32 |
| Management IP | 10.255.0.1/24 | 10.255.0.2/24 | 10.255.0.3/24 | 10.255.0.4/24 |
| Router-ID | 10.0.0.1 | 10.0.0.2 | 10.0.0.3 | 10.0.0.4 |
| eBGP ASN | 65000 | 65000 | 65000 | 65000 |
| Subnet (P2P) | 10.1.1.0/16 | 10.1.2.0/16 | 10.1.3.0/16 | 10.1.4.0/16 |

### Interface Configuration

#### Port Breakout Architecture
- QFX5220-32CD has 32x 400G QSFP-DD ports
- Ports 0-14 broken out to 4x 100G each = 60 leaf connections
- Ports 30-31 remain 400G for firewall connectivity
- MTU: 9216 bytes (jumbo frames for VXLAN)

#### Leaf Connections (eBGP Underlay)
- **Ports et-0/0/{0-14}:{0-3}** → 60 leaf switches
  - Point-to-point /31 subnets
  - Spine side: .0, Leaf side: .1
  - Storm control on all ports (10% unknown-unicast, broadcast, multicast)
  - BFD with 300ms min-interval, multiplier 3

#### Firewall Connections (eBGP Underlay)
- **Port et-0/0/30** → dc1-fw-01 (10.2.0.{0,4,8,12}/31 per spine)
- **Port et-0/0/31** → dc1-fw-02 (10.2.0.{2,6,10,14}/31 per spine)
- Firewall ASN: 65100
- Both links active for ECMP

#### Loopback Interface (iBGP EVPN Overlay)
- lo0.0: 10.0.0.{1-4}/32
- Router-ID: same as loopback IP
- Firewall: input ACL "protect-loopback"

#### Management Interface
- em0.0: 10.255.0.{1-4}/24
- Out-of-band management only

### Routing Configuration

#### eBGP Underlay
- **Protocol**: BGP
- **Group**: ebgp-leaves
  - Type: external
  - Local ASN: 65000
  - Per-leaf ASNs: 65001-65060
  - Import policy: underlay-in (accept all)
  - Export policy: underlay-out (loopback + connected subnets)
  - ECMP: multiple-as enabled
  - BFD: 300ms/3x

#### eBGP Firewalls
- **Group**: ebgp-firewalls
  - Type: external
  - Peer ASN: 65100
  - Dual paths (FW-01, FW-02) for active-active

#### iBGP EVPN Overlay
- **Group**: RR-clients
  - Type: internal
  - Role: Route Reflector
  - Family: evpn signaling
  - All 60 leaves as RR clients
  - Cluster ID: spine's loopback IP
  - Multihop TTL: 64
  - Leaf loopback range: 10.0.101.0 - 10.0.160.0 (/32)

#### BGP Features
- Graceful restart: 300s restart-time, 600s stale-route-time
- BFD liveness detection on all sessions
- Multipath ECMP: multiple-as
- Authentication: MD5 passwords (set to placeholder)

### Routing Policies

#### underlay-out
- Exports loopback (/32 of spine)
- Exports connected subnets (10.1.0.0/16, 10.2.0.0/16)
- Denies all others

#### underlay-in
- Accepts all routes from eBGP peers

#### RR-out / RR-in
- EVPN family routes only
- Bidirectional

#### underlay-ecmp
- Per-flow load balancing hash
- Applied to forwarding table

### Security Hardening

#### SSH
- Protocol v2 only
- Root login disabled
- Max 32 sessions per connection, 32 concurrent
- Rate limit: 5 attempts

#### NETCONF
- Over SSH only
- Port 830
- Max 32 concurrent sessions

#### SNMP
- SNMPv3 only
- USM with SHA authentication + AES128 encryption
- Single view with restricted OID scope
- Trap destination: 10.255.0.252:514

#### Firewall Filters
- protect-loopback applied to lo0.0 input
- Allowed: BGP (179), BFD (3784-3785), SSH (22), SNMP (161), NTP (123), ICMP, NETCONF (830)
- Default deny all others

#### Authentication
- Root password: SHA512 encrypted ($6$PLACEHOLDER - replace with actual hash)
- netadmin user: class super-user
- Login banner: Warning message

#### NTP & Logging
- NTP servers: 10.255.0.250 (prefer), 10.255.0.251
- Syslog: 10.255.0.252:514
- Log files: messages, traffic_log
- Archive: 100MB files, 10 files retained

#### LLDP
- Enabled on all interfaces except em0, lo0
- Port ID: interface-alias
- Neighbor discovery for topology mapping

### EVPN Overlay Design

All 60 leaves are iBGP EVPN route reflector clients to all 4 spines.

**Leaf Loopback Allocation**:
- Leaf-001: 10.0.101.0
- Leaf-002: 10.0.102.0
- ...
- Leaf-060: 10.0.160.0

This allows:
- Direct iBGP peering from each leaf to all 4 spines
- Full mesh of RR clients for EVPN advertisement
- No additional VXLAN gateways required at spines

### Configuration Size

- dc1-spine-01.conf: 2,559 lines (initial version with comprehensive examples)
- dc1-spine-02/03/04.conf: ~1,169 lines each (optimized format)
- Total: ~6,058 lines across 4 spines
- 60 eBGP neighbors per spine
- 60 EVPN RR clients per spine

## Deployment Instructions

### Pre-Deployment Checklist

1. **Replace Placeholders**:
   ```
   Root password: $6$PLACEHOLDER → actual SHA512 hash
   BGP auth-keys: $9$PLACEHOLDER → actual Juniper-style hashes
   SNMP keys: $9$PLACEHOLDER → authentication/privacy passphrases
   ```

2. **Verify ASN Assignments**:
   - Confirm leaf ASN ranges: 65001-65060
   - Confirm firewall ASN: 65100

3. **Validate IP Allocations**:
   - Loopback range: 10.0.0.0/30 (spines), 10.0.100.0/24 (leaves)
   - P2P range: 10.1.0.0/16 (leaf links), 10.2.0.0/16 (fw links)
   - Management: 10.255.0.0/24

### Deployment Steps

1. **Initial Configuration**:
   ```
   request system zeroize
   [Boot into rescue mode or factory config]
   ```

2. **Load Configuration**:
   ```
   load replace relative spine/<hostname>.conf
   commit comment "Initial spine fabric deployment"
   ```

3. **Verify**:
   ```
   show bgp summary
   show bgp group
   show bgp neighbor
   show evpn database
   show route protocol bgp
   ```

4. **Monitor Convergence**:
   ```
   monitor start
   show log messages
   ```

## Jinja2 Template Usage

The `spine.conf.j2` template allows dynamic configuration generation:

```python
from jinja2 import Template

spine_vars = {
    'hostname': 'dc1-spine-01',
    'loopback_ip': '10.0.0.1',
    'mgmt_ip': '10.255.0.1',
    'router_id': '10.0.0.1',
    'asn': '65000',
    'spine_id': 1,
    'spine_asn_suffix': 1,  # For 10.1.{X}.0/16 subnet
    'generation_date': '2026-03-25',
    # Additional variables for interface numbering
}

# Render template for each spine
```

Key template variables:
- `hostname`: Device name
- `loopback_ip`: Lo0 address
- `loopback_ipv6`: Optional IPv6 loopback
- `mgmt_ip`: OOB management address
- `router_id`: BGP router identifier
- `asn`: AS number
- `spine_id`: Numeric spine identifier (1-4)
- `spine_asn_suffix`: Subnet number for P2P links

## Troubleshooting

### BGP Not Coming Up
- Verify interface IPs are assigned and up: `show interfaces terse`
- Check BGP configuration: `show configuration protocols bgp | display set`
- Monitor BGP session: `show bgp neighbor 10.1.X.Y extensive`

### EVPN Routes Not Advertising
- Verify RR cluster configuration: `show configuration protocols bgp group RR-clients`
- Check EVPN family: `show route receive-protocol bgp 10.0.101.0 family evpn`
- Monitor RR status: `show route-reflector status`

### Interface Issues
- Check interface status: `show interfaces et-0/0/X`
- Verify storm control: `show interfaces et-0/0/X statistics`
- Monitor BFD: `show bfd session`

### Performance Tuning
- ECMP load balancing: `show route extensive`
- Forwarding table: `show route forwarding-table destination <prefix>`
- BGP multipath: `show bgp group multipath`

## Support and References

- Juniper QFX5220-32CD: https://www.juniper.net/us/en/products/switches/qfx-series/qfx5220.html
- JunOS BGP: https://www.juniper.net/documentation/en_US/junos/
- EVPN RFC 7432: https://tools.ietf.org/html/rfc7432
- VXLAN RFC 7348: https://tools.ietf.org/html/rfc7348

## Version History

- **v1.0** (2026-03-25): Initial production deployment
  - 4 spine switches with 60-leaf support
  - eBGP underlay + iBGP EVPN overlay
  - Full security hardening

---

Generated: 2026-03-25
Configuration Format: JunOS Hierarchical (set-style equivalent available on request)
