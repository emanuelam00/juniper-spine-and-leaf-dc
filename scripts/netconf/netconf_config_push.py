#!/usr/bin/env python3
"""
NETCONF Configuration Push Script

Pushes configuration to Juniper devices via NETCONF edit-config RPC.
Supports commit-confirm with automatic rollback on error.

Usage:
    python3 netconf_config_push.py --host 10.0.0.1 --config config.xml
    python3 netconf_config_push.py --host 10.0.1.1 --config config.txt --confirm --timeout 300
"""

import argparse
import logging
import sys
import time
from pathlib import Path
from typing import Optional

from ncclient import manager
from ncclient.operations.errors import OperationError
from rich.console import Console
from rich.logging import RichHandler

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    handlers=[RichHandler(rich_tracebacks=True)]
)
logger = logging.getLogger("netconf_config_push")
console = Console()


class NetconfConfigPush:
    """NETCONF configuration push handler for Juniper devices."""

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
                # SSH key authentication
                if not Path(self.sshkey).exists():
                    logger.error(f"SSH key file not found: {self.sshkey}")
                    return False

                self.session = manager.connect(
                    host=self.host,
                    port=self.port,
                    username=self.username,
                    key_filename=self.sshkey,
                    hostkey_verify=False,
                    timeout=self.timeout,
                )
            else:
                # Password authentication
                self.session = manager.connect(
                    host=self.host,
                    port=self.port,
                    username=self.username,
                    password=self.password,
                    hostkey_verify=False,
                    timeout=self.timeout,
                )

            logger.info(f"Successfully connected to {self.host}")
            logger.debug(f"Server capabilities: {self.session.server_capabilities}")
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

    def load_config(self, config_file: str) -> Optional[str]:
        """
        Load configuration from file.

        Args:
            config_file: Path to configuration file (XML or text format)

        Returns:
            Configuration string or None if load fails
        """
        try:
            config_path = Path(config_file)
            if not config_path.exists():
                logger.error(f"Configuration file not found: {config_file}")
                return None

            config_content = config_path.read_text()
            logger.info(f"Loaded configuration from {config_file} ({len(config_content)} bytes)")
            return config_content

        except Exception as e:
            logger.error(f"Failed to load configuration: {e}")
            return None

    def push_config(
        self,
        config: str,
        target: str = "candidate",
        action: str = "merge",
        confirm: bool = False,
        confirm_timeout: int = 300,
    ) -> bool:
        """
        Push configuration to device via NETCONF edit-config.

        Args:
            config: Configuration string (XML)
            target: Target datastore (candidate or running)
            action: Edit action (merge, replace, or delete)
            confirm: Enable commit-confirm with auto-rollback
            confirm_timeout: Timeout in seconds before auto-rollback

        Returns:
            True if successful, False otherwise
        """
        if not self.session:
            logger.error("Not connected to device")
            return False

        try:
            logger.info(f"Pushing configuration to {target} datastore...")
            logger.debug(f"Configuration size: {len(config)} bytes")

            # Send edit-config RPC
            reply = self.session.edit_config(
                target=target,
                config=config,
                default_operation=action,
            )

            if reply.ok:
                logger.info("Configuration accepted")
            else:
                logger.error(f"Configuration rejected: {reply}")
                return False

            # Commit configuration
            logger.info("Committing configuration...")
            if confirm:
                logger.info(f"Using commit-confirm with {confirm_timeout}s timeout")
                reply = self.session.commit(confirmed=True, timeout=confirm_timeout)
            else:
                reply = self.session.commit()

            if reply.ok:
                logger.info("Configuration committed successfully")
                return True
            else:
                logger.error(f"Commit failed: {reply}")
                return False

        except OperationError as e:
            logger.error(f"NETCONF operation failed: {e}")
            self._rollback()
            return False
        except Exception as e:
            logger.error(f"Unexpected error during configuration push: {e}")
            self._rollback()
            return False

    def _rollback(self) -> bool:
        """
        Rollback configuration to previous commit.

        Returns:
            True if rollback successful, False otherwise
        """
        if not self.session:
            return False

        try:
            logger.warning("Attempting rollback...")
            reply = self.session.discard_changes()
            if reply.ok:
                logger.info("Configuration rolled back successfully")
                return True
            else:
                logger.error(f"Rollback failed: {reply}")
                return False
        except Exception as e:
            logger.error(f"Rollback error: {e}")
            return False

    def validate_config(self, config: str) -> bool:
        """
        Validate configuration without committing.

        Args:
            config: Configuration string (XML)

        Returns:
            True if valid, False otherwise
        """
        if not self.session:
            logger.error("Not connected to device")
            return False

        try:
            logger.info("Validating configuration...")

            # Load config to candidate
            reply = self.session.edit_config(
                target="candidate",
                config=config,
                default_operation="merge",
            )

            if not reply.ok:
                logger.error(f"Validation failed: {reply}")
                return False

            # Validate candidate
            reply = self.session.validate(source="candidate")
            if reply.ok:
                logger.info("Configuration is valid")
                return True
            else:
                logger.error(f"Validation error: {reply}")
                return False

        except Exception as e:
            logger.error(f"Validation error: {e}")
            return False
        finally:
            # Discard candidate changes
            try:
                self.session.discard_changes()
            except Exception:
                pass


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Push configuration to Juniper devices via NETCONF",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic configuration push
  %(prog)s --host 10.0.0.1 --config config.xml

  # With commit-confirm (5 minute timeout)
  %(prog)s --host 10.0.1.1 --config config.txt --confirm --timeout 300

  # Validate only (don't commit)
  %(prog)s --host 10.0.2.1 --config config.xml --validate-only

  # Using SSH key authentication
  %(prog)s --host 10.0.3.1 --config config.xml --sshkey ~/.ssh/id_rsa
        """
    )

    parser.add_argument("--host", required=True, help="Device IP address or hostname")
    parser.add_argument("--port", type=int, default=830, help="NETCONF port (default: 830)")
    parser.add_argument("--username", required=True, help="Username for authentication")
    parser.add_argument("--password", help="Password (if not using SSH key)")
    parser.add_argument("--sshkey", help="Path to SSH private key file")
    parser.add_argument("--config", required=True, help="Configuration file (XML or text)")
    parser.add_argument(
        "--target",
        choices=["candidate", "running"],
        default="candidate",
        help="Target datastore (default: candidate)"
    )
    parser.add_argument(
        "--action",
        choices=["merge", "replace", "delete"],
        default="merge",
        help="Edit action (default: merge)"
    )
    parser.add_argument(
        "--confirm",
        action="store_true",
        help="Enable commit-confirm with auto-rollback"
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=300,
        help="Commit-confirm timeout in seconds (default: 300)"
    )
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate configuration without committing"
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

    # Validate arguments
    if not args.password and not args.sshkey:
        console.print("[red]Error: Either --password or --sshkey must be provided[/red]")
        sys.exit(1)

    # Create NETCONF handler
    handler = NetconfConfigPush(
        host=args.host,
        username=args.username,
        password=args.password,
        sshkey=args.sshkey,
        port=args.port,
    )

    try:
        # Connect to device
        if not handler.connect():
            sys.exit(1)

        # Load configuration
        config = handler.load_config(args.config)
        if not config:
            sys.exit(1)

        # Validate or push configuration
        if args.validate_only:
            success = handler.validate_config(config)
        else:
            success = handler.push_config(
                config=config,
                target=args.target,
                action=args.action,
                confirm=args.confirm,
                confirm_timeout=args.timeout,
            )

        sys.exit(0 if success else 1)

    except KeyboardInterrupt:
        logger.warning("Operation cancelled by user")
        sys.exit(130)
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        sys.exit(1)
    finally:
        handler.disconnect()


if __name__ == "__main__":
    main()
