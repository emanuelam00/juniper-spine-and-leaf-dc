# Datacenter Network Architecture: Juniper Spine-Leaf Fabric Design

## Executive Summary

This document describes the comprehensive architecture of a modern, highly scalable datacenter network fabric based on Juniper Networks equipment. The design employs a spine-leaf (Clos) architecture with 4 spine switches and 60 leaf switches, supporting 30 racks of compute infrastructure through an EVPN-VXLAN overlay network.

**Key Characteristics:**
- **Scale:** 60 leaf switches serving 30 racks with dual-homed server connectivity
- **Switching Capacity:** 2.88 Tbps aggregate (4 spines × 3.2 Tbps per spine)
- **Underlay Protocol:** eBGP IP Fabric with automatic failure convergence
- **Overlay Protocol:** EVPN-VXLAN with symmetric IRB and ESI-LAG multihoming
- **North-South Security:** Active-active FortiGate firewall pair with ECMP load balancing
- **High Availability:** No single point of failure in fabric; full mesh leaf-to-spine connectivity
- **Resilience:** 4-way ECMP for redundancy; automatic convergence on link/node failure

This architecture supports enterprise-grade SLAs, provides predictable low-latency performance, and enables flexible workload placement across the datacenter.

---

## Design Goals and Principles

### Architectural Goals

1. **Scalability:** Support growth from current 30 racks to potential 60+ racks with minimal architectural changes
2. **High Availability:** Eliminate single points of failure; support concurrent link/switch failures with zero packet loss
3. **Performance:** Deliver consistent, predictable latency (<5μs fabric traversal) and achieve line-rate throughput
4. **Operational Simplicity:** Minimize configuration complexity; maximize automation and standard protocols
5. **Workload Flexibility:** Support diverse workloads (VMs, containers, bare-metal) with flexible L2/L3 segmentation

### Design Principles

- **Three-Tier Architecture:** Spine (aggregation), leaf (access), and firewall (northbound gateway)
- **ECMP-First Design:** All equal-cost paths are utilized; symmetric traffic flows
- **Stateless Switching:** Each device independently forwards based on routing/bridging state; no central controller
- **Standard Protocols:** Industry-standard eBGP, EVPN, VXLAN; vendor-agnostic at control plane
- **End-to-End Encryption:** VXLAN provides logical isolation; firewall enforces policy
- **Failure Assumption:** Design assumes link or switch failure at any layer; recovery must be automatic

---

## Hardware Bill of Materials

### Switch Inventory

| Component | Model | Quantity | Role | Specification |
|-----------|-------|----------|------|----------------|
| **Spine Switches** | Juniper QFX5220-32CD | 4 | Layer 3 Spine (Core) | 32×100G/400G QSFP28/QSFP-DD ports, 3.2 Tbps throughput, 2.1 Tbps fabric bandwidth |
| **Leaf Switches** | Juniper QFX5120-48Y | 60 | Layer 2/3 Access | 48×25G SFP28 (servers) + 8×100G QSFP28 (spines), 3.2 Tbps throughput |
| **Firewalls** | FortiGate 7000 Series | 2 | Layer 4-7 Gateway | Active-active north-of-spine, 100G connectivity to all spines |

### Physical Specifications

#### Spine Switches: Juniper QFX5220-32CD

- **Port Count:** 32 ports (100G/400G capable)
- **Backplane:** 3.2 Tbps
- **Buffer Memory:** 70 MB (supporting up to 9 ms latency tolerance)
- **Latency:** <1 μs switching latency
- **Redundancy:** Dual PSU, dual RE modules (optional)
- **Management Ports:** 1× 1GE out-of-band management, console

**Spine Role Justification:**
The QFX5220 is purpose-built for the spine role. With 32 ports, we achieve 8 leaf connections per port (240 leaf uplinks / 32 = 7.5 leaves/port effective). The deep buffer and high radix make it ideal for aggregation. BGP multipath and BFD are natively supported at line rate.

#### Leaf Switches: Juniper QFX5120-48Y

- **Server Ports:** 48×25G SFP28 (downlink to compute servers)
- **Uplink Ports:** 8×100G QSFP28 (uplink to spines, 800 Gbps total uplink capacity)
- **Backplane:** 3.2 Tbps
- **Buffer Memory:** 64 MB
- **Latency:** <1 μs switching latency
- **Redundancy:** Dual PSU, single routing engine

**Leaf Role Justification:**
The QFX5120-48Y provides optimal server-to-spine ratio. With 48 server ports at 25G (1.2 Tbps server connectivity) and 8×100G uplinks (800 Gbps to spines), the oversubscription ratio is 1.5:1, suitable for consolidated datacenter workloads where 100% simultaneous uplink saturation is rare.

#### Firewall: FortiGate (North-of-Spine)

- **Deployment:** Active-active cluster with all 4 spines as next-hop
- **Connectivity:** 4×100G links (one to each spine) per FortiGate = 8×100G total northbound
- **Role:** NAT, stateful inspection, IPS, DLP, rate limiting
- **Management:** Out-of-band via separate management network

---

## Physical Topology

### Rack Layout

```
Rack 01: leaf-001 (leaf-a) + leaf-002 (leaf-b)
Rack 02: leaf-003 (leaf-a) + leaf-004 (leaf-b)
Rack 03: leaf-005 (leaf-a) + leaf-006 (leaf-b)
...
Rack 30: leaf-059 (leaf-a) + leaf-060 (leaf-b)
```

Each rack contains exactly 2 leaf switches arranged in a back-to-back configuration for maximum cable efficiency:
- **Position A (Top):** Odd-numbered leaf (leaf-a) — connects to spines via uplink ports
- **Position B (Bottom):** Even-numbered leaf (leaf-b) — connects to spines via uplink ports
- **Interconnect:** Optional direct leaf-to-leaf link for fast convergence (reserved, not used in current design)

### Spine Placement

All 4 spine switches are located in the **Core Network Room** (separate from racks):
```
┌─────────────────────────────────────────────────────────┐
│          Core Network Room (Climate Controlled)          │
├──────────────┬──────────────┬──────────────┬─────────────┤
│ dc1-spine-01 │ dc1-spine-02 │ dc1-spine-03 │ dc1-spine-04│
│ QFX5220-32CD │ QFX5220-32CD │ QFX5220-32CD │ QFX5220-32CD│
└──────────────┴──────────────┴──────────────┴─────────────┘
      ↑ 32×100G uplinks to leaves (per spine)
```

### Physical Connectivity Matrix

**Per Spine:** 32 ports (100G) available
- 30 ports → 30 leaf switches (Leaf 1-30 = primary leaf per rack, Leaf 31-60 = secondary leaf per rack)
  - Port 1 → dc1-leaf-001 uplink port 1 (Rack 01, Leaf-A)
  - Port 31 → dc1-leaf-031 uplink port 1 (Rack 16, Leaf-A)
  - Etc. for all leaves 1-60 (see Port Mapping Appendix)
- 2 ports → FortiGate pair (100G each, full 100G to FW1, full 100G to FW2)
- 0 ports → Reserved for future expansion

**Per Leaf:** 8 uplink ports (100G QSFP28)
- 4 ports → 4 spines (one 100G link per spine, enabling 4-way ECMP)
- 4 ports → Reserved for future use or direct leaf-to-leaf multihoming

**Server Connectivity:** 48 downlink ports per leaf (25G SFP28)
- Distributed across racks: 1-2 servers per port (with ESI-LAG from servers to dual leaves)

---

## IP Addressing Plan

### Management Network (Out-of-Band)

| Device Category | IP Range | Netmask | Gateway | Notes |
|-----------------|----------|---------|---------|-------|
| Spine Switches | 10.255.0.1/24 – 10.255.0.4/24 | /24 | 10.255.0.254 | 4 spines, sequential IPs |
| Leaf Switches | 10.255.1.1/24 – 10.255.1.60/24 | /24 | 10.255.1.254 | 60 leaves, sequential IPs |
| Firewall (Primary) | 10.255.2.1/24 | /24 | 10.255.2.254 | FortiGate-1 mgmt IP |
| Firewall (Secondary) | 10.255.2.2/24 | /24 | 10.255.2.254 | FortiGate-2 mgmt IP |

**Management VLAN:** VLAN 4094 (reserved, out-of-band)
**Gateway Device:** Dedicated management switch or spare port on distribution layer
**Access Control:** SSH with public key authentication; no Telnet

### Loopback Addresses

#### Spine Loopbacks (BGP Router IDs)

| Device | Loopback IP | ASN | Purpose |
|--------|-------------|-----|---------|
| dc1-spine-01 | 10.0.0.1/32 | 65000 | eBGP Router ID, EVPN VTEP |
| dc1-spine-02 | 10.0.0.2/32 | 65000 | eBGP Router ID, EVPN VTEP |
| dc1-spine-03 | 10.0.0.3/32 | 65000 | eBGP Router ID, EVPN VTEP |
| dc1-spine-04 | 10.0.0.4/32 | 65000 | eBGP Router ID, EVPN VTEP |

#### Leaf Loopbacks (BGP Router IDs)

| Device Range | IP Range | ASN Range | Purpose |
|---------------|----------|-----------|---------|
| dc1-leaf-001 to dc1-leaf-060 | 10.0.1.1/32 to 10.0.1.60/32 | 65001 to 65060 | eBGP Router ID, EVPN VTEP, ESI-LAG |

**Loopback Assignments:** Each leaf's loopback matches its leaf ID: leaf-NNN gets 10.0.1.NNN/32

### Spine-to-Leaf P2P Links (Underlay eBGP)

**Addressing Scheme:**
- Network: 10.1.0.0/16 (65,536 usable /31 subnets)
- Convention: `10.1.{spine_id}.{leaf_id*2}/31` where:
  - `spine_id` = 1–4 (per spine)
  - `leaf_id` = 1–60 (per leaf)

**Example P2P Subnets:**

| Spine | Leaf | Subnet | Spine IP | Leaf IP | Notes |
|-------|------|--------|----------|---------|-------|
| spine-01 | leaf-001 | 10.1.1.0/31 | 10.1.1.0 | 10.1.1.1 | Rack 01, Leaf-A uplink |
| spine-01 | leaf-002 | 10.1.1.2/31 | 10.1.1.2 | 10.1.1.3 | Rack 01, Leaf-B uplink |
| spine-01 | leaf-003 | 10.1.1.4/31 | 10.1.1.4 | 10.1.1.5 | Rack 02, Leaf-A uplink |
| spine-02 | leaf-001 | 10.1.2.0/31 | 10.1.2.0 | 10.1.2.1 | Spine-02 to Leaf-001 |
| spine-03 | leaf-001 | 10.1.3.0/31 | 10.1.3.0 | 10.1.3.1 | Spine-03 to Leaf-001 |
| spine-04 | leaf-001 | 10.1.4.0/31 | 10.1.4.0 | 10.1.4.1 | Spine-04 to Leaf-001 |

**Full Formula for Any Link:**
```
Subnet = 10.1.{spine_id}.{(leaf_id-1)*2}/31
  where spine_id ∈ [1,4], leaf_id ∈ [1,60]
Spine IP = network base
Leaf IP = network base + 1
```

**Capacity:** This scheme supports up to 4 spines × 65,536/2 = 131,072 potential leaf connections (vs. our 240 actual connections).

### Spine-to-Firewall P2P Links

**Addressing Scheme:**
- Network: 10.2.0.0/24 (254 usable /31 subnets)
- Convention: `10.2.0.{(spine_id-1)*4 + fw_id*2}/31`

| Spine | FW ID | Subnet | Spine IP | FW IP | 100G Link |
|-------|-------|--------|----------|-------|-----------|
| spine-01 | fw-01 | 10.2.0.0/31 | 10.2.0.0 | 10.2.0.1 | Spine-1 to FW-1 |
| spine-01 | fw-02 | 10.2.0.2/31 | 10.2.0.2 | 10.2.0.3 | Spine-1 to FW-2 |
| spine-02 | fw-01 | 10.2.0.4/31 | 10.2.0.4 | 10.2.0.5 | Spine-2 to FW-1 |
| spine-02 | fw-02 | 10.2.0.6/31 | 10.2.0.6 | 10.2.0.7 | Spine-2 to FW-2 |
| spine-03 | fw-01 | 10.2.0.8/31 | 10.2.0.8 | 10.2.0.9 | Spine-3 to FW-1 |
| spine-03 | fw-02 | 10.2.0.10/31 | 10.2.0.10 | 10.2.0.11 | Spine-3 to FW-2 |
| spine-04 | fw-01 | 10.2.0.12/31 | 10.2.0.12 | 10.2.0.13 | Spine-4 to FW-1 |
| spine-04 | fw-02 | 10.2.0.14/31 | 10.2.0.14 | 10.2.0.15 | Spine-4 to FW-2 |

### VTEP Loopbacks (EVPN-VXLAN Tunnel Endpoints)

| Device | VTEP IP | Type | Usage |
|--------|---------|------|-------|
| dc1-spine-01 to dc1-spine-04 | 10.0.0.1-4/32 | Primary Loopback | Spine VTEP for transit |
| dc1-leaf-001 to dc1-leaf-060 | 10.0.1.1-60/32 | Primary Loopback | Leaf VTEP for edge encap/decap |

**VTEP Note:** Spines act as optional transit VTEPs (enabled for Type-5 route aggregation); leaves are primary edge VTEPs.

### Server Subnets (Tenant VLANs / VXLAN)

**Address Space:** 172.16.0.0/12 (1,048,576 total IPs)

| VLAN/VNI | Subnet | Netmask | Gateway (IRB) | Purpose | VNI |
|----------|--------|---------|---------------|---------|-----|
| VLAN 100 | 172.16.1.0 | /24 | 172.16.1.254 | Compute VLAN-A | 1001 |
| VLAN 101 | 172.16.2.0 | /24 | 172.16.2.254 | Compute VLAN-B | 1002 |
| VLAN 102 | 172.16.3.0 | /24 | 172.16.3.254 | Storage Replication | 1003 |
| VLAN 110 | 172.16.10.0 | /24 | 172.16.10.254 | DMZ | 1010 |
| VLAN 120 | 172.16.20.0 | /24 | 172.16.20.254 | Database Tier | 1020 |

**IRB (Integrated Routing & Bridging):** Each VLAN has an IRB interface on all active leaf switches (symmetric IRB). Anycast gateway addresses are used to provide active-active routing.

---

## Underlay Design: eBGP IP Fabric

### Overview

The underlay routing fabric uses eBGP (external BGP) to provide flexible, scalable, and operator-friendly routing. Each leaf uses a unique ASN; all spines share ASN 65000. This "per-device" ASN approach eliminates many BGP configuration issues and provides automatic loop prevention.

### BGP Design Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| **Spine ASN** | 65000 | Common ASN for all 4 spines; simplifies filtering |
| **Leaf ASN Range** | 65001–65060 | Unique ASN per leaf; prevents accidental loops |
| **Address Family** | IPv4 Unicast + IPv4 Labeled Unicast (LU) | LU enables VXLAN tunnel auto-discovery |
| **Multipath** | eBGP multipath with maximum-paths 4 | ECMP across all 4 spines |
| **Convergence** | BFD enabled; fast-failover on link down | Sub-100ms convergence |
| **Route Propagation** | Direct loopbacks + connected P2P links | No redistribution from static routes |

### BGP Session Configuration

#### Spine Sessions (Active on All Spines)

**dc1-spine-01:**
```
BGP Process: AS 65000
Neighbors (eBGP External):
  - leaf-001 (leaf-a, rack-01): Peer IP 10.1.1.1, ASN 65001
  - leaf-002 (leaf-b, rack-01): Peer IP 10.1.1.3, ASN 65002
  - leaf-003 (leaf-a, rack-02): Peer IP 10.1.1.5, ASN 65003
  - ... (continuing for all 60 leaves)
  - firewall-01: Peer IP 10.2.0.1, ASN 65100 (or static route)
  - firewall-02: Peer IP 10.2.0.3, ASN 65100 (or static route)
```

**Applied to all 4 spines identically, with per-spine P2P addresses.**

#### Leaf Sessions (Active on All Leaves)

**dc1-leaf-001:**
```
BGP Process: AS 65001
Neighbors (eBGP External):
  - spine-01: Peer IP 10.1.1.0, ASN 65000
  - spine-02: Peer IP 10.1.2.0, ASN 65000
  - spine-03: Peer IP 10.1.3.0, ASN 65000
  - spine-04: Peer IP 10.1.4.0, ASN 65000
```

**Applies to all leaves, with ASN matching leaf ID.**

### Route Propagation

#### Advertised Routes (per leaf):

1. **Loopback Address:** 10.0.1.{leaf_id}/32 with default NEXT_HOP_SELF
2. **Direct Connected Subnets:** Optional; typically suppressed to avoid unnecessary routing state
3. **Aggregated Server Subnets:** Not announced at leaf level; only redistributed by spines toward firewalls

#### Advertised Routes (per spine):

1. **Loopback Address:** 10.0.0.{spine_id}/32
2. **Default Route (0.0.0.0/0):** Pointing toward FortiGate cluster
   - Static default route on spines with next-hop 10.2.0.1 (FW-1) or 10.2.0.5 (FW-1) depending on spine
   - Or: Learned from firewall via eBGP

### BFD (Bidirectional Forwarding Detection)

**Enabled on all BGP sessions** for sub-100ms link failure detection:

| Parameter | Value | Justification |
|-----------|-------|---------------|
| Detect Interval (Rx) | 300 ms | Leaf-to-spine link RTT ~500 ns; 300 ms provides 600x headroom |
| Transmit Interval | 100 ms | Aggressive detection without false positives |
| Multiplier | 3 | Allows 2 missed packets before declaring session down |
| **Effective Failure Detection Time** | ~300 ms | Per BFD standard (3 × 100 ms) |

**Impact:** After a link or switch failure, BGP convergence (all leaf routes updated) occurs within ~500 ms including routing table recalculation.

### ECMP and Path Selection

**Multipath Configuration (on all switches):**
```
maximum-paths 4  # Enables 4-way ECMP for leaf-to-spine paths
```

**From leaf perspective:**
- Each leaf learns 4 equal-cost paths to each of 60 other leaf loopbacks (one via each spine)
- Packets to 10.0.1.NNN are ECMP-hashed across all 4 uplink ports
- Hash function: 5-tuple (source IP, dest IP, protocol, source port, dest port)

**From spine perspective:**
- Each spine learns multiple equal-cost paths to 10.0.1.NNN destinations (one per leaf, all valid)
- Spines forward based on underlay ECMP hash

**Design Benefit:** Single link failure triggers immediate ECMP re-balancing; no packet loss for new flows, existing flows may see brief reordering.

### Route Filtering and Communities

**Import Filters (on all leaves):**
- Accept all loopback advertisements from spines and sibling leaves
- Accept default route from spines
- Reject any overlapping VTEP advertisements (to prevent VXLAN tunnel storms)

**Export Filters (on all leaves):**
- Advertise only local loopback (10.0.1.{leaf_id}/32)
- Do not advertise server subnets directly

**Communities (optional, for future policy):**
- Spines tag all loopback advertisements with RT 65000:1 (fabric-internal)
- Leaves can tag advertisements for future VRF-lite or multi-tenancy

---

## Overlay Design: EVPN-VXLAN

### Overview

The overlay provides virtual L2 and L3 forwarding across the physical fabric. EVPN (Ethernet VPN) handles MAC/IP advertisement and multi-destination delivery; VXLAN provides the encapsulation. This design supports:
- Multi-tenancy via VRF instances
- Symmetric IRB (Integrated Routing & Bridging) for inter-VLAN routing
- ESI-LAG (EVPN multihoming) for active-active server connectivity
- Redundancy without requiring spanning tree

### EVPN Route Types

| Route Type | Function | Example |
|-----------|----------|---------|
| **Type-2 (MAC/IP)** | Advertises learned MAC addresses + optional IP bindings | Server MAC learned on leaf-001 → advertised to all other leaves |
| **Type-3 (Inclusive Multicast)** | Establishes VXLAN tunnel endpoints for BUM (Broadcast, Unknown, Multicast) | All leaves join overlay multicast tree for flooded ARP |
| **Type-5 (IP Prefix)** | Advertises routed subnets for inter-VLAN traffic | IRB subnet 172.16.1.0/24 advertised via leaf; enabled on all leaves |

### VNI Allocation

| VLAN | VNI | Type | Endpoint(s) |
|------|-----|------|-------------|
| 100 | 1001 | Tenant (Compute-A) | All leaves (for VLAN 100 service) |
| 101 | 1002 | Tenant (Compute-B) | All leaves (for VLAN 101 service) |
| 102 | 1003 | Tenant (Storage) | Subset of leaves w/ storage servers |
| 110 | 1010 | Tenant (DMZ) | All leaves, with firewall IRB |
| 120 | 1020 | Tenant (DB) | Subset of leaves w/ database servers |

**VNI = 1000 + VLAN-ID** for simplicity.

### Symmetric IRB (Inter-VLAN Routing)

**Architecture:**
- Each VLAN is bridged locally on leaves
- Ingress VTEP (leaf receiving packet) classifies based on VLAN
- If destination MAC is local → forward to local port (L2)
- If destination MAC is remote or unknown → route to IRB subnet → lookup next-hop VTEP → encapsulate in VXLAN → forward to spine

**IRB Interface Configuration (per leaf, per VLAN):**

| VLAN | IRB IP (Primary) | Anycast IP (Shared) | VRF |
|------|-----------------|-------------------|-----|
| 100 | 172.16.1.1/24 (leaf-001) | 172.16.1.254/24 (all leaves) | default |
| 101 | 172.16.2.1/24 (leaf-001) | 172.16.2.254/24 (all leaves) | default |

**Anycast Gateway Behavior:**
- All leaves own the same IRB gateway IP (e.g., 172.16.1.254/24)
- ARP resolution on server always succeeds: server sends ARP for 172.16.1.254 → receives reply from local leaf (or any leaf via spine)
- Packets destined to 172.16.1.254 are routed locally (if on that leaf's VLAN) or forwarded to ingress VTEP for remote routing

**Impact:** Servers see a single, redundant default gateway; no need for HSRP/VRRP (active-active by design).

### Type-5 Route Aggregation (IP Prefix Routes)

**Enabled on all leaves** to support inter-VLAN routing across VRF boundaries (future multi-tenancy):

```
For each VLAN subnet (e.g., 172.16.1.0/24):
  - IRB owns the subnet locally
  - Advertise via EVPN Type-5 with extended community RT 10000:100
  - Other leaves import Type-5 routes into default VRF
  - Packets arriving on different VLAN can route via spine to correct VLAN's IRB
```

### MAC Learning and Advertisement

**Leaf MAC Learning Process:**
1. Server A (AA:AA:AA:AA:AA:01) sends frame on VLAN 100 (VNI 1001) to leaf-001
2. Leaf-001 learns MAC → associates with local port + VLAN 100
3. Leaf-001 generates EVPN Type-2 route: MAC AA:AA:AA:AA:AA:01, VLAN 100, RD 10.0.1.1:1001, VTEP 10.0.1.1
4. Route is advertised to all spines via eBGP EVPN address family
5. All other leaves learn the route → install in MAC table with VXLAN tunnel endpoint 10.0.1.1

**Scope:** Each leaf advertises only MACs learned on local ports; avoids unnecessary flooding.

### BUM (Broadcast, Unknown, Multicast) Handling

**Flooding Architecture:**
- Type-3 (Inclusive Multicast) routes establish VNI-to-tunnel-endpoint mapping
- All leaves interested in VNI 1001 advertise Type-3 routes
- Leaf receiving BUM packet floods to all Type-3 route participants via VXLAN replication tree

**Example:**
- Server sends ARP request (broadcast) on VLAN 100 (VNI 1001)
- Leaf-001 floods to all other leaves in the Type-3 tree
- Each leaf floods locally to attached servers on VLAN 100

**Multicast Underlay (Optional):** For very large deployments (>100 leaves), IP multicast can be used instead of unicast VXLAN replication to reduce spine traffic. Not enabled in current design.

---

## Server Connectivity and ESI-LAG Multihoming

### Dual-Homed Server Architecture

**Each server has 2× 25G network interfaces:**
- NIC-1 → Leaf-A (odd) in its rack
- NIC-2 → Leaf-B (even) in its rack
- Both NICs form a single LACP LAG from the server's perspective
- Dual leaves use ESI-LAG (EVPN multihoming) to provide active-active forwarding

### ESI (Ethernet Segment Identifier) Format

```
ESI (per rack): 00:01:01:01:01:xx:xx:00:00:00

Where:
  00:01:01:01:01 = Fixed prefix (manufacturer ID space)
  xx:xx = Rack number (00-30, or configurable)
  00:00:00 = Reserved for future use
```

**Example ESIs:**
```
Rack 01: 00:01:01:01:01:00:01:00:00:00
Rack 02: 00:01:01:01:01:00:02:00:00:00
...
Rack 30: 00:01:01:01:01:00:30:00:00:00
```

**Per-Server Distinction (Optional):**
If multiple servers per rack require unique ESIs, extend format:
```
00:01:01:01:01:rr:ss:ee:00:00
where rr = rack, ss = server slot, ee = nic/lag index
```

### LACP Configuration (Server-Side)

```
Server LAG Configuration (Linux, example):
  - LACP mode: active
  - Hash algorithm: L3+L4 (5-tuple)
  - Polling interval: 1 second (fast)
  - Aggregator select policy: stable (avoids flap)

Interface config:
  - NIC1: eth0 (25G) → bond0
  - NIC2: eth1 (25G) → bond0
  - bond0 is L3 interface (IP address, routing)
```

### ESI-LAG Configuration (Leaf-Side)

**Leaf-A (odd-numbered leaf in rack):**
```
Interface eth0:
  - MTU 9216 (VXLAN jumbo)
  - VLAN: 100, 101, 102 (trunk)
  - EVPN ESI: 00:01:01:01:01:00:01:00:00:00 (for Rack 01)
  - DF Election: Designated Forwarder mode enabled

Leaf-B (even-numbered leaf in rack):**
```
Interface eth0:
  - MTU 9216 (VXLAN jumbo)
  - VLAN: 100, 101, 102 (trunk)
  - EVPN ESI: 00:01:01:01:01:00:01:00:00:00 (same as Leaf-A!)
  - DF Election: Designated Forwarder mode enabled
```

### Designated Forwarder (DF) Election

**DF Role:** Determines which leaf (A or B) handles BUM traffic for the ESI.

| Traffic Direction | Leaf-A Role | Leaf-B Role |
|---|---|---|
| **Known Unicast (MAC learning)** | Active | Active |
| **BUM (floods, unknown)** | Designated (DF) | Non-Designated (NDF) |
| **Default Route** | Primary (lower metric) | Backup |

**DF Election Process:**
1. Both leaves advertise the same ESI via EVPN Type-4 route
2. All other leaves participate in DF voting based on BGP community tie-breaking
3. DF winner (e.g., Leaf-A with lower IP) handles all BUM traffic for the ESI
4. Non-DF (Leaf-B) discards received BUM traffic from peers (avoids duplication)

**Benefit:** Single copy of broadcast traffic, reducing bandwidth waste.

### Redundancy and Failover

**Failure Scenarios:**

| Scenario | Leaf-A | Leaf-B | Server Impact |
|----------|--------|--------|---------------|
| Leaf-A link down (NIC1 fails) | DOWN | ACTIVE | Server detects link-down on eth0; traffic flows via eth1 (leaf-B); BGP re-converges |
| Leaf-A whole switch fails | DOWN | ACTIVE | Server loses NIC1; all traffic via NIC2/eth1 (leaf-B); spines reroute via leaf-B uplinks |
| Leaf-B link down | ACTIVE | DOWN | Server detects link-down on eth1; traffic flows via NIC1/eth0 (leaf-A) |
| Spine link down (e.g., spine-01→leaf-A) | DEGRADED | ACTIVE | Leaf-A re-converges via spine-02/03/04; leaf-B unaffected; server sees no loss (redundancy) |

**Packet Loss:** Zero packet loss on link failure; brief (~500 ms) reordering possible during BGP convergence for existing TCP flows.

### Server Redundancy Configuration File Example

```yaml
# In Ansible playbook for server provisioning
---
- name: Configure LACP on compute servers
  hosts: compute_servers
  tasks:
    - name: Create bond0 interface
      netplan:
        devices:
          eth0:
            - match: {}
            - set-name: eth0
          eth1:
            - match: {}
            - set-name: eth1
        bonds:
          bond0:
            - interfaces: [eth0, eth1]
            - parameters:
                mode: 802.3ad
                mii-monitor-interval: 100
                lacp-rate: fast

    - name: Assign IP to bond0
      nmcli:
        conn_name: bond0
        type: bond
        ifname: bond0
        ip4: "{{ server_ip }}/24"
        gw4: 172.16.1.254
        state: present
```

---

## North-South Traffic Flow

### Architecture Overview

**North-South traffic** is any traffic destined to/from outside the datacenter (e.g., client → server, server → external API). This traffic must egress via the firewall cluster.

```
             ┌─────────────────┐
             │ External Network│
             │  (Internet)     │
             └────────┬────────┘
                      │
        ┌─────────────┴─────────────┐
        │                           │
    ┌─────────┐               ┌─────────┐
    │ FW-1    │               │ FW-2    │
    │ (Active)│               │ (Active)│
    │ (100G)  │               │ (100G)  │
    └────┬─┬──┘               └──┬─┬────┘
         │ │                    │ │
    ┌────┴─┴────────────────────┴─┴────┐
    │                                    │
 ┌──┴──┬──────┬──────┬──────┬──────┬──┴──┐
 │ S1  │ S2   │ S3   │ S4   │ S5   │ S6  │  (Spines)
 └──┬──┴──┬───┴──┬───┴──┬───┴──┬───┴──┬──┘
    │     │     │     │     │     │
   (60 leaves aggregate traffic)
```

### Default Route and BGP

**Spine Configuration:**
```
route 0.0.0.0/0 {
  next-hop 10.2.0.1;     # FW-1 primary path
  next-hop 10.2.0.5;     # FW-2 via spine-02 (if configured)
}
```

Or, if firewalls advertise a default route via eBGP:
```
neighbor fw-01 {
  passive;  # Listen for 0.0.0.0/0 from firewall
}
neighbor fw-02 {
  passive;  # Listen for 0.0.0.0/0 from firewall
}
```

**ECMP to Firewalls:** Each spine has an ECMP path to both FW-1 and FW-2. Packets destined to external networks are 5-tuple hashed across both firewalls.

### FortiGate Active-Active Cluster

**Deployment Mode:**
- **No Single Point of Failure:** Both firewalls independently receive all ingress traffic (via 4 spines)
- **Stateful Syncing:** Firewall state is synced via dedicated inter-FW link (not shown; typically a dedicated 10G or 100G peer link)
- **Session Distribution:** New flows are hashed; established flows maintain affinity to the firewall holding the session state

**Typical Configuration:**
```
FortiGate HA Mode: Active-Active cluster
  - Cluster IP: 10.2.0.128 (virtual, used by external systems for status checks)
  - Member 1: FW-1, Priority 100
  - Member 2: FW-2, Priority 99
  - Heartbeat: Dedicated Ethernet link (management VLAN)
  - Session sync: Real-time state replication
```

### Traffic Flow Examples

#### Scenario 1: Outbound (Server → External Client)

```
1. Server A (172.16.1.10) on leaf-001 sends packet to external IP 8.8.8.8
2. Leaf-001 L3 lookup: 8.8.8.8 is unknown → route via IRB (172.16.1.254)
3. Leaf-001 does not have VNI for external route → forwards to spine via ECMP
4. Spine (e.g., spine-01) receives packet, L3 lookup: 8.8.8.8 → 0.0.0.0/0 next-hop FW-1/FW-2
5. Spine-01 ECMP hash selects FW-1 (or FW-2 with 50% probability)
6. FW-1 receives packet, applies NAT: replace source IP 172.16.1.10 → external IP (e.g., 203.0.113.5)
7. FW-1 forwards to external network, maintains session state
8. Reply from 8.8.8.8 arrives at FW-1 (or FW-2, depending on hash)
9. Firewall performs reverse NAT, forwards back to spine
10. Spine routes to leaf-001, leaf-001 forwards to server via VXLAN
```

**Result:** Server establishes session with external host via NAT; full bidirectional communication.

#### Scenario 2: Inbound (External Client → Server, via Firewall DNAT)

```
1. External client sends packet to public IP 203.0.113.50 (DNAT mapped to 172.16.1.20)
2. Packet arrives at FW-1 (or FW-2) via upstream ISP link
3. FW applies DNAT: replace dest IP 203.0.113.50 → 172.16.1.20
4. FW-1 performs L3 lookup: 172.16.1.20 is in 172.16.0.0/12 range → datacenter fabric
5. FW-1 forwards packet to spine (e.g., spine-01)
6. Spine-01 receives packet, L3 lookup: 172.16.1.20 is in VLAN 100 → IRB route via Type-5
7. Spine-01 VXLAN-encapsulates with source VTEP spine-01 (10.0.0.1), dest VTEP leaf-001 (10.0.1.1)
8. Packet is forwarded to leaf-001
9. Leaf-001 decapsulates VXLAN, forwards to server on VLAN 100 (port with 172.16.1.20 MAC)
10. Server receives packet as if from firewall's perspective (transparent)
```

**Result:** Inbound traffic from external clients reaches intended server; firewall enforces policy/rate limits.

### North-South Policy and Security

**Typical Firewall Policies (FortiGate):**

| Policy # | Source | Destination | Service | Action | Notes |
|----------|--------|-------------|---------|--------|-------|
| 1 | Datacenter (172.16.0.0/12) | External (0.0.0.0/0) | HTTP, HTTPS | Allow + Log | Outbound web |
| 2 | Datacenter (172.16.0.0/12) | External (0.0.0.0/0) | DNS (port 53) | Allow + Log | Outbound DNS |
| 3 | Datacenter (172.16.0.0/12) | External (0.0.0.0/0) | All | Deny + Log | Implicit deny (default) |
| 10 | External (0.0.0.0/0) | DMZ (172.16.10.0/24) | HTTP, HTTPS | Allow + Log | Inbound web services |
| 11 | External (0.0.0.0/0) | Internal (172.16.0.0/12) | All | Deny + Log | Block direct external→internal |

**IPS and DLP:** Enabled on all policies; signatures updated daily.

---

## Security Architecture

### Network Segmentation (VRF and VLAN)

**Current Design (Single VRF):** All traffic in default VRF for simplicity.

**Future Multi-Tenancy:** Support for customer isolation:
```
VRF customer-A: VLAN 100-109, 172.16.0.0/24 - 172.16.9.0/24
VRF customer-B: VLAN 110-119, 172.16.10.0/24 - 172.16.19.0/24
VRF mgmt: VLAN 4094, 10.255.0.0/16
```

**Inter-VRF Routing:** Only via firewall (north-south gateway). Prevents accidental cross-customer traffic.

### Access Control and Authentication

#### Device Management Access

| Access Method | Protocol | Authentication | Authorization | Notes |
|---|---|---|---|---|
| SSH | SSH v2 | Public Key (.ssh/authorized_keys) | Role-based (admin, operator) | Primary method |
| Console | Serial (Out-of-Band) | Local username/password | admin only | Recovery access |
| SNMP | UDP 161 (read), 162 (trap) | Community string (v2c) or v3 user | Read-only | For monitoring agents |
| Syslog | UDP 514 (default) | None (implicit trust from collector) | None | One-way logging |

**SSH Key Management:**
- Each operator maintains private key; public key deployed via Ansible
- Keys stored in secure vault (e.g., HashiCorp Vault) with audit logging
- No shared accounts; all access is auditable per-user

#### Firewall Access Control

**Management Access to Firewalls:**
- FortiGate GUI (HTTPS): Username/password via LDAP or local database
- FortiGate CLI (SSH): Public key auth (same as network devices)
- Implicit: Both have 10.2.x.x addresses on spine-to-FW links (trusted internally)

### Underlay Security (eBGP Authentication)

**BGP MD5 Authentication (optional):**
```
! Spine config
neighbor 10.1.1.1 {
  remote-as 65001;
  authentication-key md5 "<secret>";  # Prevents route hijacking
}
```

**Benefit:** Prevents rogue devices from injecting false routes into the fabric. Without MD5, any device on the P2P subnet can establish a BGP session and advertise false prefixes.

**Trade-off:** Minimal CPU overhead; adds ~2 ms latency to BGP packet processing. Enabled on all production links.

### Overlay Security (VXLAN Encryption)

**Current Design:** No encryption on VXLAN tunnels (overlay is isolated by firewall policies).

**Future Enhancement (Recommended):**
```
! Leaf config
vxlan-encapsulation {
  tunnel-mode: vxlan;
  encryption: aes-256-gcm;  # Encrypts VNI payload
  key-derivation: ipsec-ikev2;
}
```

**Benefit:** Even if spine is compromised, VXLAN payloads remain encrypted in transit.

### DDoS Mitigation

**Ingress (Firewall):**
- Rate limiting on public IPs (e.g., max 100k pps per IP)
- Connection limits per source IP
- Stateless filtering of known attack signatures

**Egress (Spine/Leaf):**
- VLAN-level broadcast limits (no more than 1k bps per VLAN)
- Per-port rate limiting (if needed for rogue server containment)

### Logging and Audit Trail

**Syslog Destinations (all switches):**
```
logging host 10.255.254.1;  # Central syslog collector
logging facility LOCAL0;
logging level info;
```

**Logged Events:**
- BGP state changes (session up/down)
- EVPN route advertisements/withdrawals
- ACL match logs (policy denials)
- Configuration changes (via Syslog)
- Authentication failures (SSH, SNMP)

**Retention:** 30 days on central collector; 7 days on local device storage.

---

## High Availability Design

### Redundancy Strategy

**No Single Point of Failure:**

| Component | Quantity | Failure Impact | Recovery Time |
|-----------|----------|----------------|---|
| Spine | 4 | Loss of one spine → 3/4 ECMP paths remain; no packet loss | N/A (no loss) |
| Leaf | 60 (paired) | Loss of one leaf → server fails to one leaf; still has pair | ~500 ms BGP reconvergence |
| Uplink (Spine→Leaf) | 4 per leaf | Loss of one uplink → 3/4 ECMP paths; re-balance traffic | ~100 ms BFD detection |
| Firewall | 2 (active-active) | Loss of one FW → traffic shifts to second FW | <1 second (session state synced) |

### Failure Recovery Paths

#### Link Failure: Spine-to-Leaf Uplink Down

```
Before:
  Leaf-001 has 4 equal paths to 10.0.0.1 (spine-01 loopback):
    Path 1: via spine-01 (10.1.1.0 link)
    Path 2: via spine-02 (10.1.2.0 link)
    Path 3: via spine-03 (10.1.3.0 link)
    Path 4: via spine-04 (10.1.4.0 link)

BFD detects failure on Path 1 (~300 ms)
  → BGP session with spine-01 is declared down
  → Withdraw EVPN routes received from spine-01
  → FIB recalculates: now only 3 paths remain

After (~500 ms total):
  Leaf-001 has 3 equal paths to 10.0.0.1:
    Path 1: via spine-02 (10.1.2.0 link) [ACTIVE]
    Path 2: via spine-03 (10.1.3.0 link) [ACTIVE]
    Path 3: via spine-04 (10.1.4.0 link) [ACTIVE]

  New traffic from Leaf-001:
    - Hash 1/3 of flows via spine-02
    - Hash 1/3 of flows via spine-03
    - Hash 1/3 of flows via spine-04

  Existing flows (TCP established):
    - May see brief packet reordering if hash bucket changed
    - TCP receiver reorders packets via sequence numbers
    - No application-level impact for TCP streams
```

#### Node Failure: Complete Spine Down

```
Failure of dc1-spine-01:
  1. All 60 leaves have BGP session with spine-01
  2. BFD detects all 4 links (spine-01→leaf-001/002/003/004) are down
  3. Each leaf:
     - Withdraws all routes from spine-01
     - Recalculates FIB with remaining 3 spines
     - ECMP rehashes traffic (33% shift in traffic patterns)
  4. Traffic rerouting completes within ~500 ms
  5. Spines re-learn MAC addresses from leaf advertisements (already known via Type-2)

Result:
  - Zero packet loss for established flows
  - New flows route via spines 02, 03, 04 only
  - Leaf performance unaffected (servers don't see it)
  - Spine-01 can be offline for days without user impact
```

#### Leaf Pair Failure: Both Leaves in Rack Down

```
Failure of dc1-leaf-001 and dc1-leaf-002 (entire Rack 01):
  1. All servers in Rack 01 lose connectivity
  2. Servers detect link down on eth0/eth1 (both NICs go dark)
  3. Servers raise alarms; hypervisors initiate VM migration to other racks

Recovery path:
  - Servers in Rack 01 remain dark until replacement leaf hardware is installed
  - RTO (Recovery Time Objective): ~2-4 hours (hardware swap + configuration)
  - RPO (Recovery Point Objective): 0 (data is replicated to other servers)

Design note:
  - ESI-LAG provides failover WITHIN rack (leaf-a to leaf-b)
  - Multi-rack redundancy handled by application layer (VM replication, storage replication, etc.)
```

### Health Checks and Alerting

**Monitoring Points (per device):**

| Metric | Alert Threshold | Escalation |
|--------|---|---|
| BGP Session State | Down for >60 seconds | Page on-call engineer |
| Interface Status | Link down | Log + alert (non-blocking) |
| Temperature | >85°C on any fan | Alert; check cooling |
| PSU Status | One PSU failed (dual PSU) | Alert; plan replacement |
| Disk Usage | >80% on RE | Alert; likely not an issue |

---

## Monitoring and Observability Strategy

### Telemetry Stack

**Collection Methods:**

| Method | Protocol | Interval | Data Volume |
|--------|----------|----------|---|
| **Streaming Telemetry (Juniper)** | gRPC, mdt (OpenConfig) | 10 seconds | ~500 MB/day per device |
| **SNMP Polling** | SNMPv3 | 60 seconds | ~50 MB/day per device |
| **Syslog Events** | UDP 514 | Real-time | ~10 MB/day per device |
| **NetFlow/sFlow** | UDP 2055 / 6343 | Sampled (1:1000) | ~100 MB/day per device |

### Metrics to Collect

#### BGP Health
```
- Session state (up/down)
- Route count per neighbor (prefixes sent/received)
- Flap history (rapid up/down cycles)
- Best path selection (ECMP count)
```

#### Interface Health
```
- Link status (up/down)
- RX/TX bytes, packets, errors
- FCS errors, jabber, runts
- Queue depth (congestion indicator)
```

#### Device Health
```
- CPU utilization (forwarding plane vs. control plane)
- Memory utilization (RE, PFE)
- Temperature sensors (intake, exhaust, chipset)
- Power supply status
```

#### EVPN/VXLAN Performance
```
- MAC table size (learning rate)
- VXLAN tunnel count
- BUM (broadcast) traffic rate per VNI
- Type-2 and Type-5 route count
```

### Visualization and Alerting Tools

**Recommended Stack (Cloud-Native):**
```
Device → Telegraf (agent) → InfluxDB (TSDB) → Grafana (visualization)
                        ↓
                     Prometheus (optional, for alerting)
                        ↓
                  AlertManager → PagerDuty/Email
```

**Example Dashboard (Grafana):**
- Fabric Health: BGP session count, ECMP path utilization, VXLAN tunnel count
- Traffic Heatmap: Per-spine throughput, per-leaf uplink utilization
- Alerts: Failed sessions, high CPU, temperature warnings

---

## Capacity Planning

### Current State

| Resource | Utilized | Capacity | Utilization |
|----------|----------|----------|---|
| **Spine Ports** | 60 (leaf-facing) + 2 (FW-facing) = 62 | 128 (32×4 spines) | 48% |
| **Leaf Ports** | 1,200 (server-facing) + 240 (uplink) = 1,440 | 2,700 (48×60 leaves + 8×60 leaves) | 53% |
| **Uplink Bandwidth (per leaf)** | 1.2 Tbps (servers) | 0.8 Tbps (8×100G uplinks) | 150% **[OVERSUBSCRIBED]** |
| **Spine Throughput** | ~400 Gbps average (varies by traffic pattern) | 3.2 Tbps | <13% |

**Note:** Uplink oversubscription is **normal and expected** in datacenter fabrics. Most workloads do not saturate all 48 server ports simultaneously.

### Scaling Path (To 60 Racks)

**Current:** 30 racks, 60 leaves, 4 spines
**Target:** 60 racks, 120 leaves, 8 spines (or higher)

**Option A: Double Spines (Recommended)**
```
Current:
  4 spines × 32 ports = 128 uplink ports
  60 leaves × 4 uplinks = 240 required uplinks
  Mismatch: 240 > 128 oversubscription

Future (8 spines):
  8 spines × 32 ports = 256 uplink ports
  120 leaves × 4 uplinks = 480 required uplinks
  Still oversubscribed, but better ratio

Solution: Use higher-radix spine (QFX5220 with 48 ports)
  8 spines × 48 ports = 384 uplink ports
  120 leaves × 4 uplinks = 480 required uplinks
  Remaining: use 2 additional spine ports or dual-connect some leaves
```

**Option B: Increase Leaf Uplinks**
```
Current Leaf: 8 uplink ports to 4 spines (4-way ECMP)
Upgraded Leaf: 12 uplink ports to 4 spines (3 uplinks/spine, 12-way ECMP)

Bandwidth increase per leaf:
  8×100G = 800 Gbps → 12×100G = 1.2 Tbps

Benefit: Matches server-side 1.2 Tbps capacity; eliminates oversubscription
Trade-off: Requires leaf hardware upgrade (next-gen QFX5220-48Y2 or similar)
```

### Traffic Engineering and Oversubscription Model

**Oversubscription Ratio (Current):** 1.5:1 (1.2 Tbps servers / 0.8 Tbps uplinks)

**Oversubscription Justification:**
- **East-West Heavy:** Most traffic is within datacenter (server-to-server)
- **Limited North-South:** Outbound traffic typically 10-20% of total fabric traffic
- **No Simultaneous Saturation:** Not all 60 leaves send max traffic simultaneously

**Acceptable Scenarios:**
```
Scenario 1: Rack filling (cold start)
  - New servers added to Rack 05
  - Rack 05 leaves initialize; learn MAC addresses
  - Brief oversubscription for ARP/DHCP broadcast (milliseconds)
  - Stabilizes within seconds

Scenario 2: Large data transfer (VM migration, backup)
  - One rack migrates data to external storage
  - One leaf pair saturates uplinks for ~30 minutes
  - Remaining leaves unaffected (ECMP isolates traffic)
  - No service impact for other racks

Scenario 3: Fabric-wide disaster (all servers send data northbound)
  - Entire datacenter attempts to send to external networks
  - 1.2 Tbps server traffic → 0.8 Tbps uplinks = 400 Gbps dropped
  - Firewall and WAN are likely bottleneck anyway
  - Acceptable (rare, and external network is limiting factor)
```

### Forecasting and Upgrade Planning

**Year 1:** 30 racks → 50 racks (add 20 racks, 40 leaves, 2 spines)
- New leaves connect to existing 4-spine fabric
- Uplinks become more congested (approaching 100% in peak hours)
- Monitor link utilization via sFlow; upgrade by end of year 1

**Year 2:** 50 racks → 80 racks (add 30 racks, 60 leaves, 2 additional spines)
- Total: 120 leaves, 6 spines
- Maintain 4-way ECMP (each leaf connects to all 6 spines)
- Uplink ratio improves: 2.4 Tbps / 1.2 Tbps = 2:1 oversubscription (acceptable)

**Year 3+:** Reevaluate based on actual traffic patterns and workload changes

---

## Operational Procedures

### Configuration Management

**Tool:** Ansible + Jinja2 templates for idempotent device configuration

**Workflow:**
```
1. Update inventory file: roles/spines/inventory.yaml
2. Edit playbook: ansible/playbooks/deploy_fabric.yaml
3. Dry-run: ansible-playbook -i inventory deploy_fabric.yaml --check
4. Review diffs (highlighted in terminal)
5. Deploy: ansible-playbook -i inventory deploy_fabric.yaml
6. Verify: ansible-playbook -i inventory verify_connectivity.yaml
```

**Change Approval:** All changes require peer review (GitHub PR) + approval from network lead.

### Device Provisioning and Onboarding

**New Spine Deployment:**
```
1. Physical installation + cable verification
2. Boot loader set to auto-format disks (factory reset)
3. DHCP boot + automated image install via PXE
4. Device comes up with basic IP address (10.255.0.X)
5. Ansible playbook applies full configuration (BGP, EVPN, interfaces)
6. BGP sessions come up automatically
7. Verify routes and EVPN Type-2 routes are learned
8. Traffic forwarding verified via synthetic tests
```

**New Leaf Deployment:** Same process, but with leaf-specific configuration (different ASN, uplinks to all 4 spines).

### BGP Session Troubleshooting

**Common Issues:**

| Issue | Diagnosis | Fix |
|-------|-----------|-----|
| BGP session stuck in Idle | Check reachability: `ping 10.1.1.1` from leaf to spine P2P IP | Add static route or enable IGP |
| BGP session in Active/Connect | MD5 key mismatch | Verify MD5 key matches on both sides |
| Routes not being advertised | Check advertise policy | Verify `advertise primary-only` is not enabled |
| ECMP not working | Maximum-paths setting too low | Set `maximum-paths 4` on all devices |
| BFD flapping | BFD timers too aggressive | Increase detect-interval to 500 ms |

### MAC Address Aging and Learning

**Default Behavior:**
- Leaf learns MAC on arrival; associates with port + VLAN
- MAC is advertised via EVPN Type-2 after 1 second
- Other leaves import Type-2 route; add to forwarding table
- After 5 minutes without activity, leaf flushes MAC from local table
- After 5 minutes without activity, EVPN Type-2 is withdrawn

**Tuning (if needed):**
```
! Juniper QFX config
vlan default {
  mac-table-aging-time 600;  # 10 minutes instead of default 5
}
```

### Traffic Verification and Testing

**Synthetic Test (iperf3 between two servers):**
```bash
# On Server A (172.16.1.10)
iperf3 -s

# On Server B (172.16.1.20)
iperf3 -c 172.16.1.10 -t 30 -R
# Expected: ~1.2 Tbps throughput if both on same leaf pair
# Expected: ~800 Gbps if on different leaf pairs (uplink limited)
```

**Real-World Validation:**
- Monitor fabric utilization during known high-traffic times (e.g., nightly backups)
- Verify ECMP distribution: traffic should balance evenly across 4 spines
- Check for any asymmetric flows: if one spine carries 50%+ of traffic, investigate hash function

### Maintenance Windows and Planned Downtime

**Spine Maintenance (one at a time):**
```
1. Notify applications: "spine-01 maintenance in 1 hour"
2. Disable BGP advertisements from spine-01 (or graceful shutdown)
3. Wait 30 seconds for traffic to reroute to other 3 spines
4. Perform maintenance (software update, hardware repair, etc.)
5. Re-enable spine-01; traffic converges within ~500 ms
6. Verify no packet loss in TCP retransmit rates
```

**Leaf Maintenance (paired leaves, one pair at a time):**
```
1. Notify applications: "Rack 05 (leaf-005/leaf-006) maintenance in 1 hour"
2. Gracefully migrate VMs from Rack 05 to other racks
3. Wait for storage to sync
4. Disable leaf pair via BGP shutdown
5. Perform maintenance
6. Re-enable; VMs are brought back up (or stay migrated)
```

---

## Appendix: Port Mapping Tables

### Spine Port Allocation

**dc1-spine-01 (Ports 1-32):**

| Port | Destination Leaf | Target Device | P2P Subnet |
|------|---|---|---|
| 1 | leaf-001 | dc1-leaf-001 (rack-01, leaf-a) | 10.1.1.0/31 |
| 2 | leaf-002 | dc1-leaf-002 (rack-01, leaf-b) | 10.1.1.2/31 |
| 3 | leaf-003 | dc1-leaf-003 (rack-02, leaf-a) | 10.1.1.4/31 |
| 4 | leaf-004 | dc1-leaf-004 (rack-02, leaf-b) | 10.1.1.6/31 |
| ... | ... | ... | ... |
| 29 | leaf-057 | dc1-leaf-057 (rack-29, leaf-a) | 10.1.1.112/31 |
| 30 | leaf-058 | dc1-leaf-058 (rack-29, leaf-b) | 10.1.1.114/31 |
| 31 | fw-01 | FortiGate-1 | 10.2.0.0/31 |
| 32 | fw-02 | FortiGate-2 | 10.2.0.2/31 |

**dc1-spine-02 (Ports 1-32):**

| Port | Destination Leaf | Target Device | P2P Subnet |
|------|---|---|---|
| 1 | leaf-001 | dc1-leaf-001 (rack-01, leaf-a) | 10.1.2.0/31 |
| 2 | leaf-002 | dc1-leaf-002 (rack-01, leaf-b) | 10.1.2.2/31 |
| 3 | leaf-003 | dc1-leaf-003 (rack-02, leaf-a) | 10.1.2.4/31 |
| 4 | leaf-004 | dc1-leaf-004 (rack-02, leaf-b) | 10.1.2.6/31 |
| ... | ... | ... | ... |
| 29 | leaf-057 | dc1-leaf-057 (rack-29, leaf-a) | 10.1.2.112/31 |
| 30 | leaf-058 | dc1-leaf-058 (rack-29, leaf-b) | 10.1.2.114/31 |
| 31 | fw-01 | FortiGate-1 | 10.2.0.4/31 |
| 32 | fw-02 | FortiGate-2 | 10.2.0.6/31 |

*(Repeat for spine-03 and spine-04 with subnet 10.1.3.x and 10.1.4.x respectively)*

### Leaf Uplink Port Allocation (All 60 Leaves)

**dc1-leaf-NNN (Uplink Ports 1-4):**

| Uplink Port | Spine | P2P Subnet | Spine IP | Leaf IP |
|---|---|---|---|---|
| 1 | dc1-spine-01 | 10.1.1.{(N-1)*2}/31 | 10.1.1.{(N-1)*2} | 10.1.1.{(N-1)*2+1} |
| 2 | dc1-spine-02 | 10.1.2.{(N-1)*2}/31 | 10.1.2.{(N-1)*2} | 10.1.2.{(N-1)*2+1} |
| 3 | dc1-spine-03 | 10.1.3.{(N-1)*2}/31 | 10.1.3.{(N-1)*2} | 10.1.3.{(N-1)*2+1} |
| 4 | dc1-spine-04 | 10.1.4.{(N-1)*2}/31 | 10.1.4.{(N-1)*2} | 10.1.4.{(N-1)*2+1} |

**Example: dc1-leaf-001**

| Uplink Port | Spine | P2P Subnet | Spine IP | Leaf IP |
|---|---|---|---|---|
| 1 | dc1-spine-01 | 10.1.1.0/31 | 10.1.1.0 | 10.1.1.1 |
| 2 | dc1-spine-02 | 10.1.2.0/31 | 10.1.2.0 | 10.1.2.1 |
| 3 | dc1-spine-03 | 10.1.3.0/31 | 10.1.3.0 | 10.1.3.1 |
| 4 | dc1-spine-04 | 10.1.4.0/31 | 10.1.4.0 | 10.1.4.1 |

**Example: dc1-leaf-030 (Rack 15, Leaf-B)**

| Uplink Port | Spine | P2P Subnet | Spine IP | Leaf IP |
|---|---|---|---|---|
| 1 | dc1-spine-01 | 10.1.1.58/31 | 10.1.1.58 | 10.1.1.59 |
| 2 | dc1-spine-02 | 10.1.2.58/31 | 10.1.2.58 | 10.1.2.59 |
| 3 | dc1-spine-03 | 10.1.3.58/31 | 10.1.3.58 | 10.1.3.59 |
| 4 | dc1-spine-04 | 10.1.4.58/31 | 10.1.4.58 | 10.1.4.59 |

### Server Connectivity (Leaf Downlink Ports)

**Each leaf has 48 server-facing ports (25G SFP28), organized by rack:**

| Rack | Leaf-A | Leaf-B | Servers per Leaf | Total Servers in Rack |
|---|---|---|---|---|
| Rack 01 | leaf-001 ports 1-24 | leaf-002 ports 1-24 | 24 | 48 |
| Rack 02 | leaf-003 ports 1-24 | leaf-004 ports 1-24 | 24 | 48 |
| ... | ... | ... | 24 | 48 |
| Rack 30 | leaf-059 ports 1-24 | leaf-060 ports 1-24 | 24 | 48 |

**Port Assignment Convention:**
- Ports 1-24: Primary NIC (eth0) of servers 1-24
- Ports 25-48: Reserved or secondary NIC (eth1) for dual-homing (if needed)

**Example: Server 01 in Rack 01**
```
Server eth0 → leaf-001 (dc1-leaf-001) port 1
Server eth1 → leaf-002 (dc1-leaf-002) port 1
Server bond0 (LACP): both eth0 and eth1
```

---

## Summary and Next Steps

This architecture provides a robust, scalable, and operationally simple datacenter network fabric. The key differentiators are:

1. **Simplicity:** Standard eBGP + EVPN; no proprietary protocols
2. **Scalability:** Supports 4-way ECMP; easy to add spines and leaves
3. **Redundancy:** No single point of failure; sub-1-second convergence
4. **Performance:** Consistent <5 μs latency; high throughput
5. **Security:** Firewall north-of-spine; network segmentation via VRF/VLAN

**Immediate Next Steps:**
1. Validate IP addressing scheme in lab environment
2. Deploy Ansible playbooks to production devices
3. Activate BGP on all spine-leaf links; verify EVPN route exchange
4. Provision first VLAN (VLAN 100) and test server connectivity
5. Monitor fabric traffic patterns; adjust VLAN allocation as needed

**Long-Term Roadmap:**
- Year 1: Scale to 50 racks (add 2 spines)
- Year 2: Implement multi-tenancy via VRF; enable VXLAN encryption
- Year 3: Migrate to BGP route reflectors for hyper-scale (>200 leaves)

---

**Document Version:** 1.0
**Last Updated:** March 25, 2026
**Author:** Network Architecture Team
**Status:** Approved for Production Deployment
