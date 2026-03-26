# Juniper Spine-Leaf Datacenter Fabric Ansible Automation

Complete production-ready Ansible automation framework for managing a Juniper spine-leaf datacenter fabric with EVPN overlay.

## Architecture Overview

### Fabric Components
- **4 Spine Switches**: QFX5220-32CD (ASN 65000, Route Reflectors)
- **60 Leaf Switches**: QFX5120-48Y (ASN 65001-65060, EVPN Clients)
- **Management Network**: 10.255.0.0/24 (spines), 10.255.1.0/24 (leaves)
- **Overlay**: EVPN with VXLAN encapsulation
- **Underlay**: BGP with BFD fast failure detection

## Directory Structure

```
ansible/
├── ansible.cfg                 # Main Ansible configuration
├── requirements.yml            # Galaxy collection requirements
├── inventory/
│   ├── hosts.yml              # Host inventory with all devices
│   ├── group_vars/
│   │   ├── all.yml            # Global variables for all devices
│   │   ├── spines.yml         # Spine-specific variables
│   │   └── leaves.yml         # Leaf-specific variables
│   └── host_vars/
│       ├── dc1-spine-01.yml   # Spine-01 specific config
│       ├── dc1-spine-02.yml   # Spine-02 specific config
│       ├── dc1-leaf-001.yml   # Leaf-001 specific config
│       └── dc1-leaf-002.yml   # Leaf-002 specific config (+ 58 more)
├── playbooks/
│   ├── site.yml               # Master playbook
│   ├── deploy_base.yml        # Base configuration
│   ├── deploy_interfaces.yml  # Interface configuration
│   ├── deploy_routing.yml     # BGP and EVPN setup
│   ├── deploy_security.yml    # Security hardening
│   ├── deploy_monitoring.yml  # SNMP, syslog, telemetry
│   ├── backup_configs.yml     # Configuration backup
│   ├── validate_fabric.yml    # Fabric validation checks
│   └── upgrade_firmware.yml   # Rolling firmware upgrade
├── roles/
│   ├── base_config/           # System base config role
│   ├── interfaces/            # Interface configuration role
│   ├── routing/               # BGP and EVPN role
│   ├── security/              # Security hardening role
│   └── monitoring/            # Monitoring and telemetry role
├── tasks/
│   └── validate_bgp.yml       # BGP validation task
└── README.md                  # This file
```

## Quick Start

### 1. Install Dependencies

```bash
# Install required Ansible collections
ansible-galaxy collection install -r requirements.yml

# Install Python dependencies
pip install ncclient pyyaml paramiko jinja2
```

### 2. Configure Vault (Optional but Recommended)

Create a vault file for sensitive data:

```bash
ansible-vault create inventory/group_vars/vault.yml
```

Add sensitive variables:
```yaml
vault_ansible_password: "your_password_here"
vault_snmp_community: "your_snmp_community"
vault_snmp_v3_password: "your_snmp_v3_password"
vault_netadmin_password: "your_netadmin_password"
vault_admin_password: "your_admin_password"
vault_bgp_auth_key: "your_bgp_auth_key"
```

### 3. Update Inventory

Edit `inventory/hosts.yml` with your actual device IPs:

```yaml
dc1-spine-01:
  ansible_host: 10.255.0.1     # Update with actual management IP
```

Update `inventory/host_vars/` files with actual device configuration values.

### 4. Dry Run / Check Mode

Test configuration without applying changes:

```bash
ansible-playbook playbooks/site.yml --check
```

### 5. Deploy Configuration

Deploy complete fabric configuration:

```bash
# Deploy base configuration only
ansible-playbook playbooks/deploy_base.yml

# Deploy interfaces
ansible-playbook playbooks/deploy_interfaces.yml

# Deploy routing (BGP/EVPN)
ansible-playbook playbooks/deploy_routing.yml

# Deploy security
ansible-playbook playbooks/deploy_security.yml

# Deploy monitoring
ansible-playbook playbooks/deploy_monitoring.yml

# Deploy all in sequence
ansible-playbook playbooks/site.yml
```

## Playbook Guide

### site.yml (Master Playbook)
Orchestrates complete fabric deployment:
- Pre-flight validation
- Executes all roles in sequence
- Post-deployment validation
- Configuration backup

### deploy_base.yml
Configures base system settings:
- Hostname, domain name, timezone
- NTP servers
- DNS servers
- Syslog forwarding
- SNMP community and v3
- User accounts
- SSH hardening
- NETCONF configuration
- Login banner

### deploy_interfaces.yml
Configures all interface types:
- Loopback interfaces (lo0)
- Management interface (em0)
- P2P underlay links (GigabitEthernet)
- Server-facing access ports (on leaves)
- VLANs and IRB gateways (on leaves)
- LAG configuration for multi-homed servers
- BFD on critical links
- MTU and speed configuration

### deploy_routing.yml
Configures underlay and overlay:
- BGP underlay (eBGP between spines and leaves)
- EVPN overlay (iBGP on spines as RRs, leaves as clients)
- Route policies and prefix lists
- ECMP and multipath configuration
- BGP authentication
- Graceful restart
- VXLAN encapsulation
- VRF configuration

### deploy_security.yml
Implements security hardening:
- Control Plane Policing (CoPP) filters
- Port security on leaf access ports
- Storm control on all interfaces
- SSH hardening (ciphers, key exchange, algorithms)
- DoS protection settings
- Firewall zone configuration
- Rate limiting for critical protocols
- Syslog for security events

### deploy_monitoring.yml
Sets up comprehensive monitoring:
- SNMP community and v3 configuration
- SNMP trap groups
- Syslog forwarding with structured data
- gRPC for streaming telemetry
- OpenConfig metric server
- Interface statistics collection
- BGP monitoring and dampening
- LLDP for topology discovery
- System health monitoring

### backup_configs.yml
Backs up device configurations:
- Saves running configs in multiple formats (XML, set)
- Exports device facts to JSON
- Backs up BGP, interface, routing configs separately
- Creates tarballs of all backups
- Generates configuration diffs
- Archives old backups (>30 days)

### validate_fabric.yml
Comprehensive fabric validation:
- NETCONF connectivity check
- BGP session validation
- EVPN route verification
- Interface status checks
- LLDP neighbor discovery
- Routing table validation
- System health monitoring
- Chassis and alarm status
- Spine/leaf reachability tests

### upgrade_firmware.yml
Rolling firmware upgrade process:
- Backs up configuration before upgrade
- Validates maintenance window
- Transfers firmware packages
- Performs upgrade with validation
- Handles device reboot
- Verifies firmware version post-upgrade
- Validates BGP session recovery
- Generates audit logs

## Role Structure

Each role contains:
- `tasks/main.yml`: Task definitions
- `templates/*.j2`: Jinja2 configuration templates

### base_config Role
Generates base system configuration using template

### interfaces Role
Configures loopbacks, P2P links, VLANs, and server ports

### routing Role
Configures BGP underlay, EVPN overlay, and route policies

### security Role
Implements CoPP, port security, firewalls, and hardening

### monitoring Role
Configures SNMP, syslog, gRPC, and telemetry

## Variables Organization

### Global Variables (all.yml)
- NTP servers, DNS servers
- Syslog and SNMP configuration
- SSH and NETCONF settings
- User accounts
- Monitoring thresholds

### Spine Variables (spines.yml)
- ASN: 65000
- EVPN role: route-reflector
- Device model: QFX5220-32CD
- Route reflection settings

### Leaf Variables (leaves.yml)
- ASN: 65001-65060 (per host)
- EVPN role: client
- Device model: QFX5120-48Y
- VLAN/VNI mappings
- VRF configuration
- Server port settings

### Host Variables (host_vars/*)
- Hostname, management IP, loopback IP
- BGP neighbors list
- Interface configurations
- ESI settings for multi-homing
- EVPN import/export targets

## Vault Integration

Use Ansible Vault to protect sensitive data:

```bash
# Encrypt specific file
ansible-vault encrypt inventory/group_vars/vault.yml

# Run playbook with vault
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --ask-vault-pass

# Use vault password file (less secure)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --vault-password-file=.vault_pass
```

## Tags for Selective Execution

Run specific configuration stages using tags:

```bash
# Deploy only BGP routing
ansible-playbook playbooks/site.yml -t bgp

# Deploy interfaces and BGP
ansible-playbook playbooks/site.yml -t interfaces,bgp

# Run validation only
ansible-playbook playbooks/validate_fabric.yml -t validate

# Exclude security hardening
ansible-playbook playbooks/site.yml --skip-tags security
```

Available tags:
- `base`: Base system configuration
- `ntp`, `dns`, `syslog`: Specific base services
- `interfaces`, `loopback`, `p2p`, `vlans`: Interface configuration
- `bgp`, `evpn`, `underlay`, `overlay`: Routing
- `security`, `copp`, `port_security`: Security
- `monitoring`, `snmp`, `syslog`: Monitoring
- `backup`, `validate`, `commit`: Operations

## Backup and Recovery

Automated backups created by `backup_configs.yml`:

```
/var/backups/configs/
├── dc1-spine-01_config_<timestamp>.xml
├── dc1-spine-01_config_<timestamp>.set
├── dc1-spine-01_bgp_<timestamp>.conf
├── dc1-spine-01_interfaces_<timestamp>.conf
├── dc1-spine-01_facts_<timestamp>.json
└── ... (similar for all devices)
```

Restore configuration from backup:

```bash
# SSH to device
ssh admin@10.255.0.1

# Load and commit configuration
load set /tmp/config_backup.set
commit
```

## Monitoring and Observability

### SNMP
- Community: `{{ snmp_community }}` (read-only)
- v3 user: `{{ snmp_v3_username }}`
- Trap targets: `{{ snmp_trap_targets }}`

### Syslog
- Forwarded to: `{{ syslog_servers }}`
- Port: `{{ syslog_port }}`
- Facility: `{{ syslog_facility }}`

### Streaming Telemetry
- gRPC port: `{{ grpc_port }}`
- OpenConfig metric server: Telegraf
- Enabled on all devices when `grpc_enabled: true`

## Best Practices

1. **Always use check mode first**: `ansible-playbook --check`
2. **Use vault for sensitive data**: Never commit passwords in plain text
3. **Backup before major changes**: Run `backup_configs.yml` before deployments
4. **Validate fabric health**: Run `validate_fabric.yml` after changes
5. **Use git for version control**: Track all configuration changes
6. **Test in staging first**: Never deploy directly to production
7. **Use serial/batch deployment**: Roll out changes to devices gradually
8. **Monitor upgrade windows**: Coordinate firmware upgrades during maintenance windows

## Troubleshooting

### NETCONF Connection Issues
```bash
# Test NETCONF connectivity
ssh -p 830 admin@10.255.0.1

# Enable NETCONF SSH service
show system services netconf
```

### BGP Session Not Established
```bash
# Check BGP neighbor status
show bgp neighbor detail

# Verify interface configuration
show interfaces et-0/0/44 detail

# Check BFD status
show bfd session
```

### Ansible Connection Problems
```bash
# Increase verbosity
ansible-playbook -vvv playbooks/site.yml

# Test inventory
ansible-inventory -i inventory/hosts.yml --list
```

## Performance Tuning

Configuration parameters can be adjusted in `ansible.cfg`:
- `forks = 10`: Parallel execution across devices
- `timeout = 30`: NETCONF operation timeout
- `serial = 30%`: Deploy to 30% of devices in parallel

## Contributing

When adding new features:
1. Create new role in `roles/` directory
2. Add variables to appropriate `group_vars/` or `host_vars/` file
3. Create Jinja2 template if complex configuration
4. Add tasks to role's `tasks/main.yml`
5. Reference role in appropriate playbook
6. Test with `--check` before deployment

## Support and Documentation

- **Juniper Junos**: https://www.juniper.net/documentation/
- **Ansible Juniper Collection**: https://github.com/ansible-collections/junipernetworks.junos
- **EVPN on Junos**: https://www.juniper.net/documentation/us/en/junos/topics/concept/evpn-overview.html
- **NETCONF Protocol**: https://tools.ietf.org/html/rfc6241

## License

This automation framework is provided as-is for network automation purposes.

---

**Created**: March 2026
**Version**: 1.0
**Maintained by**: Network Automation Team
