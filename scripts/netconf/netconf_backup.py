#!/usr/bin/env python3
"""
NETCONF Configuration Backup Script

Backs up running configurations from Juniper devices via NETCONF.
Supports parallel execution and timestamped backup directories.

Usage:
    python3 netconf_backup.py --inventory inventory.yaml
    python3 netconf_backup.py --inventory inventory.yaml --output backups --parallel 4
"""

import argparse
import logging
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional

import yaml
from ncclient import manager
from rich.console import Console
from rich.logging import RichHandler
from rich.progress import Progress, BarColumn, TextColumn, TimeRemainingColumn

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    handlers=[RichHandler(rich_tracebacks=True)]
)
logger = logging.getLogger("netconf_backup")
console = Console()


class ConfigurationBackup:
    """NETCONF configuration backup handler."""

    def __init__(self, output_dir: str = "backups"):
        """
        Initialize backup handler.

        Args:
            output_dir: Directory for backup files
        """
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Create timestamped subdirectory
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.backup_dir = self.output_dir / f"backup_{timestamp}"
        self.backup_dir.mkdir(parents=True, exist_ok=True)

        self.results = {
            "timestamp": datetime.now().isoformat(),
            "backup_dir": str(self.backup_dir),
            "devices": {},
            "summary": {
                "total": 0,
                "successful": 0,
                "failed": 0,
            }
        }

    def backup_device(
        self,
        hostname: str,
        host: str,
        username: str,
        password: Optional[str] = None,
        sshkey: Optional[str] = None,
    ) -> bool:
        """
        Backup configuration from a single device.

        Args:
            hostname: Device hostname
            host: Device IP address
            username: Username for authentication
            password: Password (if not using SSH key)
            sshkey: Path to SSH private key

        Returns:
            True if backup successful, False otherwise
        """
        try:
            logger.debug(f"Connecting to {hostname} ({host})")

            # Connect to device
            if sshkey:
                session = manager.connect(
                    host=host,
                    port=830,
                    username=username,
                    key_filename=sshkey,
                    hostkey_verify=False,
                    timeout=30,
                )
            else:
                session = manager.connect(
                    host=host,
                    port=830,
                    username=username,
                    password=password,
                    hostkey_verify=False,
                    timeout=30,
                )

            logger.debug(f"Connected to {hostname}")

            # Get running configuration
            logger.debug(f"Retrieving configuration from {hostname}")
            reply = session.get(filter=("subtree", "<configuration/>"))

            if not reply.ok:
                logger.error(f"Failed to retrieve configuration from {hostname}")
                self.results["devices"][hostname] = {
                    "status": "FAILED",
                    "error": "Failed to retrieve configuration"
                }
                return False

            # Save configuration to file
            config_content = str(reply)
            config_file = self.backup_dir / f"{hostname}.xml"

            with open(config_file, 'w') as f:
                f.write(config_content)

            file_size = config_file.stat().st_size
            logger.info(f"Backed up {hostname} ({file_size} bytes)")

            self.results["devices"][hostname] = {
                "status": "SUCCESS",
                "file": str(config_file),
                "size_bytes": file_size,
            }

            session.close_session()
            return True

        except Exception as e:
            logger.error(f"Backup failed for {hostname}: {e}")
            self.results["devices"][hostname] = {
                "status": "FAILED",
                "error": str(e)
            }
            return False

    def backup_inventory(
        self,
        inventory_file: str,
        parallel: int = 4
    ) -> bool:
        """
        Backup configurations from all devices in inventory.

        Args:
            inventory_file: Path to inventory YAML file
            parallel: Number of parallel backup threads

        Returns:
            True if all backups successful, False otherwise
        """
        try:
            # Load inventory
            inventory_path = Path(inventory_file)
            if not inventory_path.exists():
                logger.error(f"Inventory file not found: {inventory_file}")
                return False

            with open(inventory_path) as f:
                inventory = yaml.safe_load(f)

            devices = inventory.get("devices", [])
            if not devices:
                logger.error("No devices found in inventory")
                return False

            logger.info(f"Backing up {len(devices)} devices to {self.backup_dir}")
            self.results["summary"]["total"] = len(devices)

            # Backup devices in parallel
            with ThreadPoolExecutor(max_workers=parallel) as executor:
                futures = {
                    executor.submit(
                        self.backup_device,
                        device["hostname"],
                        device["host"],
                        device.get("username", "admin"),
                        device.get("password"),
                        device.get("sshkey"),
                    ): device["hostname"]
                    for device in devices
                }

                with Progress(
                    TextColumn("[progress.description]{task.description}"),
                    BarColumn(),
                    TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
                    TimeRemainingColumn(),
                    console=console,
                ) as progress:
                    task = progress.add_task("Backing up devices...", total=len(futures))

                    for future in as_completed(futures):
                        hostname = futures[future]
                        try:
                            success = future.result()
                            if success:
                                self.results["summary"]["successful"] += 1
                            else:
                                self.results["summary"]["failed"] += 1
                        except Exception as e:
                            logger.error(f"Backup error for {hostname}: {e}")
                            self.results["devices"][hostname] = {
                                "status": "FAILED",
                                "error": str(e)
                            }
                            self.results["summary"]["failed"] += 1

                        progress.update(task, advance=1)

            # Generate summary report
            self._generate_summary()

            return self.results["summary"]["failed"] == 0

        except Exception as e:
            logger.error(f"Failed to backup inventory: {e}")
            return False

    def _generate_summary(self):
        """Generate and display backup summary."""
        summary = self.results["summary"]
        success_rate = (
            (summary["successful"] / summary["total"] * 100)
            if summary["total"] > 0 else 0
        )

        console.print(f"\n[bold]Backup Complete[/bold]")
        console.print(f"  [green]Successful:[/green] {summary['successful']}")
        console.print(f"  [red]Failed:[/red] {summary['failed']}")
        console.print(f"  [yellow]Success Rate:[/yellow] {success_rate:.1f}%")
        console.print(f"  [cyan]Backup Directory:[/cyan] {self.backup_dir}")

        # List backed up files
        backup_files = list(self.backup_dir.glob("*.xml"))
        if backup_files:
            console.print(f"\n[bold]Backed up files:[/bold]")
            for f in sorted(backup_files):
                size_kb = f.stat().st_size / 1024
                console.print(f"  - {f.name} ({size_kb:.1f} KB)")

    def save_report(self, report_file: Optional[str] = None):
        """
        Save backup report to file.

        Args:
            report_file: Path to output report file (JSON)
        """
        if not report_file:
            return

        try:
            import json
            report_path = Path(report_file)
            with open(report_path, 'w') as f:
                json.dump(self.results, f, indent=2)
            logger.info(f"Report saved to {report_file}")
        except Exception as e:
            logger.error(f"Failed to save report: {e}")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Backup configurations from Juniper devices via NETCONF",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Inventory file format (YAML):
  devices:
    - hostname: spine-1
      host: 10.0.0.1
      username: admin
      password: password123
    - hostname: leaf-1
      host: 10.0.1.1
      username: admin
      sshkey: /home/user/.ssh/id_rsa

Examples:
  # Basic backup
  %(prog)s --inventory inventory.yaml

  # Backup to custom directory with parallel execution
  %(prog)s --inventory inventory.yaml --output /backup/location --parallel 8

  # Save backup report
  %(prog)s --inventory inventory.yaml --report backup_report.json
        """
    )

    parser.add_argument(
        "--inventory",
        required=True,
        help="Inventory file (YAML format)"
    )
    parser.add_argument(
        "--output",
        default="backups",
        help="Output directory for backups (default: ./backups)"
    )
    parser.add_argument(
        "--parallel",
        type=int,
        default=4,
        help="Number of parallel backup threads (default: 4)"
    )
    parser.add_argument(
        "--report",
        help="Output report file (JSON)"
    )
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        default="INFO",
        help="Logging level (default: INFO)"
    )

    args = parser.parse_args()

    # Set logging level
    logger.setLevel(getattr(logging, args.log_level))

    # Create backup handler
    backup = ConfigurationBackup(output_dir=args.output)

    try:
        # Backup devices
        success = backup.backup_inventory(
            inventory_file=args.inventory,
            parallel=args.parallel
        )

        # Save report
        if args.report:
            backup.save_report(args.report)

        sys.exit(0 if success else 1)

    except KeyboardInterrupt:
        logger.warning("Backup cancelled by user")
        sys.exit(130)
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
