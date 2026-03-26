#!/usr/bin/env python3
"""
Juniper Leaf Configuration Generator

Generates complete Juniper configuration templates for leaf devices in a
spine-leaf EVPN-VXLAN fabric. Uses Jinja2 templates for flexibility.

Usage:
    python3 generate_leaf_configs.py --inventory inventory.yaml --template leaf-template.j2
    python3 generate_leaf_configs.py --inventory inventory.yaml --output configs/
"""

import argparse
import logging
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml
from jinja2 import Environment, FileSystemLoader, Template
from rich.console import Console
from rich.logging import RichHandler

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    handlers=[RichHandler(rich_tracebacks=True)]
)
logger = logging.getLogger("generate_leaf_configs")
console = Console()


class LeafConfigGenerator:
    """Generate Juniper leaf configurations."""

    # Default Jinja2 template for leaf configuration
    DEFAULT_TEMPLATE = """
{# Juniper Leaf Configuration Template #}
system {
    hostname {{ leaf.hostname }};
    ntp {
        server {{ ntp_servers | join('; server ') }};
    }
    syslog {
{% for host in syslog_hosts %}
        host {{ host }} {
            any any;
        }
{% endfor %}
    }
    domain-name {{ domain_name }};
    name-server {
{% for dns in dns_servers %}
        {{ dns }};
{% endfor %}
    }
    snmp {
{% for community in snmp_communities %}
        community {{ community.name }} {
            authorization {{ community.permission | default('read-only') }};
        }
{% endfor %}
    }
}

interfaces {
    lo0 {
        unit 0 {
            family inet {
                address {{ leaf.loopback_ip }}/32;
            }
        }
        unit 1 {
            family inet {
                address {{ leaf.vtep_ip }}/32;
            }
        }
    }

    me0 {
        unit 0 {
            family inet {
                address {{ leaf.management_ip }}/24;
            }
        }
    }
}

protocols {
    bgp {
        group SPINES {
            type external;
            local-address {{ leaf.loopback_ip }};
            family inet unicast;
            family evpn;
            multipath;
        }
    }

    evpn {
        encapsulation vxlan;
    }

    lldp {
        interface all;
    }
}
"""

    def __init__(self, template: Optional[str] = None):
        """Initialize configuration generator."""
        if template and Path(template).exists():
            self.jinja_env = Environment(
                loader=FileSystemLoader(str(Path(template).parent))
            )
            self.template = self.jinja_env.get_template(Path(template).name)
            logger.info(f"Loaded custom template from {template}")
        else:
            if template:
                logger.warning(f"Template file not found: {template}, using default")
            self.template = Template(self.DEFAULT_TEMPLATE)
            logger.info("Using default built-in template")

    def load_inventory(self, inventory_file: str) -> Optional[Dict[str, Any]]:
        """Load device inventory from YAML file."""
        try:
            inventory_path = Path(inventory_file)
            if not inventory_path.exists():
                logger.error(f"Inventory file not found: {inventory_file}")
                return None

            with open(inventory_path) as f:
                inventory = yaml.safe_load(f)

            leaves = [d for d in inventory.get("devices", []) if d.get("type") == "leaf"]
            logger.info(f"Loaded inventory with {len(leaves)} leaf devices")
            return inventory

        except Exception as e:
            logger.error(f"Failed to load inventory: {e}")
            return None

    def generate_leaf_config(
        self,
        leaf: Dict[str, Any],
        fabric_config: Dict[str, Any]
    ) -> str:
        """Generate configuration for a single leaf device."""
        try:
            context = {
                "leaf": leaf,
                "ntp_servers": fabric_config.get("ntp_servers", []),
                "syslog_hosts": fabric_config.get("syslog_hosts", []),
                "dns_servers": fabric_config.get("dns_servers", []),
                "domain_name": fabric_config.get("domain_name", "example.com"),
                "snmp_communities": fabric_config.get("snmp_communities", []),
                "spines": fabric_config.get("spines", []),
            }

            config = self.template.render(context)
            return config

        except Exception as e:
            logger.error(f"Failed to generate config for {leaf.get('hostname')}: {e}")
            raise

    def generate_all_configs(
        self,
        inventory: Dict[str, Any],
        output_dir: str = "leaf-configs"
    ) -> bool:
        """Generate configurations for all leaf devices."""
        try:
            output_path = Path(output_dir)
            output_path.mkdir(parents=True, exist_ok=True)

            fabric_config = inventory.get("fabric", {})
            spines = [d for d in inventory.get("devices", []) if d.get("type") == "spine"]
            leaves = [d for d in inventory.get("devices", []) if d.get("type") == "leaf"]

            fabric_config["spines"] = spines

            if not leaves:
                logger.warning("No leaf devices found in inventory")
                return False

            logger.info(f"Generating configurations for {len(leaves)} leaf devices")

            for leaf in leaves:
                try:
                    config = self.generate_leaf_config(leaf, fabric_config)
                    config_file = output_path / f"{leaf['hostname']}.conf"

                    with open(config_file, 'w') as f:
                        f.write(config)

                    file_size = config_file.stat().st_size
                    logger.info(f"Generated config for {leaf['hostname']} ({file_size} bytes)")

                except Exception as e:
                    logger.error(f"Failed to generate config for {leaf['hostname']}: {e}")
                    return False

            logger.info(f"All configurations generated to {output_dir}")
            return True

        except Exception as e:
            logger.error(f"Failed to generate configurations: {e}")
            return False


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Generate Juniper leaf configurations for spine-leaf fabric"
    )

    parser.add_argument(
        "--inventory",
        required=True,
        help="Inventory file (YAML format)"
    )
    parser.add_argument(
        "--template",
        help="Custom Jinja2 template file"
    )
    parser.add_argument(
        "--output",
        default="leaf-configs",
        help="Output directory for configurations (default: ./leaf-configs)"
    )
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        default="INFO",
        help="Logging level (default: INFO)"
    )

    args = parser.parse_args()

    logger.setLevel(getattr(logging, args.log_level))

    try:
        generator = LeafConfigGenerator(template=args.template)

        inventory = generator.load_inventory(args.inventory)
        if not inventory:
            sys.exit(1)

        success = generator.generate_all_configs(inventory, args.output)

        if success:
            console.print(f"[green]✓[/green] Configurations generated to [bold]{args.output}[/bold]")
            sys.exit(0)
        else:
            console.print("[red]✗[/red] Failed to generate configurations")
            sys.exit(1)

    except KeyboardInterrupt:
        logger.warning("Generation cancelled by user")
        sys.exit(130)
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
