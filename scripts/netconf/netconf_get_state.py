#!/usr/bin/env python3
"""
NETCONF Operational State Retrieval Script

Retrieves operational state from Juniper devices via NETCONF get RPC.
Supports BGP status, interface status, LLDP neighbors, and system information.

Usage:
    python3 netconf_get_state.py --host 10.0.0.1 --bgp
    python3 netconf_get_state.py --host 10.0.1.1 --interfaces --lldp --json
"""

import argparse
import json
import logging
import sys
from typing import Any, Dict, Optional

from lxml import etree
from ncclient import manager
from ncclient.operations.errors import OperationError
from rich.console import Console
from rich.logging import RichHandler
from rich.table import Table

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    handlers=[RichHandler(rich_tracebacks=True)]
)
logger = logging.getLogger("netconf_get_state")
console = Console()


class NetconfStateRetriever:
    """NETCONF operational state retrieval handler for Juniper devices."""

    def __init__(
        self,
        host: str,
        username: str,
        password: Optional[str] = None,
        sshkey: Optional[str] = None,
        port: int = 830,
        timeout: int = 30,
    ):
        """
        Initialize NETCONF connection parameters.

        Args:
            host: Device IP address or hostname
            username: Username for authentication
            password: Password for authentication (if not using SSH key)
            sshkey: Path to SSH private key file
            port: NETCONF SSH port (default 830)
            timeout: Connection timeout in seconds (default 30)
        """
        self.host = host
        self.username = username
        self.password = password
        self.sshkey = sshkey
        self.port = port
        self.timeout = timeout
        self.session = None

    def connect(self) -> bool:
        """
        Establish NETCONF session to device.

        Returns:
            True if connection successful, False otherwise
        """
        try:
            logger.info(f"Connecting to {self.host}:{self.port}...")

            if self.sshkey:
                self.session = manager.connect(
                    host=self.host,
                    port=self.port,
                    username=self.username,
                    key_filename=self.sshkey,
                    hostkey_verify=False,
                    timeout=self.timeout,
                )
            else:
                self.session = manager.connect(
                    host=self.host,
                    port=self.port,
                    username=self.username,
                    password=self.password,
                    hostkey_verify=False,
                    timeout=self.timeout,
                )

            logger.info(f"Successfully connected to {self.host}")
            return True

        except Exception as e:
            logger.error(f"Connection failed: {e}")
            return False

    def disconnect(self):
        """Close NETCONF session."""
        if self.session:
            try:
                self.session.close_session()
                logger.info(f"Disconnected from {self.host}")
            except Exception as e:
                logger.warning(f"Error during disconnect: {e}")
            self.session = None

    def get_system_info(self) -> Optional[Dict[str, Any]]:
        """
        Get system information (hostname, version, serial number, etc).

        Returns:
            Dictionary with system information or None on error
        """
        try:
            logger.info("Retrieving system information...")
            reply = self.session.get(filter=("subtree", "<system/>"))

            if not reply.ok:
                logger.error(f"Failed to retrieve system info: {reply}")
                return None

            data = etree.fromstring(str(reply).encode())
            return self._parse_system_info(data)

        except Exception as e:
            logger.error(f"Error retrieving system info: {e}")
            return None

    def get_bgp_status(self) -> Optional[Dict[str, Any]]:
        """
        Get BGP neighbor status and statistics.

        Returns:
            Dictionary with BGP information or None on error
        """
        try:
            logger.info("Retrieving BGP status...")
            filter_xml = """
            <bgp-information>
                <bgp-group/>
            </bgp-information>
            """
            reply = self.session.get(filter=("subtree", filter_xml))

            if not reply.ok:
                logger.error(f"Failed to retrieve BGP status: {reply}")
                return None

            data = etree.fromstring(str(reply).encode())
            return self._parse_bgp_status(data)

        except Exception as e:
            logger.error(f"Error retrieving BGP status: {e}")
            return None

    def get_interface_status(self) -> Optional[Dict[str, Any]]:
        """
        Get physical and logical interface status.

        Returns:
            Dictionary with interface information or None on error
        """
        try:
            logger.info("Retrieving interface status...")
            filter_xml = """
            <interface-information>
                <physical-interface/>
            </interface-information>
            """
            reply = self.session.get(filter=("subtree", filter_xml))

            if not reply.ok:
                logger.error(f"Failed to retrieve interface status: {reply}")
                return None

            data = etree.fromstring(str(reply).encode())
            return self._parse_interface_status(data)

        except Exception as e:
            logger.error(f"Error retrieving interface status: {e}")
            return None

    def get_lldp_neighbors(self) -> Optional[Dict[str, Any]]:
        """
        Get LLDP neighbor information.

        Returns:
            Dictionary with LLDP neighbors or None on error
        """
        try:
            logger.info("Retrieving LLDP neighbors...")
            filter_xml = """
            <lldp-neighbors-information>
                <lldp-neighbor-information/>
            </lldp-neighbors-information>
            """
            reply = self.session.get(filter=("subtree", filter_xml))

            if not reply.ok:
                logger.error(f"Failed to retrieve LLDP neighbors: {reply}")
                return None

            data = etree.fromstring(str(reply).encode())
            return self._parse_lldp_neighbors(data)

        except Exception as e:
            logger.error(f"Error retrieving LLDP neighbors: {e}")
            return None

    def get_routing_table(self) -> Optional[Dict[str, Any]]:
        """
        Get routing table information.

        Returns:
            Dictionary with routing information or None on error
        """
        try:
            logger.info("Retrieving routing table...")
            filter_xml = """
            <route-information>
                <route-table/>
            </route-information>
            """
            reply = self.session.get(filter=("subtree", filter_xml))

            if not reply.ok:
                logger.error(f"Failed to retrieve routing table: {reply}")
                return None

            data = etree.fromstring(str(reply).encode())
            return self._parse_routing_table(data)

        except Exception as e:
            logger.error(f"Error retrieving routing table: {e}")
            return None

    @staticmethod
    def _parse_system_info(data: etree._Element) -> Dict[str, Any]:
        """Parse system information from XML."""
        info = {}
        try:
            for elem in data.iter():
                if elem.tag == "host-name":
                    info["hostname"] = elem.text
                elif elem.tag == "serial-number":
                    info["serial_number"] = elem.text
                elif elem.tag == "model":
                    info["model"] = elem.text
                elif elem.tag == "os-name":
                    info["os_name"] = elem.text
                elif elem.tag == "os-version":
                    info["os_version"] = elem.text
                elif elem.tag == "uptime-information":
                    info["uptime"] = elem.text
        except Exception as e:
            logger.warning(f"Error parsing system info: {e}")
        return info

    @staticmethod
    def _parse_bgp_status(data: etree._Element) -> Dict[str, Any]:
        """Parse BGP status from XML."""
        bgp_info = {
            "groups": [],
            "neighbors": []
        }
        try:
            for group in data.findall(".//bgp-group"):
                group_name = group.findtext("name", "unknown")
                for peer in group.findall("peer-as-list/peers"):
                    peer_data = {
                        "group": group_name,
                        "ip_address": peer.findtext("peer-address", "N/A"),
                        "asn": peer.findtext("peer-as", "N/A"),
                        "state": peer.findtext("peer-state", "N/A"),
                        "up_time": peer.findtext("elapsed-time", "N/A"),
                    }
                    bgp_info["neighbors"].append(peer_data)
                bgp_info["groups"].append(group_name)
        except Exception as e:
            logger.warning(f"Error parsing BGP status: {e}")
        return bgp_info

    @staticmethod
    def _parse_interface_status(data: etree._Element) -> Dict[str, Any]:
        """Parse interface status from XML."""
        iface_info = {"interfaces": []}
        try:
            for iface in data.findall(".//physical-interface"):
                iface_data = {
                    "name": iface.findtext("name", "N/A"),
                    "status": iface.findtext("oper-status", "N/A"),
                    "mtu": iface.findtext("mtu", "N/A"),
                    "speed": iface.findtext("speed", "N/A"),
                    "logical_interfaces": []
                }
                for logical in iface.findall("logical-interface"):
                    logical_data = {
                        "name": logical.findtext("name", "N/A"),
                        "status": logical.findtext("oper-status", "N/A"),
                        "ip_addresses": []
                    }
                    for addr_family in logical.findall("address-family"):
                        for addr in addr_family.findall("interface-address"):
                            logical_data["ip_addresses"].append(
                                addr.findtext("ifa-destination", "N/A")
                            )
                    iface_data["logical_interfaces"].append(logical_data)
                iface_info["interfaces"].append(iface_data)
        except Exception as e:
            logger.warning(f"Error parsing interface status: {e}")
        return iface_info

    @staticmethod
    def _parse_lldp_neighbors(data: etree._Element) -> Dict[str, Any]:
        """Parse LLDP neighbors from XML."""
        lldp_info = {"neighbors": []}
        try:
            for neighbor in data.findall(".//lldp-neighbor-information"):
                neighbor_data = {
                    "local_interface": neighbor.findtext("lldp-local-interface", "N/A"),
                    "remote_device": neighbor.findtext("lldp-remote-system-name", "N/A"),
                    "remote_interface": neighbor.findtext("lldp-remote-port-id", "N/A"),
                    "remote_ip": neighbor.findtext("lldp-remote-management-address", "N/A"),
                }
                lldp_info["neighbors"].append(neighbor_data)
        except Exception as e:
            logger.warning(f"Error parsing LLDP neighbors: {e}")
        return lldp_info

    @staticmethod
    def _parse_routing_table(data: etree._Element) -> Dict[str, Any]:
        """Parse routing table from XML."""
        routes = {"tables": []}
        try:
            for table in data.findall(".//route-table"):
                table_data = {
                    "name": table.findtext("table-name", "N/A"),
                    "routes": []
                }
                for route in table.findall("rt"):
                    route_data = {
                        "destination": route.findtext("rt-destination", "N/A"),
                        "protocol": route.findtext("rt-entry/protocol-name", "N/A"),
                        "preference": route.findtext("rt-entry/preference", "N/A"),
                    }
                    table_data["routes"].append(route_data)
                routes["tables"].append(table_data)
        except Exception as e:
            logger.warning(f"Error parsing routing table: {e}")
        return routes


def display_bgp_status(bgp_info: Dict[str, Any]):
    """Display BGP status in table format."""
    if not bgp_info.get("neighbors"):
        console.print("[yellow]No BGP neighbors found[/yellow]")
        return

    table = Table(title="BGP Neighbor Status")
    table.add_column("Group", style="cyan")
    table.add_column("IP Address", style="cyan")
    table.add_column("ASN", style="magenta")
    table.add_column("State", style="green")
    table.add_column("Up Time", style="yellow")

    for neighbor in bgp_info["neighbors"]:
        state_color = "green" if neighbor["state"] == "Established" else "red"
        table.add_row(
            neighbor["group"],
            neighbor["ip_address"],
            neighbor["asn"],
            f"[{state_color}]{neighbor['state']}[/{state_color}]",
            neighbor["up_time"]
        )

    console.print(table)


def display_interface_status(iface_info: Dict[str, Any]):
    """Display interface status in table format."""
    if not iface_info.get("interfaces"):
        console.print("[yellow]No interfaces found[/yellow]")
        return

    table = Table(title="Interface Status")
    table.add_column("Interface", style="cyan")
    table.add_column("Status", style="cyan")
    table.add_column("MTU", style="magenta")
    table.add_column("Speed", style="yellow")

    for iface in iface_info["interfaces"]:
        status_color = "green" if iface["status"] == "up" else "red"
        table.add_row(
            iface["name"],
            f"[{status_color}]{iface['status']}[/{status_color}]",
            iface["mtu"],
            iface["speed"]
        )

    console.print(table)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Retrieve operational state from Juniper devices via NETCONF",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Get BGP status
  %(prog)s --host 10.0.0.1 --bgp

  # Get all information
  %(prog)s --host 10.0.1.1 --all

  # Output as JSON
  %(prog)s --host 10.0.2.1 --interfaces --lldp --json

  # Using SSH key authentication
  %(prog)s --host 10.0.3.1 --bgp --sshkey ~/.ssh/id_rsa
        """
    )

    parser.add_argument("--host", required=True, help="Device IP address or hostname")
    parser.add_argument("--port", type=int, default=830, help="NETCONF port (default: 830)")
    parser.add_argument("--username", required=True, help="Username for authentication")
    parser.add_argument("--password", help="Password (if not using SSH key)")
    parser.add_argument("--sshkey", help="Path to SSH private key file")
    parser.add_argument("--system", action="store_true", help="Get system information")
    parser.add_argument("--bgp", action="store_true", help="Get BGP status")
    parser.add_argument("--interfaces", action="store_true", help="Get interface status")
    parser.add_argument("--lldp", action="store_true", help="Get LLDP neighbors")
    parser.add_argument("--routes", action="store_true", help="Get routing table")
    parser.add_argument("--all", action="store_true", help="Get all information")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        default="INFO",
        help="Logging level (default: INFO)"
    )

    args = parser.parse_args()

    # Set logging level
    logger.setLevel(getattr(logging, args.log_level))

    # Validate arguments
    if not args.password and not args.sshkey:
        console.print("[red]Error: Either --password or --sshkey must be provided[/red]")
        sys.exit(1)

    # Determine what to retrieve
    if args.all:
        args.system = args.bgp = args.interfaces = args.lldp = args.routes = True

    if not any([args.system, args.bgp, args.interfaces, args.lldp, args.routes]):
        console.print("[red]Error: At least one data type must be specified[/red]")
        sys.exit(1)

    # Create state retriever
    retriever = NetconfStateRetriever(
        host=args.host,
        username=args.username,
        password=args.password,
        sshkey=args.sshkey,
        port=args.port,
    )

    results = {}

    try:
        # Connect to device
        if not retriever.connect():
            sys.exit(1)

        # Retrieve requested information
        if args.system:
            results["system"] = retriever.get_system_info()
        if args.bgp:
            results["bgp"] = retriever.get_bgp_status()
        if args.interfaces:
            results["interfaces"] = retriever.get_interface_status()
        if args.lldp:
            results["lldp"] = retriever.get_lldp_neighbors()
        if args.routes:
            results["routes"] = retriever.get_routing_table()

        # Output results
        if args.json:
            console.print_json(data=results)
        else:
            if results.get("system"):
                table = Table(title="System Information")
                for key, value in results["system"].items():
                    table.add_row(key, str(value))
                console.print(table)

            if results.get("bgp"):
                display_bgp_status(results["bgp"])

            if results.get("interfaces"):
                display_interface_status(results["interfaces"])

            if results.get("lldp") and results["lldp"].get("neighbors"):
                table = Table(title="LLDP Neighbors")
                table.add_column("Local Interface", style="cyan")
                table.add_column("Remote Device", style="magenta")
                table.add_column("Remote Interface", style="yellow")
                table.add_column("Remote IP", style="green")
                for neighbor in results["lldp"]["neighbors"]:
                    table.add_row(
                        neighbor["local_interface"],
                        neighbor["remote_device"],
                        neighbor["remote_interface"],
                        neighbor["remote_ip"]
                    )
                console.print(table)

        sys.exit(0)

    except KeyboardInterrupt:
        logger.warning("Operation cancelled by user")
        sys.exit(130)
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        sys.exit(1)
    finally:
        retriever.disconnect()


if __name__ == "__main__":
    main()
