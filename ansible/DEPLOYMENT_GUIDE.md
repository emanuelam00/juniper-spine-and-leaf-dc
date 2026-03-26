# Juniper Spine-Leaf Datacenter Fabric Deployment Guide

## Pre-Deployment Checklist

- [ ] All devices accessible via NETCONF (port 830)
- [ ] Device credentials available
- [ ] Loopback IPs assigned (192.0.2.0/26 for spines, 192.0.2.64/26 for leaves)
- [ ] Management IPs configured (10.255.0.0/24 for spines, 10.255.1.0/24 for leaves)
- [ ] P2P IP addressing scheme defined (10.0.0.0/16)
- [ ] Vault file created and populated with secrets
- [ ] Inventory file updated with actual device IPs
- [ ] Host variables updated with device-specific configs

## Phase 1: Preparation (Day -1)

### 1.1 Create Vault File

```bash
ansible-vault create inventory/group_vars/vault.yml
```

Add the following (update with actual values):
```yaml
vault_ansible_password: "SecurePassword123!"
vault_admin_password: "AdminPassword456!"
vault_netadmin_password: "NetAdminPass789!"
vault_snmp_community: "YourSNMPComm123"
vault_snmp_v3_password: "SNMPv3Pass456!"
vault_bgp_auth_key: "BGPAuthKey789!"
```

### 1.2 Update Inventory

Edit `inventory/hosts.yml`:
- Replace management IPs with actual device IPs
- Verify ansible_user is correct (default: admin)
- Ensure ansible_port 830 for NETCONF

Edit `inventory/host_vars/`:
- Update loopback IPs for each device
- Update management IPs for each device
- Update P2P neighbor IPs
- Configure VLANs and VNIs for leaves

### 1.3 Validate Connectivity

```bash
# Test NETCONF connectivity to all devices
ansible-inventory -i inventory/hosts.yml --list | grep ansible_host

# Test with ansible
ansible dc_fabric -m junos_facts --ask-vault-pass
```

## Phase 2: Pre-Deployment Validation (Day 0, Morning)

### 2.1 Check Current Device State

```bash
# Check current configuration
ansible-playbook playbooks/validate_fabric.yml --ask-vault-pass -t connectivity

# Backup current configurations
ansible-playbook playbooks/backup_configs.yml --ask-vault-pass
```

### 2.2 Dry Run Deployment

```bash
# Check mode - no changes applied
ansible-playbook playbooks/site.yml --check --ask-vault-pass

# Review the output for any errors or unexpected changes
```

## Phase 3: Base Configuration Deployment (Day 0, Off-Peak Hours)

Deploy in this order, validating after each step:

### 3.1 Deploy Base Configuration

```bash
# Deploy base config to all devices
ansible-playbook playbooks/deploy_base.yml --ask-vault-pass

# Verify successful
ansible-playbook playbooks/validate_fabric.yml --ask-vault-pass -t connectivity
```

**Configuration applied:**
- Hostname, domain name, timezone
- NTP servers
- DNS configuration
- System users
- SSH hardening
- SNMP configuration
- Syslog setup
- NETCONF configuration

**Expected state:** Devices reachable via NETCONF, basic system parameters configured

### 3.2 Deploy Interface Configuration

```bash
# Deploy interface config
ansible-playbook playbooks/deploy_interfaces.yml --ask-vault-pass

# Verify interfaces are configured
ansible dc_fabric -m junos_command -a "commands='show interfaces terse'" --ask-vault-pass
```

**Configuration applied:**
- Loopback interfaces
- P2P underlay links
- Server-facing access ports (leaves)
- VLAN and IRB interfaces (leaves)
- Management interface
- BFD configuration

**Expected state:** All P2P links are "up", loopbacks configured

### 3.3 Deploy Routing Configuration

```bash
# Deploy BGP and EVPN
ansible-playbook playbooks/deploy_routing.yml --ask-vault-pass

# Monitor BGP convergence (takes 30-60 seconds)
ansible dc_fabric -m junos_command -a "commands='show bgp summary'" --ask-vault-pass

# Wait for BGP sessions to establish
sleep 60

# Verify BGP health
ansible-playbook playbooks/validate_fabric.yml --ask-vault-pass -t bgp
```

**Configuration applied:**
- BGP underlay (eBGP spines to leaves)
- EVPN overlay (iBGP, spines as RRs)
- Route policies and filters
- ECMP configuration
- VRFs on leaves
- VXLAN encapsulation

**Expected state:** BGP sessions "established", EVPN routes learned

### 3.4 Deploy Security Configuration

```bash
# Deploy security hardening
ansible-playbook playbooks/deploy_security.yml --ask-vault-pass

# Verify CoPP is active
ansible dc_fabric -m junos_command -a "commands='show firewall filter copp-filter'" --ask-vault-pass
```

**Configuration applied:**
- CoPP (Control Plane Policing)
- Port security (leaves)
- Storm control
- SSH hardening
- DoS protection
- Firewall zones
- Rate limiting

**Expected state:** CoPP filter active, SSH working with hardened settings

### 3.5 Deploy Monitoring Configuration

```bash
# Deploy monitoring and telemetry
ansible-playbook playbooks/deploy_monitoring.yml --ask-vault-pass

# Verify SNMP configuration
ansible dc_fabric -m junos_command -a "commands='show snmp'" --ask-vault-pass

# If gRPC enabled, verify status
ansible dc_fabric -m junos_command -a "commands='show system grpc status'" --ask-vault-pass
```

**Configuration applied:**
- SNMP community and v3
- SNMP trap targets
- Syslog forwarding
- gRPC/streaming telemetry
- OpenConfig metric server
- Statistics collection
- LLDP topology discovery

**Expected state:** SNMP responding, syslog receiving, telemetry stream active

## Phase 4: Comprehensive Validation (Day 0, End of Window)

```bash
# Full fabric validation
ansible-playbook playbooks/validate_fabric.yml --ask-vault-pass

# Expected results:
# - All BGP neighbors established
# - EVPN routes learned
# - All interfaces up
# - LLDP neighbors discovered
# - No critical alarms
# - System resources healthy
```

## Phase 5: Post-Deployment Verification (Day 1)

### 5.1 Connectivity Verification

```bash
# Ping from spine to leaf loopbacks
ansible spines -m junos_command -a "commands='request shell execute \"ping -c 1 192.0.2.65\"'" --ask-vault-pass

# Expected: PING is reachable
```

### 5.2 Traffic Verification

Perform on a test VLAN:
```
1. Configure test VLANs on two leaves
2. Attach test servers to leaves
3. Verify inter-VLAN routing via leaf gateway IPs
4. Verify VXLAN tunnel is operational
5. Verify packet replication for unknown unicast
```

### 5.3 Monitor System Logs

```bash
# Check for any errors or warnings
ssh admin@10.255.0.1 "show log messages | last 20"
ssh admin@10.255.1.1 "show log messages | last 20"
```

## Phase 6: Firmware Upgrade (Optional, Separate Maintenance Window)

After fabric is stable (minimum 48 hours):

```bash
# Perform rolling firmware upgrade
# Read upgrade_firmware.yml playbook for detailed procedure
ansible-playbook playbooks/upgrade_firmware.yml --ask-vault-pass
```

## Rollback Procedure

If issues occur, rollback to previous configuration:

### Manual Rollback on Individual Device

```bash
# SSH to device
ssh admin@10.255.0.1

# Show available rollback points
show system commit log

# Rollback to previous configuration
rollback [commit_number]
commit
```

### Ansible Rollback

```bash
# Rollback all devices to clean state
ansible dc_fabric -m junos_config -a "rollback=0" --ask-vault-pass

# Commit empty (reverts to last saved)
ansible dc_fabric -m junos_config -a "commit=yes" --ask-vault-pass
```

## Troubleshooting During Deployment

### Issue: NETCONF Connection Timeout

```bash
# Verify NETCONF is enabled
ssh admin@10.255.0.1
show system services netconf

# Enable if needed
request system netconf enable
```

### Issue: BGP Sessions Not Establishing

```bash
# Check BGP configuration
show configuration protocols bgp

# Check BFD status
show bfd session

# Check interface status
show interfaces et-0/0/44 detail

# Verify routing options
show configuration routing-options
```

### Issue: Ansible Authentication Fails

```bash
# Test direct SSH
ssh -p 830 admin@10.255.0.1

# Verify vault password
ansible-vault view inventory/group_vars/vault.yml

# Check ansible.cfg for correct settings
cat ansible.cfg
```

### Issue: Playbook Stops Mid-Deployment

```bash
# Check what was applied
ansible dc_fabric -m junos_command -a "commands='show configuration | display set | head 50'" --ask-vault-pass

# Resume from specific playbook
ansible-playbook playbooks/deploy_routing.yml --ask-vault-pass -v

# Or continue with next step
ansible-playbook playbooks/deploy_security.yml --ask-vault-pass
```

## Monitoring Post-Deployment

### Key Metrics to Monitor

1. **BGP Health**
   - All neighbors established
   - No session flaps
   - Route count stable

2. **Interface Health**
   - All P2P links up
   - No interface errors
   - BFD all green

3. **System Health**
   - CPU utilization < 50%
   - Memory utilization < 80%
   - No disk space warnings
   - Temperature normal

4. **SNMP/Syslog**
   - Traps received at collector
   - Syslog messages flowing
   - No critical errors

### Automated Monitoring

```bash
# Run validation every 6 hours
0 */6 * * * cd /ansible && ansible-playbook playbooks/validate_fabric.yml >> logs/validation.log

# Run configuration backup daily
0 2 * * * cd /ansible && ansible-playbook playbooks/backup_configs.yml >> logs/backup.log
```

## Maintenance Tasks

### Regular Backups

```bash
# Weekly full backup
ansible-playbook playbooks/backup_configs.yml --ask-vault-pass -t backup
```

### Configuration Updates

```bash
# For small changes, update host_vars and run specific playbook
vi inventory/host_vars/dc1-leaf-001.yml
ansible-playbook playbooks/deploy_interfaces.yml --ask-vault-pass

# For BGP policy changes
vi roles/routing/tasks/main.yml
ansible-playbook playbooks/deploy_routing.yml --ask-vault-pass
```

### Rolling Maintenance Window

```bash
# Update one device at a time
ansible-playbook playbooks/site.yml -l dc1-spine-01 --ask-vault-pass
ansible-playbook playbooks/validate_fabric.yml --ask-vault-pass
# Wait for convergence
sleep 300
# Continue with next device
```

## Deployment Timeline

| Phase | Duration | Notes |
|-------|----------|-------|
| Preparation | 2-4 hours | Vault setup, inventory update, validation |
| Base Config | 10-15 min | System settings, NTP, DNS, users |
| Interfaces | 10-15 min | Loopback, P2P, VLANs |
| Routing | 5-10 min | BGP/EVPN configuration |
| Security | 5 min | CoPP, firewalls, SSH hardening |
| Monitoring | 5 min | SNMP, syslog, telemetry |
| Validation | 30 min | Full health check, convergence |
| **Total** | **1-2 hours** | **Full fabric deployment** |

## Post-Deployment Handoff

1. Document all IP addresses and credentials in secure location
2. Provide access to configuration backups
3. Train operations team on monitoring and alerting
4. Establish change control process
5. Schedule quarterly reviews and updates
6. Plan firmware upgrade schedule

---

For issues or questions, refer to README.md and role-specific documentation.
