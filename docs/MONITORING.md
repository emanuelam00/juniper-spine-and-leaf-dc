# Juniper Spine-Leaf Datacenter Fabric Monitoring and Observability

## Executive Summary

This document provides a comprehensive monitoring and observability strategy for a Juniper spine-leaf datacenter fabric consisting of:
- **4 Spine Switches**: QFX5220-32CD (32 x 400G QSFP-DD ports)
- **60 Leaf Switches**: QFX5120-48Y (48 x 25G SFP28 + 8 x 100G QSFP28 ports)
- **2 Firewalls**: FortiGate (edge security and egress)

**Management Network**: 10.255.0.0/8 subnet
- Spines: 10.255.0.1 through 10.255.0.4
- Leaves: 10.255.1.1 through 10.255.1.60

---

## 1. Monitoring Strategy Overview

### Four Pillars of Observability

#### 1.1 Metrics
Time-series data providing quantitative insights into system behavior and performance.

**Collection Methods**:
- SNMP v3 polling (5-minute intervals for standard metrics)
- Streaming Telemetry/gRPC (1-second intervals for real-time data)
- Application metrics via Telegraf agent

**Key Metric Categories**:
- Interface statistics (bytes in/out, errors, discards, CRC)
- Device health (CPU, memory, temperature)
- Protocol statistics (BGP, EVPN, ARP)
- Optical transceiver metrics (power levels, bit error rate)

#### 1.2 Logs
Structured event data for troubleshooting, compliance, and forensic analysis.

**Collection Methods**:
- Syslog forwarding from network devices
- Structured logging with severity levels
- Centralized aggregation using ELK Stack or Loki

**Log Categories**:
- Configuration changes
- Protocol state transitions
- Error conditions and alarms
- Authentication and authorization events

#### 1.3 Traces
Distributed tracing for understanding request flow and latency across services.

**Use Cases**:
- Application-to-application communication paths
- Latency attribution across fabric hops
- Service dependency mapping

**Implementation**: OpenTelemetry collectors integrated with application endpoints

#### 1.4 Events
Real-time notifications of significant state changes or threshold violations.

**Event Sources**:
- SNMP traps from network devices
- Prometheus alert evaluation
- Syslog severity escalations

---

## 2. SNMP Monitoring

### 2.1 SNMPv3 Configuration

SNMPv3 provides secure, encrypted SNMP communication without shared community strings.

#### Device-Side Configuration (Juniper Junos)

```junos
set snmp v3 usm local-engine user monitoring authentication-protocol md5 authentication-password "ChangeMe123!"
set snmp v3 usm local-engine user monitoring privacy-protocol aes privacy-password "ChangeMe456!"
set snmp v3 vacm security-to-group security-model usm security-name monitoring group monitoring
set snmp v3 vacm access group monitoring context default read-view all-mib
set snmp v3 access group monitoring context default security-model usm security-level auth-privacy
set snmp trap version v3
```

#### SNMPv3 Parameters (Monitoring Stack)

| Parameter | Value |
|-----------|-------|
| SNMPv3 Version | 3 |
| Username | monitoring |
| Authentication Protocol | MD5 (or SHA for FIPS compliance) |
| Privacy Protocol | AES (AES-256 for enhanced security) |
| Engine ID | Device-specific (auto-negotiated) |
| Polling Interval | 300 seconds (5 minutes) for standard metrics |
| Timeout | 10 seconds |
| Retries | 3 attempts |

### 2.2 Key OIDs for Monitoring

#### Interface Statistics
```
ifMIB (1.3.6.1.2.1.31.1.1.1)
├── ifName - Physical interface name
├── ifAlias - Interface description
├── ifOperStatus - Interface operational status (1=up, 2=down)
├── ifInOctets - Inbound octets (bytes)
├── ifOutOctets - Outbound octets (bytes)
├── ifInUcastPkts - Inbound unicast packets
├── ifOutUcastPkts - Outbound unicast packets
├── ifInErrors - Inbound error packets
├── ifOutErrors - Outbound error packets
├── ifInDiscards - Inbound discarded packets
└── ifOutDiscards - Outbound discarded packets
```

#### Juniper-Specific Optical Metrics
```
jnxExOpto (1.3.6.1.4.1.2636.3.60.4.1)
├── jnxExOpticalModuleTemperature - Transceiver temperature (Celsius)
├── jnxExOpticalModuleRxPower - Received optical power (dBm)
├── jnxExOpticalModuleTxPower - Transmitted optical power (dBm)
└── jnxExOpticalModuleAlarms - Alarm bitmap
```

#### CPU and Memory
```
jnxOperatingTable (1.3.6.1.4.1.2636.3.1.13.1)
├── jnxOperatingCPU - CPU utilization (%)
└── jnxOperatingMemory - Memory utilization (%)
```

#### System Temperature
```
jnxChassisTable (1.3.6.1.4.1.2636.3.1.2.1)
└── jnxChassisTempAlarm - Temperature alarm status
```

#### BGP State
```
bgpMIB (1.3.6.1.2.1.15)
├── bgpLocalAs - Local BGP AS number
├── bgpPeerTable - Per-peer BGP statistics
│   ├── bgpPeerState - Session state (1=idle, 2=connect, 3=active, 4=opensent, 5=openconfirm, 6=established)
│   ├── bgpPeerInUpdates - Inbound UPDATE messages
│   ├── bgpPeerOutUpdates - Outbound UPDATE messages
│   └── bgpPeerInTotalMessages - Total inbound messages
└── bgpRcvdPrefixes - Total received prefixes
```

#### EVPN/L2VPN Statistics (Juniper Extension)
```
jnxBgpL2vpnAfiTable (1.3.6.1.4.1.2636.3.1.1.4.2.4)
├── jnxBgpL2vpnPeerState - EVPN peer state
└── jnxBgpL2vpnAfiPrefixesIn - EVPN prefixes received
```

### 2.3 SNMP Polling Configuration

| Metric | OID | Interval | Retention |
|--------|-----|----------|-----------|
| Interface Status | 1.3.6.1.2.1.2.2.1.8 | 60s | 7 days |
| Interface Counters | 1.3.6.1.2.1.31.1.1.1 | 300s | 30 days |
| Optical Power | 1.3.6.1.4.1.2636.3.60.4.1 | 300s | 7 days |
| CPU/Memory | 1.3.6.1.4.1.2636.3.1.13.1 | 300s | 7 days |
| Temperature | 1.3.6.1.4.1.2636.3.1.2.1 | 300s | 1 day |
| BGP State | 1.3.6.1.2.1.15.3.1.2 | 60s | 7 days |
| BGP Counters | 1.3.6.1.2.1.15.3.1 | 300s | 30 days |
| EVPN Stats | 1.3.6.1.4.1.2636.3.1.1.4.2.4 | 300s | 30 days |

---

## 3. Streaming Telemetry (gRPC/OpenConfig)

### 3.1 Juniper Telemetry Interface (JTI) Overview

JTI enables high-frequency streaming of operational data directly to collectors without polling overhead. Recommended for real-time visibility into interface counters, BGP state changes, and protocol events.

### 3.2 JTI Configuration (Juniper Junos)

```junos
set system services netconf rfc-compliant
set system services netconf notification

# Configure JTI server on port 50000
set services jti request interface-statistics
set services jti request interface-statistics timestamp microseconds
set services jti request bgp-rib
set services jti request system
set services jti request firewall

# Configure streaming to remote collector
set services jti streaming-server subscriber-server port 50000
set services jti streaming-server subscriber-server transport grpc
set services jti stream interface-stats frequency 1000
set services jti stream bgp-updates frequency 5000
```

### 3.3 OpenConfig Sensor Paths

OpenConfig provides vendor-neutral YANG models for consistent telemetry across multi-vendor environments.

#### Interface Counters and State
```
openconfig-interfaces:/interfaces/interface[name=*]
├── state/counters/in-octets
├── state/counters/out-octets
├── state/counters/in-errors
├── state/counters/out-errors
├── state/counters/in-discards
├── state/counters/out-discards
├── state/oper-status
└── state/admin-status
```

#### BGP State
```
openconfig-bgp:/bgp
├── global/state/as
├── global/state/total-paths
├── global/state/total-prefixes
├── neighbors/neighbor[neighbor-address=*]
│   ├── state/session-state
│   ├── state/messages/sent/updates
│   ├── state/messages/received/updates
│   └── afi-safis/afi-safi[afi-safi-name=*]/state/prefixes-sent
└── rib/af-safi[afi-safi-name=*]/state/total-paths
```

#### System Health
```
openconfig-system:/system
├── state/hostname
├── state/domain-name
├── state/boot-time
└── cpu/state/usage
```

#### Optical Transceiver
```
openconfig-platform:/components/component[name=*]
├── transceiver/state/module-functional-type
├── transceiver/state/presence
├── transceiver/physical-channels/channel[index=*]
│   ├── state/input-power
│   ├── state/output-power
│   └── state/laser-bias-current
└── state/temperature/instant
```

### 3.4 gNMI Configuration

gNMI (gRPC Network Management Interface) is the standard protocol for OpenConfig telemetry.

```yaml
# gNMI target configuration (on monitoring collector)
targets:
  - name: spine-01
    address: 10.255.0.1:50000
    credentials:
      username: monitoring
      password: ChangeMe123!
    subscriptions:
      - path: /interfaces/interface/state
        mode: STREAM
        stream_mode: ON_CHANGE
      - path: /bgp/neighbors/neighbor/state
        mode: STREAM
        stream_mode: ON_CHANGE
      - path: /system/cpu/state
        mode: SAMPLE
        sample_interval: 10000000000  # 10 seconds in nanoseconds
```

### 3.5 Telegraf Collector Configuration

```toml
# Telegraf gNMI input plugin
[[inputs.gnmi]]
addresses = ["10.255.0.1:50000", "10.255.0.2:50000", "10.255.0.3:50000", "10.255.0.4:50000"]
username = "monitoring"
password = "ChangeMe123!"
redial = "10s"
keepalive = "30s"

# Subscribe to interface statistics
[[inputs.gnmi.subscription]]
name = "interface-stats"
origin = "openconfig-interfaces"
path = "/interfaces/interface/state/counters"
subscription_mode = "STREAM"

# Subscribe to BGP state
[[inputs.gnmi.subscription]]
name = "bgp-state"
origin = "openconfig-bgp"
path = "/bgp/neighbors/neighbor/state"
subscription_mode = "ON_CHANGE"

# Subscribe to system metrics
[[inputs.gnmi.subscription]]
name = "system-health"
origin = "openconfig-system"
path = "/system"
subscription_mode = "SAMPLE"
sample_interval = 10000000000
```

---

## 4. Syslog Management

### 4.1 Syslog Configuration (Juniper Junos)

```junos
set system syslog host 10.254.10.10 any notice
set system syslog host 10.254.10.10 authorization info
set system syslog host 10.254.10.10 bgp notice
set system syslog host 10.254.10.10 kernel warning
set system syslog host 10.254.10.10 daemon notice
set system syslog host 10.254.10.10 firewall warning
set system syslog host 10.254.10.10 ftp notice
set system syslog host 10.254.10.10 ntp notice
set system syslog host 10.254.10.10 interfaces notice
set system syslog host 10.254.10.10 routing-daemon notice
set system syslog host 10.254.10.10 security notice
set system syslog host 10.254.10.10 pfe warning

set system syslog file /var/log/messages any notice
set system syslog file /var/log/security authentication info
set system syslog file /var/log/bgp bgp notice
set system syslog file /var/log/firewall firewall warning
set system syslog file /var/log/interfaces interfaces notice
```

### 4.2 Syslog Severity Levels

| Severity | Level | Meaning |
|----------|-------|---------|
| 0 | EMERG | Emergency - system is unusable |
| 1 | ALERT | Alert - action must be taken immediately |
| 2 | CRIT | Critical - critical condition occurred |
| 3 | ERR | Error - error condition |
| 4 | WARNING | Warning - warning condition |
| 5 | NOTICE | Notice - normal but significant condition |
| 6 | INFO | Informational - informational message |
| 7 | DEBUG | Debug - debug-level message |

### 4.3 Facility Codes (BSD Syslog)

| Facility | Code | Junos Keyword |
|----------|------|---------------|
| 0 | KERN | kernel |
| 1 | USER | - |
| 4 | AUTH | authorization |
| 5 | SYSLOG | - |
| 10 | AUTHPRIV | - |
| 16 | LOCAL0 | - |
| 17 | LOCAL1 | - |
| 18 | LOCAL2 | bgp |
| 19 | LOCAL3 | daemon |
| 20 | LOCAL4 | firewall |
| 21 | LOCAL5 | interfaces |
| 22 | LOCAL6 | routing-daemon |
| 23 | LOCAL7 | ntp |

### 4.4 Log Aggregation with Loki

Loki provides a logs aggregation backend compatible with Prometheus and Grafana.

**Loki Configuration**:
```yaml
auth_enabled: false

ingester:
  chunk_idle_period: 3m
  max_chunk_age: 1h
  max_streams_per_user: 5000

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: s3
      schema: v12
      index:
        prefix: loki_index_
        period: 24h

storage_config:
  s3:
    s3: s3://user:pass@host:port/bucket
```

---

## 5. Key Metrics and Alerts

### 5.1 Interface Metrics

#### Critical Thresholds

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Utilization (inbound) | 70% | 85% | Page on-call, prepare capacity plan |
| Utilization (outbound) | 70% | 85% | Page on-call, prepare capacity plan |
| Error Rate | >0.1% | >1% | Page on-call, investigate errors |
| CRC Errors | >100/5min | >1000/5min | Replace optic module |
| RX Power (below) | -8 dBm | -15 dBm | Replace optic, check connectivity |
| RX Power (above) | +5 dBm | +10 dBm | Replace optic, check for reflections |
| Interface Down | N/A | Any | Immediate notification, failover check |
| Discards (inbound) | >1000/5min | >5000/5min | Investigate policing, buffer issues |

### 5.2 BGP and EVPN Metrics

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| BGP Neighbor Down | N/A | Immediate | Page on-call, check peer connectivity |
| BGP Route Flapping | >3 in 60s | >10 in 60s | Page on-call, investigate stability |
| BGP Prefix Count (increase) | >20% in 1h | >50% in 1h | Investigate route leaks |
| BGP Prefix Count (decrease) | >10% in 1h | >30% in 1h | Check peer stability, route filters |
| EVPN MAC Count Growth | >10% daily | >30% daily | Investigate MAC moves, check for loops |
| Type-5 Route Withdrawal | >3 in 1h | >10 in 1h | Check external route distribution |
| ARP Entry Count | >50K | >100K | Investigate gratuitous ARP, subnet sizing |

### 5.3 System Metrics

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| CPU Utilization | >60% | >80% | Investigate, check for runaway processes |
| Memory Utilization | >70% | >85% | Investigate memory leaks, consider reboot |
| Temperature (Intake) | >40°C | >50°C | Check cooling, prepare for failover |
| Temperature (Exhaust) | >50°C | >60°C | Check cooling, prepare for failover |
| DRAM Bit Errors (correctable) | >100/h | >1000/h | Schedule replacement |
| Disk Utilization | >70% | >85% | Cleanup logs or schedule replacement |
| NTP Offset | >100ms | >500ms | Investigate time sync, check NTP peers |

### 5.4 Fabric-Specific Metrics

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| ECMP Imbalance | >15% deviation | >30% deviation | Rebalance traffic, check for failed paths |
| Spine Failure | N/A | 1 spine down | Immediate failover, page on-call |
| Leaf Isolation | 1 link down | 2+ links down | Check cable, optics, investigate topology |
| BGP Session Loss (spine) | 1 session | 2+ sessions | Immediate page, check connectivity |
| Multicast Tree Failure | N/A | Immediate | Page on-call, check tree state |

### 5.5 SLA Metrics

| Metric | Target | Warning | Critical | Action |
|--------|--------|---------|----------|--------|
| Intra-Fabric Latency (leaf-to-leaf) | <100µs | >150µs | >200µs | Investigate, check for congestion |
| Jitter (leaf-to-leaf) | <50µs | >75µs | >100µs | Check queue behavior, buffer sizes |
| Fabric Packet Loss | <0.001% | >0.01% | >0.1% | Investigate errors/drops, check FEC |
| EVPN Convergence | <500ms | >750ms | >1s | Check protocol timers, BFD settings |

### 5.6 Complete Alert Rules Table

| Alert Name | Condition | Severity | Impact | Escalation |
|------------|-----------|----------|--------|------------|
| InterfaceDown | ifOperStatus == 2 for 60s | CRITICAL | Loss of connectivity | Immediate page |
| HighInterfaceUtilization | ifInOctets > 85% link rate for 5min | WARNING | Potential congestion | Normal ticket |
| InterfaceErrors | ifInErrors > 100/5min | WARNING | Potential link quality issue | Investigation queue |
| HighCRCErrors | jnxExOpticalCRCErrors > 1000/5min | CRITICAL | Link integrity compromised | Immediate page |
| OpticalPowerLow | jnxExOpticalRxPower < -15 dBm | CRITICAL | Link may fail | Immediate page |
| OpticalPowerHigh | jnxExOpticalRxPower > +10 dBm | WARNING | Potential reflections | Investigation queue |
| BGPNeighborDown | bgpPeerState != 6 for 60s | CRITICAL | Loss of routing | Immediate page |
| BGPRouteFlapping | bgpPeerInUpdates rate > 10/min | WARNING | Unstable routing | Investigation queue |
| HighCPUUsage | jnxOperatingCPU > 80% for 5min | CRITICAL | Performance degradation | Immediate page |
| HighMemoryUsage | jnxOperatingMemory > 85% for 5min | CRITICAL | Potential crashes | Immediate page |
| HighTemperature | jnxChassisTemp > 55°C | CRITICAL | Hardware damage risk | Immediate page |
| ECMPImbalance | Max path utilization - Min path > 30% | WARNING | Suboptimal capacity usage | Investigation queue |
| SpineFailure | Spine device down | CRITICAL | Fabric partitioning risk | Immediate page |
| EVPNMACFlapping | MAC moved >5 times in 60s | WARNING | Potential loop/issue | Investigation queue |
| Type5WithdrawalSpike | Type-5 routes decreased >30% in 1h | CRITICAL | Loss of external routes | Immediate page |

---

## 6. Dashboard Design

### 6.1 Fabric Overview Dashboard

**Purpose**: High-level view of entire fabric health and capacity

**Key Panels**:

1. **Spine Status Grid** (4 rows)
   - Spine name, uptime, CPU/memory/temp gauges
   - BGP peer count, route count
   - Interface status (count of up/down/error interfaces)
   - Color coding: Green (healthy), Yellow (warning), Red (critical)

2. **Leaf Status Grid** (60 rows, paginated by 10)
   - Leaf name, uptime, device role
   - CPU/memory utilization as percentage bars
   - Linked interface status counts
   - Hover to show details

3. **BGP Session Health**
   - Total established/failed/down sessions
   - Breakdown by spine
   - Per-peer state matrix

4. **Interface Utilization Top-N**
   - Top 10 highest utilized interfaces (inbound)
   - Top 10 highest utilized interfaces (outbound)
   - Sorted by utilization percentage

5. **Error Rate Overview**
   - Interface error count (trending)
   - CRC error count (trending)
   - Drop/discard count (trending)

6. **System Health Heatmap**
   - CPU across all devices
   - Memory across all devices
   - Temperature across all devices
   - Color intensity = utilization level

### 6.2 Per-Device Dashboard

**Purpose**: Deep dive into individual device metrics

**Key Panels**:

1. **Device Overview Card**
   - Serial number, model, OS version
   - Uptime, last reboot, last config change
   - Management IP, device role

2. **Interface Table**
   - All interfaces with status, utilization, error count
   - Sortable, filterable, search
   - Trending sparklines for each metric

3. **Interface Detail View** (selected interface)
   - 24-hour utilization graph (in/out)
   - Error/discard counters (time series)
   - Optical power (RX/TX, if applicable)
   - Last 100 syslog entries for that interface

4. **BGP Neighbor Table**
   - All BGP neighbors with state, route count
   - Uptime, last state change
   - Message rate (updates/second)

5. **System Health Trends**
   - CPU utilization (24-hour graph)
   - Memory utilization (24-hour graph)
   - Temperature (24-hour graph)
   - Process table (top CPU consumers)

6. **Syslog Stream**
   - Real-time syslog entries from device
   - Filterable by severity/facility
   - Last 1000 entries searchable

### 6.3 BGP/EVPN Dashboard

**Purpose**: Routing protocol state and convergence monitoring

**Key Panels**:

1. **BGP Session Matrix**
   - Row per spine/leaf, column per ASN
   - Cell color: Green (established), Red (down), Yellow (flapping)
   - Hover shows last state change time

2. **Route Count Trends**
   - Total routes received per device
   - Type-2 (MAC) routes in EVPN
   - Type-5 (external) routes trending
   - Per-BGP-peer breakdown

3. **Route Flapping Detection**
   - Number of flaps per peer (last 1h)
   - Top 10 most unstable prefixes
   - Trend indicator

4. **BGP Convergence Time**
   - Time to converge after interface down event
   - Measured across multiple leaves
   - SLA target indicator

5. **EVPN MAC Events**
   - New MAC learned count (trending)
   - MAC moves per leaf
   - Multicast tree status per leaf

6. **Path Utilization Distribution**
   - Histogram of utilization across ECMP paths
   - Per-aggregate indicator
   - Imbalance detection

### 6.4 Capacity Planning Dashboard

**Purpose**: Trend analysis and growth forecasting

**Key Panels**:

1. **Interface Utilization Growth Trend**
   - Average utilization over 30/60/90 days
   - Per-interface-role breakdown (spine-leaf, leaf-access, etc.)
   - Linear regression forecast (next 90 days)

2. **Route Count Growth**
   - Total BGP routes trending
   - EVPN MAC count trending
   - Forecast based on growth rate

3. **Optics Health Trend**
   - Average RX/TX power levels
   - Temperature trend
   - BER (bit error rate) if available

4. **Capacity Headroom**
   - Port utilization distribution
   - Available bandwidth summary
   - Upgrade recommendations

5. **Resource Utilization Projections**
   - CPU utilization forecast
   - Memory utilization forecast
   - Temperature projection

---

## 7. Log Analysis and Correlation

### 7.1 Log Parsing and Structure

Structured logging enables correlation across events and systems.

**Example Log Entry** (syslog):
```
<174>Mar 25 14:32:18 spine-01 bgpd[4521]: BGP_NEIGHBOR_STATE_CHANGED: BGP peer 10.1.0.1 (as 65100) state changed from OpenConfirm to Established
```

**Parsed Fields**:
- **Timestamp**: 2026-03-25T14:32:18Z
- **Source Device**: spine-01
- **Process**: bgpd (BGP daemon)
- **Facility**: LOCAL2 (BGP)
- **Severity**: Notice (5)
- **Message Type**: BGP_NEIGHBOR_STATE_CHANGED
- **Peer Address**: 10.1.0.1
- **Peer ASN**: 65100
- **Event**: State transition

### 7.2 Event Correlation Logic

**Correlated Event Examples**:

1. **Interface Flapping Detection**
   ```
   IF (Interface Down + 60s) AND (Interface Up + 60s) AND (Repeat >3 in 5min)
   THEN Raise "Interface Flapping" alert
   ```

2. **BGP Convergence on Failure**
   ```
   IF (Interface Down) THEN Start timer
   IF (All BGP routes re-established) THEN Mark convergence time
   Alert if convergence_time > SLA_target
   ```

3. **Cascade Failure Detection**
   ```
   IF (Spine device down) AND (>10 leaf devices losing connectivity)
   THEN Raise "Cascading Failure" alert
   ```

4. **Duplicate MAC Detection**
   ```
   IF (Same MAC seen on 2+ interfaces within 1s)
   THEN Log duplicate MAC event
   ELSE If MAC moved >5 times in 1min, raise MAC flapping alert
   ```

### 7.3 Log Queries (Loki)

**Example Queries**:

```loki
# BGP state changes on a specific device
{job="syslog", device="spine-01", facility="bgp"} |= "STATE_CHANGED"

# All interface errors across fabric
{job="syslog"} |= "ERROR" and facility="interfaces"

# Temperature warnings and above
{job="syslog"} and severity >= "4" and facility="daemon"

# MAC flapping events (exclude known dynamic)
{job="syslog", facility="routing-daemon"} |= "MAC" and |!= "permanent"

# EVPN route withdrawals
{job="syslog", facility="bgp"} |= "EVPN" and |= "withdraw"
```

---

## 8. Automated Remediation (Event-Driven Automation)

### 8.1 Juniper Paragon Automation Framework

Juniper Paragon enables intent-based automation using the Event Management System (EMS).

### 8.2 Automated Remediation Playbooks

#### 8.2.1 Interface Error Recovery

**Trigger**: ifInErrors > 1000 in 5 minutes

**Playbook Steps**:
1. Log alert to ticketing system
2. Clear interface counters (soft reset)
3. Wait 5 minutes, re-check error rate
4. If still high, escalate to on-call and generate RMA ticket
5. Notify operations to schedule optic module replacement

```yaml
name: "interface-error-recovery"
trigger:
  type: "snmp_threshold"
  oid: "1.3.6.1.2.1.2.2.1.20"
  threshold: 1000
  duration: 300
actions:
  - type: "syslog"
    message: "High error rate detected on {interface}"
  - type: "clear_counters"
    device: "{device_ip}"
    interface: "{interface}"
  - type: "wait"
    duration: 300
  - type: "check_metric"
    oid: "1.3.6.1.2.1.2.2.1.20"
    comparison: ">"
    value: 500
    then: "escalate"
    else: "close"
```

#### 8.2.2 BGP Neighbor Flapping Recovery

**Trigger**: BGP neighbor state changes >5 times in 10 minutes

**Playbook Steps**:
1. Identify flapping neighbor and device
2. Save pre-failure configuration snapshot
3. Isolate peer by disabling BGP session
4. Check peer device reachability (ping)
5. If reachable, soft reset BGP session
6. Monitor convergence time
7. If convergence exceeds SLA, alert on-call

```yaml
name: "bgp-flapping-recovery"
trigger:
  type: "bgp_flap_detection"
  flap_count: 5
  time_window: 600
actions:
  - type: "snapshot"
    device: "{device_ip}"
    config: true
  - type: "bgp_disable"
    device: "{device_ip}"
    neighbor: "{neighbor_ip}"
    hold_time: 60
  - type: "ping"
    target: "{neighbor_ip}"
    threshold: 3
    then: "soft_reset"
    else: "escalate"
  - type: "bgp_soft_reset"
    device: "{device_ip}"
    neighbor: "{neighbor_ip}"
  - type: "monitor"
    metric: "bgp_convergence_time"
    target: "{sla_target}"
```

#### 8.2.3 Automatic EVPN MAC Flapping Quarantine

**Trigger**: MAC address moves >10 times in 60 seconds

**Playbook Steps**:
1. Identify MAC and interfaces
2. Disable port on first interface
3. Log event for forensic analysis
4. Alert network operations
5. After 30 minutes, enable port (if manual override not set)

```yaml
name: "evpn-mac-flap-quarantine"
trigger:
  type: "mac_flap_detection"
  flap_count: 10
  time_window: 60
actions:
  - type: "syslog"
    severity: "warning"
    message: "MAC {mac} flapping: {move_count} moves in {time_window}s"
  - type: "interface_disable"
    device: "{device_ip}"
    interface: "{first_interface}"
    reason: "MAC flapping quarantine"
  - type: "ticket_create"
    summary: "MAC {mac} quarantined due to flapping"
    priority: "high"
  - type: "wait"
    duration: 1800
  - type: "interface_enable"
    device: "{device_ip}"
    interface: "{first_interface}"
    condition: "manual_override_not_set"
```

#### 8.2.4 Spine Failover Orchestration

**Trigger**: Spine device down (all management interfaces unreachable for 30 seconds)

**Playbook Steps**:
1. Verify spine is truly down (ICMP + SSH probe)
2. Alert on-call immediately with severity CRITICAL
3. Trigger automatic graceful shutdown of BGP on affected leaves
4. Re-converge ECMP paths through remaining spines
5. Monitor convergence and error rates
6. Log all affected tenants/VNFs
7. Open critical ticket with RCA

```yaml
name: "spine-failover-orchestration"
trigger:
  type: "device_unreachable"
  device_role: "spine"
  probe_count: 3
  probe_interval: 10
actions:
  - type: "alert_pagerduty"
    severity: "critical"
    message: "Spine {device_name} ({device_ip}) is offline"
  - type: "verify_device_down"
    device: "{device_ip}"
    methods: ["icmp", "ssh", "snmp"]
    threshold: 3
  - type: "parallel"
    actions:
      - type: "bgp_graceful_shutdown"
        device: "all_leaves"
        address_family: ["ipv4-unicast", "evpn"]
      - type: "monitor_convergence"
        metric: "bgp_convergence_time"
        target: "2000"  # 2 seconds
  - type: "ticket_create"
    severity: "critical"
    summary: "Spine {device_name} offline"
    description: "Affected tenants: {affected_tenants}"
```

### 8.3 Metrics for Automation Health

| Automation Event | Success Rate Target | Alert Threshold |
|-----------------|---------------------|-----------------|
| Interface counter clear recovery | >95% | <90% |
| BGP soft reset convergence | >98% in <30s | >45s |
| MAC flap quarantine effectiveness | >99% | <95% |
| Spine failover convergence | >99% in <2s | >3s |
| Automatic ticket creation | 100% | <95% |

---

## 9. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
- Deploy Prometheus, Telegraf, Grafana stack
- Configure SNMP v3 on all devices
- Deploy SNMP exporter and scrape configs
- Create basic fabric overview dashboard
- Establish centralized syslog aggregation

### Phase 2: Streaming Telemetry (Weeks 3-4)
- Configure JTI on spine devices
- Deploy gNMI collectors
- Add streaming telemetry targets to Telegraf
- Create real-time interface counters dashboard
- Validate data quality and latency

### Phase 3: Advanced Observability (Weeks 5-6)
- Deploy Loki for log aggregation
- Configure advanced alert rules
- Integrate with PagerDuty/Slack
- Create BGP/EVPN dashboards
- Setup event correlation logic

### Phase 4: Automation and Optimization (Weeks 7-8)
- Implement automated remediation playbooks
- Deploy Juniper Paragon Event Management
- Create capacity planning dashboard
- Optimize retention policies
- Document runbooks

---

## 10. Troubleshooting Guide

### Issue: Missing SNMP Data

**Symptoms**: Gaps in metric graphs, missing devices

**Diagnosis**:
```bash
# Test SNMP connectivity from collector
snmpwalk -v3 -u monitoring -l authPriv -a MD5 -A <auth_pass> -x AES -X <priv_pass> 10.255.0.1 1.3.6.1.2.1.1.1.0

# Check Prometheus scrape logs
curl -s http://prometheus:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="snmp")'
```

**Resolution**:
- Verify SNMPv3 credentials on device
- Check firewall rules (UDP 161)
- Validate SNMP v3 parameters match between device and exporter
- Increase exporter timeout if network latency is high

### Issue: BGP Routes Not Converging

**Symptoms**: BGP neighbors established but routes not received

**Diagnosis**:
```bash
# Check BGP policy on spine
show route receiving-protocol bgp 10.1.0.1

# Verify EVPN is enabled
show protocols bgp group all family evpn

# Check for route target filtering
show route summary
```

**Resolution**:
- Verify import/export policies on both devices
- Check route targets match (for EVPN)
- Validate address family negotiation
- Check for route filters blocking traffic

### Issue: High CPU on Leaf

**Symptoms**: CPU >80%, slow response, high memory usage

**Diagnosis**:
```bash
# Check top processes
request shell
ps aux | head -20

# Check BGP route count
show route summary family inet.0

# Check EVPN MAC count
show route count family evpn
```

**Resolution**:
- Reduce EVPN MAC count by checking for MAC loops
- Implement route filtering to reduce route count
- Upgrade to higher-capacity platform if growth is legitimate
- Check for runaway processes (restart if needed)

---

## 11. Reference Documentation

- **Juniper MIB Reference**: https://www.juniper.net/documentation/
- **OpenConfig Models**: https://github.com/openconfig/public
- **Prometheus Documentation**: https://prometheus.io/docs/
- **Grafana Dashboard Development**: https://grafana.com/docs/grafana/latest/dashboards/
- **Telegraf Input Plugins**: https://github.com/influxdata/telegraf/tree/master/plugins/inputs

---

## Document Control

- **Version**: 1.0
- **Last Updated**: 2026-03-25
- **Author**: Network Engineering Team
- **Status**: Production Ready
