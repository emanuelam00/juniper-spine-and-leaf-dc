# Juniper Spine-Leaf Datacenter Security Hardening Guide

**Document Version:** 2.0
**Last Updated:** 2026-03-25
**Topology:** 4x QFX5220 Spines (ASN 65000) + 60x QFX5120 Leaves (ASN 65001-65060)
**Overlay:** EVPN-VXLAN | **Underlay:** eBGP | **Security Firewalls:** 2x FortiGate (Active-Active)

---

## 1. Security Design Principles

### 1.1 Defense in Depth

The fabric security architecture follows a multi-layered defense strategy:

- **Management Plane:** Authenticated, encrypted access only (SSH v2, NETCONF, RADIUS/TACACS+)
- **Control Plane:** CoPP with strict rate-limiting, protocol-specific filtering, DDoS protection
- **Data Plane:** Storm control, MAC limiting, DHCP snooping, DAI, IP source guard
- **Routing Security:** BGP MD5, prefix filtering, TTL security (GTSM), RPKI validation
- **Overlay Security:** VXLAN micro-segmentation, VRF-based tenant isolation, EVPN route filtering

### 1.2 Least Privilege Access

- All user accounts assigned minimal required permissions
- Role-based access control (RBAC) using class-based authentication
- Service accounts provisioned only with necessary routing protocol permissions
- No shared credentials; individual accountability enforced
- Console access restricted to labeled physical ports in secure facilities

### 1.3 Zero Trust within DC Fabric

Assumptions:
- Every port, peer, and packet is verified
- BGP MD5 authentication mandatory on all sessions
- Control plane traffic explicitly allowed only from known sources
- Ingress filtering on all external connections
- Dynamic policy enforcement based on identity and state

---

## 2. Management Plane Security

### 2.1 SSH Configuration

SSH v2 is the sole remote access protocol. Telnet and HTTP/HTTPS management must be disabled.

**Configuration:**

```junos
system {
    host-name spine-1;
    services {
        ssh {
            protocol-version v2;
            root-login deny;
            connection-limit 5;
            rate-limit 10;
        }
        telnet {
            disable;
        }
        http {
            disable;
        }
        https {
            disable;
        }
        netconf {
            ssh {
                port 830;
            }
        }
    }
}
```

**Rationale:**
- SSH v2 provides strong encryption and authentication mechanisms
- Telnet transmits credentials in plaintext; HTTP lacks encryption
- NETCONF over SSH (port 830) enables secure configuration management
- Rate-limiting prevents brute-force attacks
- Connection limits prevent resource exhaustion

### 2.2 Strong Password Policies

```junos
system {
    password {
        minimum-length 20;
        format encrypted;
        change-interval 90;
    }
    root-authentication {
        encrypted-password "$6$somehash...";
    }
    login {
        class admin {
            idle-timeout 15;
            login-attempts 3;
            allow-commands "^show ";
            deny-commands "^request system";
        }
        class operator {
            idle-timeout 30;
            login-attempts 5;
            allow-commands "^(show|monitor) ";
            deny-commands "^(request|configure|edit)";
        }
    }
}
```

**Requirements:**
- Minimum 20 characters combining uppercase, lowercase, digits, special characters
- Password change every 90 days
- Failed login attempt lockout after 3 attempts for 15 minutes
- Idle timeout of 15 minutes for admin, 30 minutes for operator
- Encrypted password storage using SHA-512 hashing

### 2.3 RADIUS/TACACS+ Integration

```junos
system {
    radius-server {
        192.168.100.10 {
            secret "$9$radiuskey12345...";
            timeout 5;
            retry 2;
            port 1812;
        }
        192.168.100.11 {
            secret "$9$radiuskey67890...";
            timeout 5;
            retry 2;
            port 1812;
        }
    }
    tacplus-server {
        192.168.100.20 {
            secret "$9$tackey12345...";
            timeout 5;
            retry 2;
            port 49;
        }
        192.168.100.21 {
            secret "$9$tackey67890...";
            timeout 5;
            retry 2;
            port 49;
        }
    }
    authentication-order [ radius tacplus ];
    accounting {
        events [ login change-log ];
        destination {
            radius {
                server 192.168.100.10;
            }
            syslog;
        }
    }
}
```

**Configuration Notes:**
- Dual RADIUS and TACACS+ servers for redundancy
- Secrets encrypted using JunOS encryption algorithm
- 5-second timeout, 2 retries for fault tolerance
- Fallback to local authentication if all remote servers fail
- All authentication events logged to syslog and remote servers

### 2.4 Session Management

```junos
system {
    login {
        idle-timeout 15;
        retry-options {
            tries-before-disconnect 3;
            backoff-interval 1;
            backoff-threshold 2;
        }
    }
}
```

### 2.5 Login Banner (Legal Warning)

```junos
system {
    login {
        announcement "\n========================================\nAUTHORIZED ACCESS ONLY\nThis system is for authorized use only.\nUnauthorized access is prohibited and will\nbe prosecuted to the fullest extent of law.\nAll activities are monitored and logged.\n========================================\n";
    }
}
```

### 2.6 Configuration Change Audit Logging

```junos
system {
    syslog {
        host 192.168.100.50 {
            any notice;
            interactive-commands info;
            change-log info;
        }
        file messages {
            any notice;
            interactive-commands info;
            change-log info;
            archive size 100m files 10;
        }
    }
}
```

**Audit Requirements:**
- All configuration changes logged with timestamp, username, change content
- Logs forwarded to centralized syslog server (192.168.100.50)
- Local archive: 100 MB files, 10 file rotation
- Retention: 90 days minimum

### 2.7 SNMPv3 Only (Disable v1/v2c)

```junos
snmp {
    disable;
}
snmp3 {
    usm {
        local-engine {
            user monitoring {
                authentication-type sha;
                authentication-password "$9$snmpkey1234...";
                privacy-type aes-128;
                privacy-password "$9$snmpprivacy5678...";
            }
            user admin {
                authentication-type sha;
                authentication-password "$9$snmpadmin1234...";
                privacy-type aes-128;
                privacy-password "$9$snmpadmin5678...";
            }
        }
    }
    access {
        group monitoring {
            security-model usm;
            security-level authentication;
            prefix all;
        }
        group admin {
            security-model usm;
            security-level privacy;
            prefix all;
        }
    }
    trap {
        group monitoring {
            version v3;
            targets [ 192.168.100.60 192.168.100.61 ];
        }
    }
}
```

**SNMPv3 Benefits:**
- Authentication and encryption of all SNMP packets
- Individual user credentials with auth/privacy separation
- Disabled legacy SNMPv1/v2c (cleartext credentials)
- Read-only community strings not supported

### 2.8 Certificate-Based SSH Authentication

```junos
system {
    services {
        ssh {
            key-type dsa;
            key-type ecdsa;
            key-type rsa;
        }
    }
}
security {
    ssh-known-hosts {
        192.168.1.1 {
            key-type dsa;
            key-value "AAAAB3NzaC1kc3...";
        }
        192.168.1.2 {
            key-type ecdsa;
            key-value "AAAAE2VjZHNhLXNoYTItbmlz...";
        }
    }
}
```

---

## 3. Control Plane Protection (CoPP)

Control Plane Policing (CoPP) protects the routing engine from DDoS attacks targeting BGP, BFD, SSH, SNMP, and other critical services.

### 3.1 CoPP Architecture

- **Policers:** Rate-limit packets per protocol class
- **Firewall Filters:** Applied to loopback (lo0) interface
- **Classifiers:** Identify traffic by protocol, source, destination
- **Action:** Accept, discard, or rate-limit based on policy

### 3.2 Complete CoPP Firewall Filter for Spine

```junos
firewall {
    policer bgp-peer-limit {
        if-exceeding {
            bandwidth-limit 50m;
            burst-size-limit 5m;
        }
        then discard;
    }
    policer bfd-limit {
        if-exceeding {
            bandwidth-limit 10m;
            burst-size-limit 1m;
        }
        then discard;
    }
    policer ssh-limit {
        if-exceeding {
            bandwidth-limit 1m;
            burst-size-limit 100k;
        }
        then discard;
    }
    policer snmp-limit {
        if-exceeding {
            bandwidth-limit 5m;
            burst-size-limit 500k;
        }
        then discard;
    }
    policer ntp-limit {
        if-exceeding {
            bandwidth-limit 2m;
            burst-size-limit 200k;
        }
        then discard;
    }
    policer icmp-limit {
        if-exceeding {
            bandwidth-limit 10m;
            burst-size-limit 1m;
        }
        then discard;
    }
    policer netconf-limit {
        if-exceeding {
            bandwidth-limit 5m;
            burst-size-limit 500k;
        }
        then discard;
    }
    policer dhcp-limit {
        if-exceeding {
            bandwidth-limit 1m;
            burst-size-limit 100k;
        }
        then discard;
    }
    filter copp-filter-lo0 {
        term permit-bgp-v4 {
            from {
                destination-address {
                    10.0.0.0/24;
                }
                protocol tcp;
                destination-port 179;
            }
            then {
                policer bgp-peer-limit;
                accept;
            }
        }
        term permit-bgp-v6 {
            from {
                destination-address {
                    2001:db8::/32;
                }
                protocol tcp;
                destination-port 179;
            }
            then {
                policer bgp-peer-limit;
                accept;
            }
        }
        term permit-bfd-v4 {
            from {
                destination-address {
                    10.0.0.0/24;
                }
                protocol udp;
                destination-port 3784;
            }
            then {
                policer bfd-limit;
                accept;
            }
        }
        term permit-bfd-v6 {
            from {
                destination-address {
                    2001:db8::/32;
                }
                protocol udp;
                destination-port 3784;
            }
            then {
                policer bfd-limit;
                accept;
            }
        }
        term permit-ssh-v4 {
            from {
                destination-address {
                    192.168.100.0/24;
                }
                protocol tcp;
                destination-port 22;
            }
            then {
                policer ssh-limit;
                accept;
            }
        }
        term permit-ssh-v6 {
            from {
                destination-address {
                    2001:db8:100::/48;
                }
                protocol tcp;
                destination-port 22;
            }
            then {
                policer ssh-limit;
                accept;
            }
        }
        term permit-netconf-v4 {
            from {
                destination-address {
                    192.168.100.0/24;
                }
                protocol tcp;
                destination-port 830;
            }
            then {
                policer netconf-limit;
                accept;
            }
        }
        term permit-snmp-v4 {
            from {
                destination-address {
                    192.168.100.0/24;
                }
                protocol udp;
                destination-port 161;
            }
            then {
                policer snmp-limit;
                accept;
            }
        }
        term permit-snmp-trap-v4 {
            from {
                protocol udp;
                destination-port 162;
            }
            then {
                policer snmp-limit;
                accept;
            }
        }
        term permit-ntp-v4 {
            from {
                protocol udp;
                destination-port 123;
            }
            then {
                policer ntp-limit;
                accept;
            }
        }
        term permit-icmp-v4 {
            from {
                protocol icmp;
            }
            then {
                policer icmp-limit;
                accept;
            }
        }
        term permit-icmp-v6 {
            from {
                protocol icmpv6;
            }
            then {
                policer icmp-limit;
                accept;
            }
        }
        term permit-dhcp-relay {
            from {
                protocol udp;
                source-port 68;
                destination-port 67;
            }
            then {
                policer dhcp-limit;
                accept;
            }
        }
        term deny-all {
            then discard;
        }
    }
}
interfaces {
    lo0 {
        unit 0 {
            family inet {
                filter {
                    input copp-filter-lo0;
                }
                address 10.0.1.1/32;
            }
            family inet6 {
                filter {
                    input copp-filter-lo0;
                }
                address 2001:db8::1/128;
            }
        }
    }
}
```

**Policer Details:**
- **BGP:** 50 Mbps (handles 200+ simultaneous BGP sessions from leaves)
- **BFD:** 10 Mbps (subsecond failure detection)
- **SSH:** 1 Mbps (interactive management, prevents brute force)
- **SNMP:** 5 Mbps (polling from monitoring systems)
- **NTP:** 2 Mbps (time synchronization)
- **ICMP:** 10 Mbps (traceroute, ping diagnostics)
- **NETCONF:** 5 Mbps (XML-RPC configuration management)
- **DHCP Relay:** 1 Mbps (DHCP request flood protection)

### 3.3 Complete CoPP Filter for Leaf

```junos
firewall {
    policer bgp-peer-limit {
        if-exceeding {
            bandwidth-limit 25m;
            burst-size-limit 2.5m;
        }
        then discard;
    }
    policer bfd-limit {
        if-exceeding {
            bandwidth-limit 5m;
            burst-size-limit 500k;
        }
        then discard;
    }
    policer ssh-limit {
        if-exceeding {
            bandwidth-limit 1m;
            burst-size-limit 100k;
        }
        then discard;
    }
    policer snmp-limit {
        if-exceeding {
            bandwidth-limit 2m;
            burst-size-limit 200k;
        }
        then discard;
    }
    policer ntp-limit {
        if-exceeding {
            bandwidth-limit 1m;
            burst-size-limit 100k;
        }
        then discard;
    }
    policer icmp-limit {
        if-exceeding {
            bandwidth-limit 5m;
            burst-size-limit 500k;
        }
        then discard;
    }
    policer netconf-limit {
        if-exceeding {
            bandwidth-limit 2m;
            burst-size-limit 200k;
        }
        then discard;
    }
    policer dhcp-snooping-limit {
        if-exceeding {
            bandwidth-limit 2m;
            burst-size-limit 200k;
        }
        then discard;
    }
    filter copp-filter-lo0 {
        term permit-bgp-from-spines {
            from {
                source-address {
                    10.0.0.0/24;
                }
                protocol tcp;
                destination-port 179;
            }
            then {
                policer bgp-peer-limit;
                accept;
            }
        }
        term permit-bgp-from-leaves {
            from {
                source-address {
                    10.0.1.0/24;
                }
                protocol tcp;
                destination-port 179;
            }
            then {
                policer bgp-peer-limit;
                accept;
            }
        }
        term permit-bfd {
            from {
                protocol udp;
                destination-port 3784;
            }
            then {
                policer bfd-limit;
                accept;
            }
        }
        term permit-ssh {
            from {
                source-address {
                    192.168.100.0/24;
                }
                protocol tcp;
                destination-port 22;
            }
            then {
                policer ssh-limit;
                accept;
            }
        }
        term permit-netconf {
            from {
                source-address {
                    192.168.100.0/24;
                }
                protocol tcp;
                destination-port 830;
            }
            then {
                policer netconf-limit;
                accept;
            }
        }
        term permit-snmp {
            from {
                source-address {
                    192.168.100.0/24;
                }
                protocol udp;
                destination-port 161;
            }
            then {
                policer snmp-limit;
                accept;
            }
        }
        term permit-ntp {
            from {
                protocol udp;
                destination-port 123;
            }
            then {
                policer ntp-limit;
                accept;
            }
        }
        term permit-icmp {
            from {
                protocol icmp;
            }
            then {
                policer icmp-limit;
                accept;
            }
        }
        term permit-icmpv6 {
            from {
                protocol icmpv6;
            }
            then {
                policer icmp-limit;
                accept;
            }
        }
        term permit-dhcp-relay {
            from {
                protocol udp;
                source-port 68;
                destination-port 67;
            }
            then {
                policer dhcp-snooping-limit;
                accept;
            }
        }
        term deny-all {
            then discard;
        }
    }
}
interfaces {
    lo0 {
        unit 0 {
            family inet {
                filter {
                    input copp-filter-lo0;
                }
                address 10.0.2.1/32;
            }
        }
    }
}
```

### 3.4 DDoS Protection Profiles

```junos
security {
    ddos-protection {
        global {
            protocol-level tcp {
                connection-rate-limit 10000;
                timeout 60;
            }
            protocol-level udp {
                flow-rate-limit 50000;
                timeout 30;
            }
        }
        policy ddos-bgp {
            rule protect-bgp {
                match {
                    destination-port 179;
                    protocol tcp;
                }
                then {
                    action drop;
                    notification alert;
                    log;
                }
            }
        }
    }
}
```

---

## 4. Data Plane Security

### 4.1 Storm Control on Server-Facing Ports

```junos
interfaces {
    et-0/0/0 {
        description "Server Port 1";
        mtu 1514;
        unit 0 {
            family ethernet-switching {
                storm-control {
                    broadcast-limit 1;
                    multicast-limit 1;
                    unknown-unicast-limit 1;
                }
            }
        }
    }
}
```

**Storm Control Thresholds:**
- **Broadcast:** 1% of port bandwidth (prevents broadcast storms)
- **Multicast:** 1% of port bandwidth (limits multicast flooding)
- **Unknown Unicast:** 1% of port bandwidth (protects against MAC table overflow attacks)

### 4.2 MAC Address Limiting

```junos
interfaces {
    et-0/0/0 {
        unit 0 {
            family ethernet-switching {
                mac-limit {
                    maximum 10;
                    action shutdown;
                    notification alert;
                }
            }
        }
    }
}
```

**Configuration:**
- Max 10 MAC addresses per server port (prevents rogue device injection)
- Action: Disable port on violation
- Notification: Alert to syslog

### 4.3 DHCP Snooping

```junos
vlans {
    default {
        vlan-id 1;
        l3-interface vlan.1;
        dhcp-snooping {
            enabled;
            trusted-interface [ et-0/0/48 et-0/0/49 ];
        }
    }
}
interfaces {
    et-0/0/0 {
        unit 0 {
            family ethernet-switching {
                vlan members default;
            }
        }
    }
    et-0/0/48 {
        description "Uplink to Spine";
        unit 0 {
            family ethernet-switching {
                vlan members default;
            }
        }
    }
}
```

**DHCP Snooping Protection:**
- Trusted uplinks only (spines): Accept all DHCP packets
- Untrusted server ports: Only accept DHCP responses (not requests)
- Prevents rogue DHCP servers on server ports

### 4.4 Dynamic ARP Inspection (DAI)

```junos
security {
    dynamic-arp-inspection {
        enabled;
        ip-table vlan.1 {
            arp-request validate source-mac destination-mac;
            arp-response validate source-mac destination-mac;
            trusted-vlans [ default ];
        }
    }
}
interfaces {
    et-0/0/48 {
        unit 0 {
            family ethernet-switching {
                vlan members default;
                arp-inspection trusted;
            }
        }
    }
}
```

**DAI Validation:**
- Source MAC must match sender's MAC in Ethernet frame
- Destination MAC must match target's MAC in ARP packet
- Prevents ARP spoofing attacks (MITM, gratuitous ARP)

### 4.5 IP Source Guard

```junos
security {
    ip-source-guard {
        enabled;
        static-bindings [ 10.1.1.1/32 ];
    }
}
interfaces {
    et-0/0/0 {
        unit 0 {
            family ethernet-switching {
                vlan members default;
                ip-source-guard {
                    trusted;
                }
            }
        }
    }
}
```

**IP Source Guard:**
- Permits only packets with matching IP/MAC binding from DHCP snooping database
- Prevents IP spoofing on server ports
- Static bindings for non-DHCP devices

### 4.6 Complete Port Security Configuration for Leaf Server Ports

```junos
interfaces {
    et-0/0/0 {
        description "Server Port 1 - Host A";
        mtu 1514;
        unit 0 {
            family ethernet-switching {
                vlan members server-vlan;
                port-security {
                    enabled;
                    maximum-mac-count 10;
                    mac-move-limit 5;
                    violation-action shutdown;
                    notification alert;
                }
                storm-control {
                    broadcast-limit 1;
                    multicast-limit 1;
                    unknown-unicast-limit 1;
                }
            }
        }
    }
    et-0/0/1 {
        description "Server Port 2 - Host B";
        mtu 1514;
        unit 0 {
            family ethernet-switching {
                vlan members server-vlan;
                port-security {
                    enabled;
                    maximum-mac-count 10;
                    mac-move-limit 5;
                    violation-action shutdown;
                    notification alert;
                }
                storm-control {
                    broadcast-limit 1;
                    multicast-limit 1;
                    unknown-unicast-limit 1;
                }
            }
        }
    }
}
vlans {
    server-vlan {
        vlan-id 100;
        l3-interface vlan.100;
        dhcp-snooping {
            enabled;
            trusted-interface [ et-0/0/48 et-0/0/49 ];
        }
    }
}
security {
    dynamic-arp-inspection {
        enabled;
        ip-table vlan.100 {
            arp-request validate source-mac destination-mac;
            arp-response validate source-mac destination-mac;
        }
    }
    ip-source-guard {
        enabled;
        interface et-0/0/0 { trusted; }
        interface et-0/0/48 { trusted; }
        interface et-0/0/49 { trusted; }
    }
}
```

---

## 5. Routing Security

### 5.1 BGP MD5 Authentication

All BGP sessions must use MD5 authentication. Configuration for spine-leaf eBGP:

```junos
protocols {
    bgp {
        log-updown;
        graceful-restart {
            restart-time 120;
        }
        group leaves-v4 {
            type external;
            multihop;
            hold-time 9;
            keepalive-time 3;
            authentication-key "$9$bgpkey123456789...";
            authentication-algorithm md5;
            neighbor 10.0.2.1 {
                description "Leaf-1";
                peer-as 65001;
            }
            neighbor 10.0.2.2 {
                description "Leaf-2";
                peer-as 65002;
            }
        }
        group leaves-v6 {
            type external;
            multihop;
            hold-time 9;
            keepalive-time 3;
            authentication-key "$9$bgpkey987654321...";
            authentication-algorithm md5;
            neighbor 2001:db8:2::1 {
                description "Leaf-1-v6";
                peer-as 65001;
            }
            neighbor 2001:db8:2::2 {
                description "Leaf-2-v6";
                peer-as 65002;
            }
        }
    }
}
```

**Authentication Details:**
- Unique MD5 keys per BGP group (not shared across devices)
- Keys encrypted at rest using JunOS encryption
- Keys rotated every 180 days
- Prevents unauthorized BGP session hijacking

### 5.2 BGP Prefix Filtering and Max-Prefix Limits

```junos
policy-statement leaf-import-policy {
    term reject-bogon-prefixes {
        from {
            route-filter 0.0.0.0/0 through 8.255.255.255 reject;
            route-filter 224.0.0.0/4 reject;
            route-filter 240.0.0.0/4 reject;
            route-filter 255.255.255.255/32 reject;
        }
    }
    term accept-only-leaf-prefixes {
        from {
            route-filter 10.0.0.0/8 upto /24 accept;
            route-filter 2001:db8::/32 upto /48 accept;
        }
        then accept;
    }
    term reject-all {
        then reject;
    }
}
protocols {
    bgp {
        group leaves-v4 {
            type external;
            import leaf-import-policy;
            neighbor 10.0.2.1 {
                description "Leaf-1";
                peer-as 65001;
            }
        }
    }
}
```

### 5.3 BGP Max-Prefix Configuration

```junos
protocols {
    bgp {
        group leaves-v4 {
            type external;
            neighbor 10.0.2.1 {
                description "Leaf-1";
                peer-as 65001;
                family inet {
                    unicast {
                        prefix-limit {
                            maximum 1000;
                            teardown 95;
                            idle-timeout forever;
                        }
                    }
                }
            }
        }
        group leaves-v6 {
            type external;
            neighbor 2001:db8:2::1 {
                description "Leaf-1-v6";
                peer-as 65001;
                family inet6 {
                    unicast {
                        prefix-limit {
                            maximum 500;
                            teardown 95;
                            idle-timeout forever;
                        }
                    }
                }
            }
        }
    }
}
```

**Prefix Limits:**
- Leaf IPv4: Max 1000 prefixes (includes loopback, VXLAN endpoints, route aggregates)
- Leaf IPv6: Max 500 prefixes
- Teardown: Automatically reset session at 95% threshold
- Idle timeout: Permanent teardown (requires manual intervention to restore)

### 5.4 BGP TTL Security (GTSM)

```junos
protocols {
    bgp {
        group leaves-v4 {
            type external;
            ttl-security {
                enable;
                max-ttl 255;
            }
            neighbor 10.0.2.1 {
                description "Leaf-1";
                peer-as 65001;
            }
        }
    }
}
```

**GTSM Protection:**
- Ensures BGP packets originate from directly connected peers (prevents spoofing from non-adjacent networks)
- TTL must equal 255 for eBGP multihop sessions
- Prevents BGP hijacking from external networks

### 5.5 EVPN Route-Target Filtering

```junos
routing-instances {
    evpn-instance {
        instance-type evpn;
        route-targets {
            import target:65000:1;
            export target:65000:1;
        }
        protocols {
            bgp {
                group evpn-peers {
                    type internal;
                    local-address 10.0.0.1;
                    peer-as 65000;
                    family evpn {
                        signaling {
                            route-target {
                                filter-policy {
                                    import "accept-evpn-targets";
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
policy-statement accept-evpn-targets {
    term accept-rt-targets {
        from {
            target [ "target:65000:1" "target:65000:2" "target:65000:3" ];
        }
        then accept;
    }
    term reject-all {
        then reject;
    }
}
```

---

## 6. VXLAN Security

### 6.1 VXLAN-Aware Firewall Considerations

The active-active FortiGate pair (north of spines) requires:

- **VXLAN Decapsulation Awareness:** Inspect inner Layer 2/3 headers after VXLAN decap
- **VNI-to-Tenant Mapping:** Enforce traffic isolation between VXLAN segments
- **UDP Port 4789 Filtering:** Allow only spine-to-leaf VXLAN tunnels
- **VXLAN Header Validation:** Drop malformed VXLAN packets

**Example FortiGate Configuration (pseudocode):**

```
config firewall address
    edit "spine-subnet"
        set subnet 10.0.0.0 255.255.255.0
    next
    edit "leaf-subnet"
        set subnet 10.0.1.0 255.255.0.0
    next
end

config firewall service custom
    edit "vxlan-service"
        set protocol udp
        set udp-portrange 4789
    next
end

config firewall policy
    edit 1
        set name "allow-vxlan-fabric"
        set srcintf "port1"
        set dstintf "port2"
        set srcaddr "spine-subnet"
        set dstaddr "leaf-subnet"
        set service "vxlan-service"
        set action accept
        set inspection-mode proxy
        set utm-status enable
        set logtraffic all
    next
end
```

### 6.2 Micro-Segmentation with Security Groups

Implement security groups at the hypervisor or ToR layer:

```junos
firewall {
    filter egress-security-group-filter {
        term allow-web-tier {
            from {
                source-prefix-list web-tier;
                destination-port 80;
                destination-port 443;
            }
            then accept;
        }
        term allow-db-tier {
            from {
                source-prefix-list app-tier;
                destination-port 3306;
                destination-port 5432;
            }
            then accept;
        }
        term allow-intra-tier {
            from {
                source-prefix-list web-tier;
                destination-prefix-list web-tier;
            }
            then accept;
        }
        term deny-all {
            then discard;
        }
    }
}
```

### 6.3 East-West Traffic Filtering Policies

```junos
policy-statement vxlan-east-west {
    term allow-same-vrf {
        from {
            family evpn;
            route-target [ "target:65000:1" ];
        }
        then accept;
    }
    term allow-inter-vrf-firewall {
        from {
            family evpn;
            next-hop [ 10.0.0.1 10.0.0.2 10.0.0.3 10.0.0.4 ];
        }
        then accept;
    }
    term deny-cross-tenant {
        then reject;
    }
}
```

### 6.4 VRF-Based Tenant Isolation

```junos
routing-instances {
    tenant-1 {
        instance-type vrf;
        vrf-target target:65000:100;
        routing-options {
            static {
                route 0.0.0.0/0 next-table inet.0;
            }
        }
        interfaces {
            vlan.100;
            irb.100;
        }
    }
    tenant-2 {
        instance-type vrf;
        vrf-target target:65000:200;
        vrf-target import target:65000:100 reject;
        routing-options {
            static {
                route 0.0.0.0/0 next-table inet.0;
            }
        }
        interfaces {
            vlan.200;
            irb.200;
        }
    }
}
```

**Isolation Mechanism:**
- Each tenant assigned unique VRF and route target
- Import policies prevent cross-tenant route leakage
- Tenant-1 cannot reach Tenant-2 without firewall mediation

### 6.5 MAC/IP Binding in EVPN

```junos
protocols {
    evpn {
        mac-ip-table {
            learn-from-arp enable;
            learn-from-nd enable;
            duplicate-detection {
                detection-threshold 3;
                time-window 60;
                action log-only;
            }
        }
    }
}
```

**MAC/IP Security:**
- Learn IP-MAC bindings from ARP/ND
- Detect duplicate MAC or IP addresses
- Log suspicious activity for analysis

---

## 7. Physical Security

### 7.1 Console Port Security

```junos
system {
    services {
        console {
            disable-authentication false;
            login-banner "CONSOLE ACCESS RESTRICTED";
            inactivity-timeout 5;
        }
    }
    root-authentication {
        encrypted-password "$6$consolepwd...";
    }
}
interfaces {
    console {
        unit 0 {
            family inet {
                address 127.0.0.1/8;
            }
        }
    }
}
```

**Configuration:**
- Console authentication enabled (not disabled)
- Inactivity timeout: 5 minutes
- Console physically labeled and access restricted
- Console logs forwarded to secure syslog server

### 7.2 USB Port Disable

```junos
system {
    usb-ports {
        disable;
    }
}
```

**Rationale:** Prevents USB-based attack vectors (firmware injection, malware loading).

### 7.3 Secure Boot Verification

```junos
system {
    secure-boot {
        enable;
    }
}
```

**Secure Boot:**
- Verify firmware signatures on boot
- Prevent unauthorized OS modifications
- Check that bootloader and kernel are signed

---

## 8. Compliance and Auditing

### 8.1 Configuration Compliance Checking

```junos
system {
    configuration-database {
        backup 192.168.100.50:/backups/daily;
        retention-time 90d;
        change-history retain 500;
    }
}
```

### 8.2 Change Management Procedures

**Required Steps for Any Configuration Change:**

1. **Planning:** Document change, risk assessment, rollback plan
2. **Approval:** Change advisory board (CAB) review
3. **Testing:** Validate in staging environment (minimum 24-hour window)
4. **Implementation:** During maintenance window, with change window (2-hour window)
5. **Validation:** Verify all systems operational, run compliance checks
6. **Documentation:** Update change log, audit trail, runbooks
7. **Review:** Post-change review meeting

**Change Window Restrictions:**
- Production changes prohibited: Friday 16:00 - Monday 06:00
- Maintenance window: Tuesday 22:00 - Wednesday 04:00 (UTC)
- Emergency changes only via incident commander authorization

### 8.3 Security Audit Checklist (80+ Items)

| Item | Category | Status | Notes |
|------|----------|--------|-------|
| SSH v2 enabled | Management | ✓ | Telnet disabled |
| Password min 20 chars | Management | ✓ | Change every 90 days |
| RADIUS/TACACS+ configured | Management | ✓ | Dual servers, fallback local |
| SNMPv3 only | Management | ✓ | SNMPv1/v2c disabled |
| CoPP on all routers | Control Plane | ✓ | All protocols rate-limited |
| BGP MD5 authentication | Routing | ✓ | Unique keys per peer group |
| BGP max-prefix limits | Routing | ✓ | Spine: 1000, Leaf: 500 |
| BGP GTSM enabled | Routing | ✓ | TTL=255 validation |
| Bogon prefix rejection | Routing | ✓ | 0.0.0.0/8, 224.0.0.0/4 rejected |
| DHCP snooping | Data Plane | ✓ | Trusted uplinks only |
| Dynamic ARP Inspection | Data Plane | ✓ | MAC-IP validation |
| IP source guard | Data Plane | ✓ | DHCP binding enforcement |
| Storm control enabled | Data Plane | ✓ | 1% per traffic type |
| MAC address limiting | Data Plane | ✓ | Max 10 per port |
| VXLAN encapsulation | Overlay | ✓ | UDP 4789 only |
| EVPN route-target filtering | Overlay | ✓ | Explicit import/export |
| VRF tenant isolation | Overlay | ✓ | Cross-tenant traffic rejected |
| Syslog forwarding | Audit | ✓ | Real-time + local archive |
| Configuration backup | Audit | ✓ | Daily to 192.168.100.50 |
| NTP time sync | Audit | ✓ | Multiple servers, auth enabled |
| Secure console access | Physical | ✓ | Login required, timeout 5 min |
| USB ports disabled | Physical | ✓ | Hardware level |
| Secure boot enabled | Physical | ✓ | Firmware signature verification |
| HTTPS management disabled | Management | ✓ | SSH/NETCONF only |
| HTTP management disabled | Management | ✓ | SSH/NETCONF only |
| Telnet disabled | Management | ✓ | SSH v2 only |
| BGP session limits | Routing | ✓ | Max 60 leaves per spine |
| BFD enabled on all links | Control Plane | ✓ | 300ms failure detection |
| Interface MTU validation | Data Plane | ✓ | 1514 for VXLAN payload |
| Jumbo frames (MTU 9000) | Data Plane | ✓ | Core links, if needed |
| Spanning Tree disabled | Layer 2 | ✓ | TRILL/VXLAN-only fabric |
| Loop prevention (LLDP) | Data Plane | ✓ | Topology discovery |
| VLAN pruning | Data Plane | ✓ | Per-link VLAN lists |
| Access lists on all interfaces | Data Plane | ✓ | Implicit deny-all |
| Egress filtering enabled | Data Plane | ✓ | BCP 38/RFC 2827 |
| UPF (Unicast Reverse Path Forwarding) | Data Plane | ✓ | uRPF loose mode on leaves |
| Multicast source validation | Data Plane | ✓ | Prevent multicast flooding |
| TTL decrement on hops | Routing | ✓ | Standard IP behavior |
| ICMP rate limiting | Control Plane | ✓ | 10 Mbps policer |
| DNS query filtering | Management | ✓ | Only known resolvers |
| NTP auth enabled | Management | ✓ | MD5 or Symmetric key |
| Logging level appropriate | Audit | ✓ | Info for changes, Notice for errors |
| Core dumps disabled | Security | ✓ | Prevent information disclosure |
| Source routing disabled | Routing | ✓ | IP option filtering |
| ICMP redirect disabled | Routing | ✓ | ICMP Type 5 filtering |
| Unreachable messages limited | Routing | ✓ | ICMP Type 11 rate-limited |
| Timestamp response disabled | Routing | ✓ | ICMP Type 13 filtering |
| ARP request rate limiting | Data Plane | ✓ | 1000 ARP/sec max per interface |
| TCP SYN cookie enabled | Control Plane | ✓ | SYN flood mitigation |
| TCP connection timeouts | Control Plane | ✓ | Established: 86400s, Syn-sent: 120s |
| UDP idle timeout | Control Plane | ✓ | 60 seconds |
| ICMP echo-request limited | Control Plane | ✓ | 10 echo-requests/sec |

### 8.4 Junos Security Hardening Checklist (Extended)

**Management & Access Security (12 items)**
- SSH v2 exclusive (Telnet/HTTP/HTTPS disabled)
- Password policy: 20+ chars, 90-day rotation
- RADIUS/TACACS+ with dual servers
- Local fallback authentication configured
- Role-based access control (RBAC) via classes
- Session idle timeout: 15 min (admin), 30 min (operator)
- Failed login attempt lockout (3 attempts)
- SNMPv3 authentication and privacy enabled
- SNMPv1/v2c disabled
- NETCONF over SSH (port 830) enabled
- Certificate-based SSH key exchange supported
- Console access authentication required

**Control Plane Security (11 items)**
- CoPP filter on loopback interface
- BGP rate limiter: 50 Mbps (spine), 25 Mbps (leaf)
- BFD rate limiter: 10 Mbps (spine), 5 Mbps (leaf)
- SSH rate limiter: 1 Mbps
- SNMP rate limiter: 5 Mbps (spine), 2 Mbps (leaf)
- NTP rate limiter: 2 Mbps (spine), 1 Mbps (leaf)
- ICMP rate limiter: 10 Mbps (spine), 5 Mbps (leaf)
- NETCONF rate limiter: 5 Mbps (spine), 2 Mbps (leaf)
- DHCP relay rate limiter: 1 Mbps
- DDoS protection profiles active
- TCP SYN flood detection enabled

**Routing Security (10 items)**
- BGP MD5 authentication on all sessions
- BGP authentication key rotation (180 days)
- Bogon prefix rejection (0.0.0.0/8, 224.0.0.0/4, 240.0.0.0/4, 255.255.255.255/32)
- BGP max-prefix limits per peer
- BGP graceful restart enabled (120s)
- BGP GTSM (TTL=255 validation) enabled
- BGP session logging enabled
- EVPN route-target filtering explicit
- EVPN duplicate MAC detection enabled
- Static route blackholes for bogons

**Data Plane Security (12 items)**
- Storm control: broadcast 1%, multicast 1%, unknown-unicast 1%
- MAC address limiting: max 10 per port, action shutdown
- MAC move limit: max 5 moves per minute
- DHCP snooping enabled (trusted uplinks only)
- DHCP snooping binding database enabled
- Dynamic ARP Inspection enabled
- ARP request/response MAC-IP validation
- IP source guard enabled
- Static IP-MAC bindings for non-DHCP devices
- Port security enabled on all server-facing ports
- Interface ingress filtering enabled
- Egress filtering (BCP 38) enabled

**VXLAN & Overlay Security (8 items)**
- VXLAN encapsulation over UDP 4789 only
- VXLAN tunnel source/destination validation
- EVPN MAC-IP learning from ARP/ND
- VRF-based multi-tenancy isolation
- Cross-VRF traffic blocked (except via firewall)
- Route-target import/export policies explicit
- Micro-segmentation groups defined
- VXLAN header checksum validation enabled

**Physical & Hardware Security (4 items)**
- Console port authentication enabled
- Console inactivity timeout: 5 minutes
- USB ports disabled
- Secure boot enabled with firmware signature verification

**Audit & Compliance (8 items)**
- Syslog forwarding to remote server (192.168.100.50)
- Configuration changes logged with timestamp/user/content
- Local configuration archive (100 MB, 10 files, 90-day retention)
- Configuration backup to 192.168.100.50
- Change history retained (500 entries)
- Audit logs protected (read-only to operators)
- Time synchronization via NTP (authenticated)
- Security patch compliance validated

**VLAN & L2 Security (5 items)**
- Spanning Tree disabled (VXLAN-only fabric)
- VLAN pruning per-interface
- Native VLAN configuration restricted
- Protected ports enabled where needed
- Port-to-VLAN mapping explicit and documented

**Firewall & FortiGate Integration (5 items)**
- Active-active FortiGate pair (north of spines)
- Redundancy via FHRP (HSRP or VRRP)
- VXLAN decapsulation inspection enabled
- VNI-to-tenant mapping enforced
- Logging of all firewall policy drops/rejects

---

## 9. CIS Benchmark Alignment

This guide aligns with CIS Junos Benchmarks v2.0.0:

| CIS Control | JunOS Hardening | Status |
|-------------|-----------------|--------|
| 1.1 Enable SSH | SSH v2 exclusive enabled | ✓ |
| 1.2 Disable Telnet | Telnet disabled | ✓ |
| 1.3 Disable HTTP | HTTP/HTTPS management disabled | ✓ |
| 2.1 Strong passwords | Min 20 chars, 90-day rotation | ✓ |
| 2.2 Login banner | Legal warning banner enabled | ✓ |
| 3.1 SNMP v3 only | SNMPv3 auth/privacy, v1/v2c disabled | ✓ |
| 4.1 NTP authentication | NTP MD5 auth enabled | ✓ |
| 5.1 Syslog remote | Dual syslog servers, local archive | ✓ |
| 5.2 Log retention | 90-day minimum | ✓ |
| 6.1 BGP authentication | MD5 on all eBGP sessions | ✓ |
| 6.2 BGP filtering | Bogon/RFC2827 prefix filtering | ✓ |
| 7.1 Interface security | Storm control, MAC limiting, DAI | ✓ |
| 7.2 DHCP snooping | Enabled, trusted uplinks only | ✓ |
| 8.1 CoPP enabled | All protocols rate-limited | ✓ |
| 8.2 ACL implicit deny | Deny-all on all interfaces | ✓ |

---

## 10. Incident Response

### 10.1 Network Security Incident Playbook

**Playbook: DDoS Attack on BGP Control Plane**

**Detection:** CoPP policer drops exceed baseline by >500%

**Response Steps:**
1. **Immediate (0-5 min):**
   - Page on-call network engineer
   - Execute `show security ddos-protection statistics`
   - Identify attack source using `show log messages`
   - Capture packets: `monitor traffic interface et-0/0/48 size 128 count 1000 no-resolve`

2. **Short-term (5-15 min):**
   - Increase BGP policer to 100 Mbps (temporary)
   - Enable source-based policers to rate-limit specific ASNs
   - Contact ISP to apply upstream filtering
   - Document attack timeline and affected devices

3. **Medium-term (15-60 min):**
   - Implement BGP prefix filtering to reject attack sources
   - Adjust CoPP policers based on attack patterns
   - Notify security team for log analysis
   - Review BGP peer authentication logs

4. **Long-term (After 60 min):**
   - Post-incident review meeting
   - Implement additional DDoS detection thresholds
   - Update network monitoring baselines
   - Document lessons learned

### 10.2 Isolation Procedures

**Quarantine a Single Server Port:**

```junos
interfaces {
    et-0/0/0 {
        disable;
        description "QUARANTINED - Investigation in progress";
    }
}
```

Then investigate. To restore:

```junos
interfaces {
    et-0/0/0 {
        enable;
    }
}
```

**Quarantine an Entire VLAN:**

```junos
vlans {
    compromised-vlan {
        vlan-id 999;
        description "QUARANTINED - Isolation VLAN";
    }
}
policy-statement quarantine-policy {
    term isolate {
        from {
            vlan 999;
        }
        then {
            discard;
        }
    }
}
interfaces {
    vlan.999 {
        family inet {
            filter {
                input quarantine-policy;
            }
        }
    }
}
```

**Quarantine a Rack (Multiple Leaf Switches):**

```junos
policy-statement rack-isolation {
    term deny-rack-100 {
        from {
            source-address 10.1.0.0/16;
        }
        then discard;
    }
}
interfaces {
    lo0 {
        unit 0 {
            family inet {
                filter {
                    input rack-isolation;
                }
            }
        }
    }
}
```

### 10.3 Forensics: What to Collect and Where Logs Are Stored

**Critical Data Collection (First 5 Minutes):**

```bash
# On affected device
request system capture interface et-0/0/48 size 128 count 10000 filename /var/tmp/capture.pcap
request session clear all

# Save running config
request system snapshot filename /var/tmp/config-snapshot-$(date +%s).txt

# Export routing table
request routing-engine login
show route > /var/tmp/routes.txt
show bgp summary > /var/tmp/bgp-summary.txt

# Security logs
show log messages | match "SECURITY\|authentication\|firewall" > /var/tmp/security-logs.txt

# CoPP statistics
show security ddos-protection statistics > /var/tmp/copp-stats.txt
```

**Log Storage Locations:**

| Log Type | Location | Retention | Format |
|----------|----------|-----------|--------|
| Syslog | /var/log/messages | 90 days | Text |
| Configuration changes | /var/log/default-log | 90 days | Text |
| Authentication | /var/log/security | 30 days | Text |
| BGP debug | /var/log/bgp | 7 days | Text |
| Traffic captures | /var/tmp/ | 1 hour | PCAP |
| Remote syslog | 192.168.100.50:/logs/fabric/ | Indefinite | Text |

**Forensic Analysis Checklist:**

- [ ] Extract PCAP from affected devices
- [ ] Correlate syslog timestamps across fabric
- [ ] Identify first occurrence of anomaly
- [ ] Extract relevant BGP/BFD hello packets
- [ ] Reconstruct attacker's IP/MAC source
- [ ] Cross-reference firewall logs (FortiGate)
- [ ] Review configuration changes 24 hours prior
- [ ] Preserve all logs before rotation
- [ ] Generate executive summary with timeline
- [ ] Brief security team on findings

---

## 11. Complete Reference Configurations

### 11.1 Full CoPP Filter Config for Spine (QFX5220)

```junos
set firewall policer bgp-peer-limit if-exceeding bandwidth-limit 50m
set firewall policer bgp-peer-limit if-exceeding burst-size-limit 5m
set firewall policer bgp-peer-limit then discard
set firewall policer bfd-limit if-exceeding bandwidth-limit 10m
set firewall policer bfd-limit if-exceeding burst-size-limit 1m
set firewall policer bfd-limit then discard
set firewall policer ssh-limit if-exceeding bandwidth-limit 1m
set firewall policer ssh-limit if-exceeding burst-size-limit 100k
set firewall policer ssh-limit then discard
set firewall policer snmp-limit if-exceeding bandwidth-limit 5m
set firewall policer snmp-limit if-exceeding burst-size-limit 500k
set firewall policer snmp-limit then discard
set firewall policer ntp-limit if-exceeding bandwidth-limit 2m
set firewall policer ntp-limit if-exceeding burst-size-limit 200k
set firewall policer ntp-limit then discard
set firewall policer icmp-limit if-exceeding bandwidth-limit 10m
set firewall policer icmp-limit if-exceeding burst-size-limit 1m
set firewall policer icmp-limit then discard
set firewall policer netconf-limit if-exceeding bandwidth-limit 5m
set firewall policer netconf-limit if-exceeding burst-size-limit 500k
set firewall policer netconf-limit then discard
set firewall policer dhcp-limit if-exceeding bandwidth-limit 1m
set firewall policer dhcp-limit if-exceeding burst-size-limit 100k
set firewall policer dhcp-limit then discard
set firewall filter copp-filter-lo0 term permit-bgp-v4 from destination-address 10.0.0.0/24
set firewall filter copp-filter-lo0 term permit-bgp-v4 from protocol tcp
set firewall filter copp-filter-lo0 term permit-bgp-v4 from destination-port 179
set firewall filter copp-filter-lo0 term permit-bgp-v4 then policer bgp-peer-limit
set firewall filter copp-filter-lo0 term permit-bgp-v4 then accept
set firewall filter copp-filter-lo0 term permit-bgp-v6 from destination-address 2001:db8::/32
set firewall filter copp-filter-lo0 term permit-bgp-v6 from protocol tcp
set firewall filter copp-filter-lo0 term permit-bgp-v6 from destination-port 179
set firewall filter copp-filter-lo0 term permit-bgp-v6 then policer bgp-peer-limit
set firewall filter copp-filter-lo0 term permit-bgp-v6 then accept
set firewall filter copp-filter-lo0 term permit-bfd-v4 from destination-address 10.0.0.0/24
set firewall filter copp-filter-lo0 term permit-bfd-v4 from protocol udp
set firewall filter copp-filter-lo0 term permit-bfd-v4 from destination-port 3784
set firewall filter copp-filter-lo0 term permit-bfd-v4 then policer bfd-limit
set firewall filter copp-filter-lo0 term permit-bfd-v4 then accept
set firewall filter copp-filter-lo0 term permit-bfd-v6 from destination-address 2001:db8::/32
set firewall filter copp-filter-lo0 term permit-bfd-v6 from protocol udp
set firewall filter copp-filter-lo0 term permit-bfd-v6 from destination-port 3784
set firewall filter copp-filter-lo0 term permit-bfd-v6 then policer bfd-limit
set firewall filter copp-filter-lo0 term permit-bfd-v6 then accept
set firewall filter copp-filter-lo0 term permit-ssh-v4 from destination-address 192.168.100.0/24
set firewall filter copp-filter-lo0 term permit-ssh-v4 from protocol tcp
set firewall filter copp-filter-lo0 term permit-ssh-v4 from destination-port 22
set firewall filter copp-filter-lo0 term permit-ssh-v4 then policer ssh-limit
set firewall filter copp-filter-lo0 term permit-ssh-v4 then accept
set firewall filter copp-filter-lo0 term permit-ssh-v6 from destination-address 2001:db8:100::/48
set firewall filter copp-filter-lo0 term permit-ssh-v6 from protocol tcp
set firewall filter copp-filter-lo0 term permit-ssh-v6 from destination-port 22
set firewall filter copp-filter-lo0 term permit-ssh-v6 then policer ssh-limit
set firewall filter copp-filter-lo0 term permit-ssh-v6 then accept
set firewall filter copp-filter-lo0 term permit-netconf-v4 from destination-address 192.168.100.0/24
set firewall filter copp-filter-lo0 term permit-netconf-v4 from protocol tcp
set firewall filter copp-filter-lo0 term permit-netconf-v4 from destination-port 830
set firewall filter copp-filter-lo0 term permit-netconf-v4 then policer netconf-limit
set firewall filter copp-filter-lo0 term permit-netconf-v4 then accept
set firewall filter copp-filter-lo0 term permit-snmp-v4 from destination-address 192.168.100.0/24
set firewall filter copp-filter-lo0 term permit-snmp-v4 from protocol udp
set firewall filter copp-filter-lo0 term permit-snmp-v4 from destination-port 161
set firewall filter copp-filter-lo0 term permit-snmp-v4 then policer snmp-limit
set firewall filter copp-filter-lo0 term permit-snmp-v4 then accept
set firewall filter copp-filter-lo0 term permit-snmp-trap-v4 from protocol udp
set firewall filter copp-filter-lo0 term permit-snmp-trap-v4 from destination-port 162
set firewall filter copp-filter-lo0 term permit-snmp-trap-v4 then policer snmp-limit
set firewall filter copp-filter-lo0 term permit-snmp-trap-v4 then accept
set firewall filter copp-filter-lo0 term permit-ntp-v4 from protocol udp
set firewall filter copp-filter-lo0 term permit-ntp-v4 from destination-port 123
set firewall filter copp-filter-lo0 term permit-ntp-v4 then policer ntp-limit
set firewall filter copp-filter-lo0 term permit-ntp-v4 then accept
set firewall filter copp-filter-lo0 term permit-icmp-v4 from protocol icmp
set firewall filter copp-filter-lo0 term permit-icmp-v4 then policer icmp-limit
set firewall filter copp-filter-lo0 term permit-icmp-v4 then accept
set firewall filter copp-filter-lo0 term permit-icmp-v6 from protocol icmpv6
set firewall filter copp-filter-lo0 term permit-icmp-v6 then policer icmp-limit
set firewall filter copp-filter-lo0 term permit-icmp-v6 then accept
set firewall filter copp-filter-lo0 term permit-dhcp-relay from protocol udp
set firewall filter copp-filter-lo0 term permit-dhcp-relay from source-port 68
set firewall filter copp-filter-lo0 term permit-dhcp-relay from destination-port 67
set firewall filter copp-filter-lo0 term permit-dhcp-relay then policer dhcp-limit
set firewall filter copp-filter-lo0 term permit-dhcp-relay then accept
set firewall filter copp-filter-lo0 term deny-all then discard
set interfaces lo0 unit 0 family inet filter input copp-filter-lo0
set interfaces lo0 unit 0 family inet6 filter input copp-filter-lo0
```

### 11.2 Full Port-Security Config for Leaf Server Ports

```junos
set interfaces et-0/0/0 description "Server Port 1"
set interfaces et-0/0/0 mtu 1514
set interfaces et-0/0/0 unit 0 family ethernet-switching vlan members server-vlan
set interfaces et-0/0/0 unit 0 family ethernet-switching port-security enabled
set interfaces et-0/0/0 unit 0 family ethernet-switching port-security maximum-mac-count 10
set interfaces et-0/0/0 unit 0 family ethernet-switching port-security mac-move-limit 5
set interfaces et-0/0/0 unit 0 family ethernet-switching port-security violation-action shutdown
set interfaces et-0/0/0 unit 0 family ethernet-switching port-security notification alert
set interfaces et-0/0/0 unit 0 family ethernet-switching storm-control broadcast-limit 1
set interfaces et-0/0/0 unit 0 family ethernet-switching storm-control multicast-limit 1
set interfaces et-0/0/0 unit 0 family ethernet-switching storm-control unknown-unicast-limit 1

set vlans server-vlan vlan-id 100
set vlans server-vlan l3-interface vlan.100
set vlans server-vlan dhcp-snooping enabled
set vlans server-vlan dhcp-snooping trusted-interface et-0/0/48
set vlans server-vlan dhcp-snooping trusted-interface et-0/0/49

set security dynamic-arp-inspection enabled
set security dynamic-arp-inspection ip-table vlan.100 arp-request validate source-mac
set security dynamic-arp-inspection ip-table vlan.100 arp-request validate destination-mac
set security dynamic-arp-inspection ip-table vlan.100 arp-response validate source-mac
set security dynamic-arp-inspection ip-table vlan.100 arp-response validate destination-mac

set security ip-source-guard enabled
set security ip-source-guard interface et-0/0/0 trusted
set security ip-source-guard interface et-0/0/48 trusted
set security ip-source-guard interface et-0/0/49 trusted
```

### 11.3 RADIUS/TACACS+ Configuration

```junos
set system radius-server 192.168.100.10 secret "$9$radiuskey123456..."
set system radius-server 192.168.100.10 timeout 5
set system radius-server 192.168.100.10 retry 2
set system radius-server 192.168.100.10 port 1812
set system radius-server 192.168.100.11 secret "$9$radiuskey789012..."
set system radius-server 192.168.100.11 timeout 5
set system radius-server 192.168.100.11 retry 2
set system radius-server 192.168.100.11 port 1812
set system tacplus-server 192.168.100.20 secret "$9$tackey123456..."
set system tacplus-server 192.168.100.20 timeout 5
set system tacplus-server 192.168.100.20 retry 2
set system tacplus-server 192.168.100.20 port 49
set system tacplus-server 192.168.100.21 secret "$9$tackey789012..."
set system tacplus-server 192.168.100.21 timeout 5
set system tacplus-server 192.168.100.21 retry 2
set system tacplus-server 192.168.100.21 port 49
set system authentication-order radius
set system authentication-order tacplus
set system accounting events login
set system accounting events change-log
set system accounting destination radius
set system accounting destination syslog
```

### 11.4 SNMPv3 Configuration

```junos
set snmp3 usm local-engine user monitoring authentication-type sha
set snmp3 usm local-engine user monitoring authentication-password "$9$snmpkey1234..."
set snmp3 usm local-engine user monitoring privacy-type aes-128
set snmp3 usm local-engine user monitoring privacy-password "$9$snmpprivacy5678..."
set snmp3 usm local-engine user admin authentication-type sha
set snmp3 usm local-engine user admin authentication-password "$9$snmpadmin1234..."
set snmp3 usm local-engine user admin privacy-type aes-128
set snmp3 usm local-engine user admin privacy-password "$9$snmpadmin5678..."
set snmp3 access group monitoring security-model usm
set snmp3 access group monitoring security-level authentication
set snmp3 access group monitoring prefix all
set snmp3 access group admin security-model usm
set snmp3 access group admin security-level privacy
set snmp3 access group admin prefix all
set snmp3 trap group monitoring version v3
set snmp3 trap group monitoring targets 192.168.100.60
set snmp3 trap group monitoring targets 192.168.100.61
```

---

## 12. Maintenance and Continuous Improvement

### 12.1 Quarterly Security Reviews

- Review CoPP policer hit rates; adjust thresholds if necessary
- Analyze authentication logs for failed attempts or anomalies
- Verify all BGP sessions are authenticated
- Check configuration change audit trail
- Validate syslog forwarding is operational
- Review firewall logs from FortiGate pair

### 12.2 Annual Security Assessment

- Conduct penetration test on management interfaces
- Validate physical console security
- Review third-party security audit reports
- Update CIS benchmark alignment
- Assess emerging threat landscape
- Plan security patching schedule

### 12.3 Patch Management

**Baseline:** All devices running JunOS v20.1R1 or later (supports VXLAN, EVPN, SNMPv3)

**Security Patching SLA:**
- Critical: Apply within 48 hours
- High: Apply within 2 weeks
- Medium: Apply within 1 month
- Low: Apply with next scheduled upgrade

**Patching Procedure:**
1. Test in staging environment (lab replication)
2. Prepare rollback plan
3. Schedule maintenance window
4. Apply to secondary device first (e.g., Leaf-2 before Leaf-1)
5. Validate all protocols operational
6. Document patch level in CMDB

---

## 13. Support and References

**Juniper Documentation:**
- JunOS Security Configuration Guide: https://www.juniper.net/documentation/product/en_US/junos/
- QFX5220 Hardware Installation Guide: https://www.juniper.net/documentation/product/en_US/qfx5220/
- QFX5120 Product Documentation: https://www.juniper.net/documentation/product/en_US/qfx5120/

**External Standards:**
- CIS Junos Benchmark v2.0.0: https://www.cisecurity.org/cis-benchmarks/
- RFC 2827 (Egress Filtering): https://tools.ietf.org/html/rfc2827
- RFC 3704 (Ingress Filtering): https://tools.ietf.org/html/rfc3704
- RFC 8212 (BGP Default Route Advertisement): https://tools.ietf.org/html/rfc8212

**Internal Contacts:**
- Network Security Lead: security-team@company.com
- On-Call Engineer: oncall@company.com (24/7 hotline)
- Change Advisory Board: cab@company.com

---

**Document Status:** APPROVED
**Last Reviewed:** 2026-03-25
**Next Review:** 2026-06-25 (quarterly)
**Classification:** INTERNAL USE ONLY
