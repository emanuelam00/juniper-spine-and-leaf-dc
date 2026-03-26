# Quick Start Guide

Get the Juniper spine-leaf datacenter fabric up and running in under an hour.

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Ansible | 2.10+ | `pip install ansible jinja2 netaddr` |
| Terraform | 1.0+ | [terraform.io/downloads](https://www.terraform.io/downloads) |
| Python | 3.8+ | `pip install pyyaml junos-eznc jxmlease ncclient` |
| Docker & Compose | 20.10+ | Required for monitoring stack only |

All Juniper devices must be running JunOS 20.4+ with SSH and NETCONF enabled. You need OOB management access to every device on the 10.255.0.0/24 network.

## 1. Clone and Configure

```bash
git clone git@github.com:emanuelam00/juniper-spine-and-leaf-dc.git
cd juniper-spine-and-leaf-dc
```

### Update credentials

Replace placeholder values in the config files before deployment:

```
Root password:  $6$PLACEHOLDER  → your SHA512 hash
BGP auth-keys:  $9$PLACEHOLDER  → Juniper-style encrypted keys
SNMP keys:      $9$PLACEHOLDER  → SNMPv3 auth/privacy passphrases
```

### Update inventory

Edit `ansible/inventory/hosts.yml` with your actual device management IPs. The default inventory uses 10.255.0.1-4 for spines and 10.255.1.1-60 for leaves.

## 2. Deploy with Ansible (Recommended)

The fastest path to a working fabric:

```bash
cd ansible

# Install required Ansible collections
ansible-galaxy install -r requirements.yml

# Verify all devices are reachable
ansible-playbook playbooks/validate_fabric.yml

# Deploy everything (base → interfaces → routing → security → monitoring)
ansible-playbook playbooks/site.yml
```

Or deploy in stages for more control:

```bash
# Step 1: Base config (hostname, NTP, syslog, users)
ansible-playbook playbooks/deploy_base.yml

# Step 2: Interfaces (et- ports, MTU, storm control)
ansible-playbook playbooks/deploy_interfaces.yml

# Step 3: Routing (eBGP underlay + EVPN overlay)
ansible-playbook playbooks/deploy_routing.yml

# Step 4: Security hardening (ACLs, firewall filters, SSH)
ansible-playbook playbooks/deploy_security.yml

# Step 5: Monitoring (SNMP, syslog, telemetry)
ansible-playbook playbooks/deploy_monitoring.yml
```

Use `--check` on any playbook for a dry run: `ansible-playbook playbooks/site.yml --check`

## 3. Deploy with Terraform (Alternative)

```bash
cd terraform/environments/production

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## 4. Deploy with NETCONF (Manual / Per-Device)

For targeted deployments or troubleshooting:

```bash
# Push config to a specific spine
python scripts/netconf/netconf_config_push.py \
  --host 10.255.0.1 \
  --config configs/spine/dc1-spine-01.conf

# Validate a device
python scripts/netconf/netconf_validate.py \
  --host 10.255.0.1

# Backup current config
python scripts/netconf/netconf_backup.py \
  --host 10.255.0.1
```

## 5. Start the Monitoring Stack

```bash
cd monitoring
docker-compose up -d
```

This launches Prometheus, Grafana, Telegraf, Alertmanager, Loki, and supporting services. Access Grafana at `http://<monitoring-host>:3000`.

## 6. Verify the Fabric

After deployment, validate everything is healthy:

```bash
# Run the full validation suite
ansible-playbook ansible/playbooks/validate_fabric.yml

# Or check manually on any spine/leaf:
ssh netadmin@10.255.0.1

show bgp summary                  # All 60 leaf + 2 FW sessions Established
show evpn database                # EVPN routes from all leaves
show bfd session                  # BFD sessions up, 300ms interval
show interfaces et-0/0/0 terse    # All fabric links up
show route summary                # Route count matches expected
```

### What "healthy" looks like

| Check | Expected |
|-------|----------|
| BGP sessions per spine | 62 Established (60 leaves + 2 firewalls) |
| EVPN routes per spine | 60 RR clients active |
| BFD sessions per spine | 62 Up |
| ECMP paths | 4-way per destination prefix |
| Fabric link speed | 100G (et- interfaces) |
| Server link speed | 25G (et- interfaces, ESI-LAG) |

## Common Issues

**BGP sessions stuck in Active**: Check that P2P /31 IPs match on both ends. Verify the interface is `et-` (not `xe-` or `ge-`) and link is physically up.

**EVPN routes not propagating**: Confirm the leaf's loopback is reachable via the underlay. Check that spines are configured as Route Reflectors with the leaf as an RR client.

**ESI-LAG not forming**: Both leaves in a rack must share the same ESI value. Verify LACP is configured on both the leaf pair and the server NIC.

**Monitoring not scraping**: Ensure SNMPv3 credentials in `monitoring/telegraf/telegraf.conf` match the device config. Check Docker container logs with `docker-compose logs telegraf`.

## Next Steps

- Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full design details
- Read [docs/SECURITY.md](docs/SECURITY.md) for security controls and hardening
- Read [docs/MONITORING.md](docs/MONITORING.md) for alerting rules and dashboards
- Open diagrams in [excalidraw.com](https://excalidraw.com) from the `diagrams/` folder
- Add host_vars for additional leaves and re-run `site.yml` to scale the fabric
