# IaC Tooling Guide — Ansible vs Terraform vs NETCONF

This project provides three automation approaches for managing the fabric. Each serves a different purpose and is suited to different operational scenarios. You can use one, two, or all three depending on your team's workflow.

## Tool Summary

| Tool | Purpose | Best For |
|------|---------|----------|
| **Ansible** | Configuration management and orchestration | Day-to-day operations, rolling deployments, validation |
| **Terraform** | Infrastructure state management | Provisioning, drift detection, lifecycle management |
| **NETCONF** | Direct device-level API access | Troubleshooting, one-off changes, custom scripting |

## Ansible

Ansible is the primary operational tool in this project. It handles configuration generation from Jinja2 templates, staged deployment across all 64 devices, and fabric validation.

**What it does:** Pushes JunOS configuration to devices over NETCONF (via the `junipernetworks.junos` collection), manages deployment ordering (base → interfaces → routing → security → monitoring), runs health checks, and handles backups.

**When to use it:**
- Full fabric deployment (Day 0): `ansible-playbook playbooks/site.yml`
- Staged rollouts with dry-run: `ansible-playbook playbooks/deploy_routing.yml --check`
- Rolling config updates across all leaves or spines
- Validating BGP sessions, BFD, and EVPN state post-change
- Backing up device configs: `ansible-playbook playbooks/backup_configs.yml`
- Firmware upgrades: `ansible-playbook playbooks/upgrade_firmware.yml`

**Key files:**
- `ansible/playbooks/site.yml` — master playbook that runs all roles in order
- `ansible/inventory/hosts.yml` — device inventory with management IPs
- `ansible/inventory/group_vars/` — shared variables (ASNs, subnets, NTP, etc.)
- `ansible/roles/` — modular roles for base, interfaces, routing, security, monitoring

## Terraform

Terraform manages the fabric as declared infrastructure state. It tracks what has been deployed and can detect configuration drift — useful for compliance and auditing.

**What it does:** Declares each spine and leaf as a Terraform resource using the Junos provider, manages the dependency graph between devices, and maintains a state file recording the deployed configuration.

**When to use it:**
- Initial provisioning when you want a state file to track what's deployed
- Drift detection: `terraform plan` will show any manual changes made outside of IaC
- Environments that require Terraform for compliance or audit trail
- Teams already using Terraform for other infrastructure (cloud, DNS, etc.)
- Destroying or decommissioning devices cleanly

**Key files:**
- `terraform/environments/production/main.tf` — production fabric definition
- `terraform/modules/junos_device/` — reusable module for individual device config
- `terraform/modules/network_fabric/` — module that composes the full fabric
- `terraform/environments/production/terraform.tfvars` — environment-specific values

**Note:** Ansible and Terraform can coexist. A common pattern is to use Terraform for initial provisioning and state tracking, then Ansible for ongoing operational changes and validation.

## NETCONF (Python Scripts)

The NETCONF scripts provide direct programmatic access to individual devices using the `ncclient` library. They bypass the orchestration layer and talk to devices one at a time.

**What it does:** Pushes configuration, retrieves operational state, runs validation checks, and creates backups — all via the NETCONF XML API over SSH (port 830).

**When to use it:**
- Troubleshooting a single device without running a full playbook
- Pulling operational state (BGP neighbors, interface counters, EVPN routes)
- Custom automation scripts that need raw NETCONF XML access
- Emergency config pushes when Ansible inventory isn't available
- Integration with external systems (ticketing, CMDB, CI/CD pipelines)

**Key files:**
- `scripts/netconf/netconf_config_push.py` — push a config file to a device
- `scripts/netconf/netconf_validate.py` — validate device config and state
- `scripts/netconf/netconf_backup.py` — backup running config
- `scripts/netconf/netconf_get_state.py` — retrieve operational data

## Choosing the Right Tool

| Scenario | Recommended Tool |
|----------|-----------------|
| Deploy full fabric from scratch | Ansible (`site.yml`) |
| Add a new rack (2 leaves) | Ansible (add to inventory, run `site.yml --limit`) |
| Check if configs have drifted | Terraform (`terraform plan`) |
| Debug a single BGP session | NETCONF (`netconf_get_state.py`) |
| Emergency fix on one device | NETCONF (`netconf_config_push.py`) |
| Nightly config backup | Ansible (`backup_configs.yml`) |
| Audit deployed state for compliance | Terraform (state file + `terraform show`) |
| Rolling firmware upgrade | Ansible (`upgrade_firmware.yml`) |
| CI/CD pipeline integration | NETCONF scripts or Ansible (depending on runner) |
