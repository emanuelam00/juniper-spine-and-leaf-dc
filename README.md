# Datacenter Network Design

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/emanuelam00/juniper-spine-and-leaf-dc)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![JunOS Version](https://img.shields.io/badge/JunOS-20.4%2B-orange)](docs/ARCHITECTURE.md)
[![Terraform](https://img.shields.io/badge/Terraform-1.0%2B-purple)](https://www.terraform.io/)
[![Ansible](https://img.shields.io/badge/Ansible-2.10%2B-red)](https://www.ansible.com/)

## Project Overview

A complete, production-ready datacenter network fabric design and automation framework built on Juniper spine-leaf architecture with EVPN-VXLAN overlay networking. This project provides a comprehensive infrastructure-as-code approach to deploying, managing, and monitoring a modern data center fabric with 64 total switches supporting 30 racks of compute infrastructure.

### Design Goals

- **Scalability**: Support 30 racks with 2 leaf switches per rack (60 total leaves)
- **High Performance**: 100G+ uplinks with low-latency, non-blocking fabric
- **High Availability**: Active-active redundancy, multi-path forwarding, NSF/NSSA support
- **Automation**: Infrastructure-as-Code with Ansible, Terraform, and NETCONF
- **Observability**: Comprehensive monitoring with Prometheus, Grafana, and Telegraf
- **Security**: Firewall integration, segmentation, and encrypted management

## Architecture Overview

### Core Design

```
                    ┌─────────────────────────────────────────┐
                    │     FortiGate Firewall (Active-Active)  │
                    │  ┌─────────────┬─────────────┐          │
                    │  │  FW-01      │    FW-02   │          │
                    │  └──────┬──────┴──────┬──────┘          │
                    └─────────┼─────────────┼─────────────────┘
                              │ 100G       │ 100G
                    ┌─────────┴─────────────┴──────────────────┐
                    │        SPINE LAYER (4 devices)           │
                    │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐ │
                    │  │spine │  │spine │  │spine │  │spine │ │
                    │  │ 01   │  │ 02   │  │ 03   │  │ 04   │ │
                    │  │QFX52 │  │QFX52 │  │QFX52 │  │QFX52 │ │
                    │  └──────┘  └──────┘  └──────┘  └──────┘ │
                    └──┬───┬───┬───┬───┬───┬───┬───┬───┬───┬──┘
                  100G │ 100G 100G │ 100G 100G │ 100G 100G │
              ┌────────┼────┬──────┼─────┬──────┼────┬───────┘
              │        │    │      │     │      │    │
        ┌─────┴──┬─────┴──┬─┴──────┴─────┴──┬───┴────┴──────┐
        │        │        │        │        │        │       │
    ┌───┴───┐┌───┴───┐┌───┴───┐ ┌─┴─────┐┌──┴──────┐┌─────┐│
    │Rack 1 ││Rack 2 ││Rack 3 │ │ ...   ││Rack 29  ││Rack ││
    │       ││       ││       │ │       ││         ││ 30  ││
    │Leaf01 ││Leaf03 ││Leaf05 │ │ ...   ││Leaf57   ││Leaf ││
    │Leaf02 ││Leaf04 ││Leaf06 │ │       ││Leaf58   ││59/60││
    │       ││       ││       │ │       ││         ││     ││
    └───┬───┘└───┬───┘└───┬───┘ └─┬─────┘└──┬──────┘└─────┘│
        │ ESI-LAG│        │ ESI-LA│        ESI-LAG   │
        │        │        │       │                 │
    ┌───┴───────┴┬───────┴───────┴────┬─────────────┴──┐
    │   Server   │   Server   Server   │   Server       │
    │   Server   │   Server   Server   │   Server       │
    └────────────┴────────────────────┴────────────────┘
```

### Technology Stack

| Component | Technology | Details |
|-----------|-----------|---------|
| **Underlay** | eBGP IP Fabric | Spine ASN: 65000, Leaf ASNs: 65001-65060 |
| **Overlay** | EVPN-VXLAN | Symmetric IRB with ARP suppression |
| **Redundancy** | ESI-LAG | Dual-homed servers at 25G per link |
| **Fabric Links** | 100G | QFX5220-32CD and QFX5120-48Y |
| **Security** | Firewalls | FortiGate active-active north of spines |
| **Automation** | Ansible + Terraform | IaC for configuration management |
| **Monitoring** | Prometheus + Grafana | Real-time telemetry and visualization |

## Hardware Bill of Materials

| Device | Model | Quantity | Ports | Uplinks | Purpose |
|--------|-------|----------|-------|---------|---------|
| Spine Switches | Juniper QFX5220-32CD | 4 | 32x 400G QSFP-DD | N/A | Core fabric |
| Leaf Switches | Juniper QFX5120-48Y | 60 | 48x 25G SFP28 | 2x 100G | Access layer (30 racks × 2) |
| Firewalls | Fortinet FortiGate 4200F | 2 | 4x 100G | Multiple | North-bound security |
| Servers | Dual-socket x86 | 600+ | 2x 25G ESI-LAG | N/A | Compute nodes |

### Network Bandwidth Summary

- **Spine-to-Spine**: 1.2 Tbps (fully meshed, 100G per link)
- **Spine-to-Leaf**: 2.4 Tbps (4 spines × 60 leaves × 100G)
- **Leaf-to-Server**: 1.5 Tbps (60 leaves × 48 × 25G)
- **North-bound**: 400 Gbps (2 FW × 2 × 100G)

## Quick Start Guide

### Prerequisites

Before deploying this fabric, ensure you have:

- **Ansible**: 2.10 or later
  ```bash
  pip install ansible jinja2 netaddr
  ```

- **Terraform**: 1.0 or later
  ```bash
  curl https://releases.hashicorp.com/terraform/1.0.0/terraform_1.0.0_linux_amd64.zip -o terraform.zip
  unzip terraform.zip && sudo mv terraform /usr/local/bin/
  ```

- **Python Libraries**:
  ```bash
  pip install pyyaml requests junos-eznc jxmlease
  ```

- **Network Access**: SSH access to all devices with appropriate credentials
- **Juniper Devices**: Running JunOS 20.4 or later
- **DNS/NTP**: Configured on all devices for synchronization

### Repository Setup

1. **Clone the repository**:
   ```bash
   git clone git@github.com:emanuelam00/juniper-spine-and-leaf-dc.git
   cd juniper-spine-and-leaf-dc
   ```

2. **Configure credentials**:
   ```bash
   cp ansible/inventory/credentials.example.yml ansible/inventory/credentials.yml
   # Edit credentials.yml with your device credentials
   chmod 600 ansible/inventory/credentials.yml
   ```

3. **Update inventory**:
   ```bash
   # Edit ansible/inventory/hosts.yml with your actual device IPs and hostnames
   vim ansible/inventory/hosts.yml
   ```

### Deployment Methods

#### Option 1: Ansible-Based Deployment (Recommended)

Deploy the entire fabric using Ansible playbooks:

```bash
# Validate syntax and connectivity
ansible-playbook ansible/playbooks/validate_fabric.yml

# Deploy baseline configuration to all devices
ansible-playbook ansible/playbooks/deploy_base.yml

# Configure underlay and overlay (eBGP + EVPN-VXLAN)
ansible-playbook ansible/playbooks/deploy_routing.yml

# Enable monitoring and operational features
ansible-playbook ansible/playbooks/deploy_monitoring.yml

# Configure firewalls and security policies
ansible-playbook ansible/playbooks/deploy_security.yml

# Run full deployment (all steps)
ansible-playbook ansible/playbooks/site.yml
```

#### Option 2: Terraform-Based Deployment

Deploy infrastructure resources and configurations via Terraform:

```bash
# Initialize Terraform environment
cd terraform/environments/production
terraform init

# Plan deployment
terraform plan -out=tfplan

# Apply configuration
terraform apply tfplan

# Verify deployment
terraform output
```

#### Option 3: NETCONF-Based Manual Deployment

For manual or targeted deployments using NETCONF scripts:

```bash
# Deploy to specific spine
python scripts/netconf/netconf_config_push.py \
  --device spine-01 \
  --config configs/spine/dc1-spine-01.conf

# Deploy all leaves in a rack
for i in {01..30}; do
  python scripts/netconf/netconf_config_push.py \
    --device leaf-$(printf "%03d" $i) \
    --config configs/leaf/dc1-leaf-$(printf "%03d" $i).conf
done
```

## IP Addressing Scheme

### Management Network

| Component | Subnet | Details |
|-----------|--------|---------|
| Spine Devices | 10.0.1.0/24 | spine-01: 10.0.1.1, spine-02: 10.0.1.2, etc. |
| Leaf Devices | 10.0.2.0/25 (odd) + 10.0.2.128/25 (even) | leaf-01-spine: 10.0.2.1, leaf-02-spine: 10.0.2.129, etc. |
| Firewalls | 10.0.0.0/24 | fw-01: 10.0.0.1, fw-02: 10.0.0.2 |
| Out-of-Band | 10.50.0.0/16 | Dedicated OOB network for management |

### Underlay (IP Fabric) - eBGP

| Layer | Subnet Range | Details |
|-------|-------------|---------|
| Spine-Spine Links | 192.168.0.0/18 | Point-to-point /31 networks |
| Spine-Leaf Links | 192.168.64.0/18 | Point-to-point /31 networks |
| Loopback (Spine) | 10.0.0.0/25 | spine-01: 10.0.0.1/32, spine-02: 10.0.0.2/32, etc. |
| Loopback (Leaf) | 10.0.1.0/25 | leaf-01: 10.0.1.1/32, leaf-02: 10.0.1.2/32, etc. |

### Overlay (EVPN-VXLAN) - Symmetric IRB

| VLAN | VNI | Subnet | Gateway | Purpose |
|------|-----|--------|---------|---------|
| 100 | 10100 | 172.16.100.0/24 | 172.16.100.1 | Rack-1 Compute |
| 101 | 10101 | 172.16.101.0/24 | 172.16.101.1 | Rack-2 Compute |
| 200 | 20000 | 172.16.200.0/23 | 172.16.200.1 | DMZ/Frontend |
| 300 | 30000 | 172.16.0.0/22 | 172.16.0.1 | Storage |
| 999 | 9999 | 10.255.0.0/24 | 10.255.0.1 | Management |

## Configuration Management

### Directory Structure for Configs

```
configs/
├── spine/
│   ├── dc1-spine-01.conf
│   ├── dc1-spine-02.conf
│   ├── dc1-spine-03.conf
│   └── dc1-spine-04.conf
├── leaf/
│   ├── dc1-leaf-001.conf
│   ├── dc1-leaf-002.conf
│   ├── ...
│   └── dc1-leaf-060.conf
└── templates/
    ├── spine.conf.j2
    └── leaf.conf.j2
```

### Modifying Configurations

1. **Template-Based Generation**:
   All device configurations are generated from Jinja2 templates using variables defined in `ansible/inventory/group_vars/` and device-specific `host_vars/`.

2. **Adding New Devices**:
   ```bash
   # Add new device to inventory
   vim ansible/inventory/hosts.yml
   # Add host_vars file with device-specific settings
   vim ansible/inventory/host_vars/leaf-05.yml
   ```

3. **Template Variables**:
   Edit `ansible/inventory/group_vars/` for:
   - eBGP ASN assignments
   - MTU sizes
   - Routing policies
   - VLAN/VNI mappings

   Edit `ansible/inventory/host_vars/{hostname}.yml` for device-specific settings.

4. **Deploying to New Device**:
   ```bash
   # Deploy configuration to newly added device
   ansible-playbook ansible/playbooks/site.yml --limit leaf-05

   # Validate changes in check mode first
   ansible-playbook ansible/playbooks/site.yml --limit leaf-05 --check
   ```

## Automation Workflows

### Day 0: Initial Fabric Deployment

Fresh datacenter deployment from ground zero:

```bash
# 1. Validate all devices are reachable
ansible-playbook ansible/playbooks/validate_fabric.yml

# 2. Deploy complete fabric configuration
ansible-playbook ansible/playbooks/site.yml

# 3. Run comprehensive health checks
ansible-playbook ansible/playbooks/validate_fabric.yml
```

**Timeline**: ~2-4 hours for full fabric deployment

### Day 1: Adding New Racks/Leaves

Scaling fabric by adding new leaf pairs:

```bash
# 1. Add new devices to inventory
vim ansible/inventory/hosts.yml
# Add leaf-61 and leaf-62 entries

# 2. Create host_vars for new leaves
vim ansible/inventory/host_vars/leaf-61.yml
vim ansible/inventory/host_vars/leaf-62.yml

# 3. Deploy to new leaves
ansible-playbook ansible/playbooks/site.yml --limit new_leaves

# 4. Validate connectivity
ansible-playbook ansible/playbooks/validate_fabric.yml --limit new_leaves
```

**Timeline**: ~30 minutes per new rack pair

### Day 2+: Monitoring and Operations

Ongoing operations and troubleshooting:

```bash
# Validate fabric health
ansible-playbook ansible/playbooks/validate_fabric.yml

# Backup all device configurations
ansible-playbook ansible/playbooks/backup_configs.yml

# Update configurations with check mode first
ansible-playbook ansible/playbooks/site.yml --check
ansible-playbook ansible/playbooks/site.yml
```

## Security Overview

This project implements multiple layers of security:

- **Management Plane**: SSH with key authentication, disabled root login
- **Control Plane**: eBGP MD5 authentication, encrypted NETCONF communication
- **Data Plane**: ACLs for micro-segmentation, firewall integration
- **Access Control**: Role-based access control via Ansible vault, device credentials encrypted
- **Monitoring**: Encrypted telemetry transport, authentication for Prometheus/Grafana

For detailed security architecture, threat model, and compliance information, see [docs/SECURITY.md](docs/SECURITY.md).

## Monitoring and Observability

Comprehensive monitoring stack for fabric visibility:

- **Telegraf Agents**: Installed on all devices for metrics collection
- **Prometheus**: Time-series database for metrics (10-second scrape interval)
- **Grafana**: Visualization dashboards for fabric health, BGP status, link utilization
- **Alerting**: AlertManager integration for critical events

Key dashboards:
- Fabric Health Overview
- BGP Peer Status
- EVPN Route Convergence
- Link Utilization and Errors
- Device Temperature and System Health

For detailed monitoring architecture, custom dashboards, and alerting rules, see [docs/MONITORING.md](docs/MONITORING.md).

## Testing and Validation

### Fabric Health Checks

Comprehensive validation suite to verify fabric correctness:

```bash
# Full health check suite
ansible-playbook ansible/playbooks/validate_fabric.yml
```

This playbook verifies:
- All spine-spine BGP sessions: Established
- All spine-leaf BGP sessions: Established
- Type-2 (MAC-IP) EVPN routes from all leaves
- Type-5 (IP prefix) EVPN routes from IRB interfaces
- VXLAN tunnel establishment
- Interface status and link utilization

### Dry-Run Validation

Test configuration changes before applying:

```bash
# Validate syntax and run in check mode
ansible-playbook ansible/playbooks/site.yml --check

# Review what would change without executing
ansible-playbook ansible/playbooks/validate_fabric.yml --check
```

### BGP Verification

For detailed BGP validation, check the BGP validation tasks:

```bash
# BGP validation is included in validate_fabric.yml
# Manual check: ansible inventory/tasks/validate_bgp.yml
```

## Troubleshooting

Common issues and resolution steps:

| Issue | Symptoms | Root Cause | Solution |
|-------|----------|-----------|----------|
| BGP Neighbors Down | "show bgp summary" shows inactive | Interface misconfiguration or IP mismatch | Verify /31 IPs match peer config, check MTU |
| VXLAN Tunnel Flap | Frequent tunnel state changes | Loopback reachability issue | Verify loopback IPs are advertised in BGP |
| EVPN Routes Missing | Routes not distributed to other leaves | ESI-LAG or RD misconfiguration | Check ESI values match across leaf pair, verify import/export policies |
| Link Errors | High packet loss on specific link | Cable or transceiver issue | Reseat optic, swap transceiver, check signal levels |
| Configuration Sync | Configs out of sync between leaf pairs | Playbook failure on one device | Re-run playbook with target device, verify idempotency |
| Ansible Connection Timeout | SSH Error: timed out during banner exchange | Device unreachable or SSH service issue | Verify reachability (ping), check SSH port (default 22), review device logs |
| Terraform State Corruption | Error reading backend config | Local state file issue | Use `terraform state show` to inspect, rebuild if necessary |

## Project Structure Details

### `/ansible/` - Ansible Automation

- `inventory/`: Device inventory, credentials, and variable definitions
- `playbooks/`: Main orchestration playbooks for deployment and validation
- `roles/`: Reusable Ansible roles for configuration modules
- `ansible.cfg`: Global Ansible configuration settings

### `/terraform/` - Infrastructure as Code

- `modules/`: Reusable Terraform modules for device types
- `environments/`: Environment-specific configurations (production, staging)
- `main.tf`, `variables.tf`, `outputs.tf`: Core Terraform definitions

### `/scripts/` - Utility Scripts

- `netconf/`: Direct NETCONF-based deployment scripts
- `utilities/`: Helper scripts for backup, reporting, etc.

### `/monitoring/` - Observability Configuration

- `prometheus/`: Scrape configs and alert rules
- `grafana/`: Dashboard definitions and provisioning
- `telegraf/`: Agent configurations for metric collection

### `/docs/` - Documentation

- `ARCHITECTURE.md`: Detailed architecture specifications
- `SECURITY.md`: Security design and controls
- `MONITORING.md`: Monitoring architecture and dashboards

### `/diagrams/` - Visual Documentation

Excalidraw diagrams (.excalidraw format, open at excalidraw.com) for network topology, routing design, addressing scheme, and traffic flow.

## Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/my-enhancement`
3. **Test** all changes locally in a non-production environment
4. **Document** changes in commit messages and update README as needed
5. **Submit** a pull request with detailed description of changes

### Code Style

- YAML: 2-space indentation, follow Ansible best practices
- Terraform: Use `terraform fmt` for consistency
- Python: Follow PEP 8, use type hints where applicable
- Jinja2 Templates: Use consistent naming conventions

### Testing Requirements

Before submitting a PR:
- Validate Ansible syntax: `ansible-playbook --syntax-check`
- Validate Terraform: `terraform validate`
- Run playbooks in `--check` mode
- Verify no secrets in committed code

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) file for details.

## Acknowledgments

- **Juniper Networks**: For QFX switching platform and EVPN-VXLAN support
- **Fortinet**: For FortiGate firewall solutions
- **Ansible Community**: For excellent automation tooling
- **HashiCorp**: For Terraform infrastructure-as-code framework
- **Prometheus & Grafana Communities**: For monitoring stack excellence

## Support and Contact

For issues, questions, or suggestions:

- **GitHub Issues**: [Create an issue](https://github.com/emanuelam00/juniper-spine-and-leaf-dc/issues)
- **Documentation**: See `/docs/` directory for detailed guides
- **Email**: emanuel.aminov@gmail.com

---

**Last Updated**: March 2026
**Fabric Generation**: v2.1
**Supported JunOS Versions**: 20.4, 21.1, 21.2, 21.3, 22.1+
