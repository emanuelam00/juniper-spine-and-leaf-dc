#!/bin/bash
#
# Juniper Spine-Leaf Fabric Health Check Script
#
# Comprehensive health check wrapper that runs all validation checks against
# the datacenter fabric. Generates timestamped reports and alerts.
#
# Usage:
#   ./fabric_health_check.sh --inventory inventory.yaml
#   ./fabric_health_check.sh --inventory inventory.yaml --report-dir /var/logs/fabric
#   ./fabric_health_check.sh --inventory inventory.yaml --email ops@example.com
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NETCONF_DIR="${SCRIPT_DIR}/netconf"

# Default configuration
INVENTORY_FILE=""
REPORT_DIR="./fabric-reports"
EMAIL_RECIPIENT=""
LOG_LEVEL="INFO"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
PARALLEL_JOBS=4

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    -i, --inventory FILE       Inventory file (YAML format) [REQUIRED]
    -r, --report-dir DIR       Report output directory (default: ./fabric-reports)
    -e, --email RECIPIENT      Email address for report (optional)
    -p, --parallel JOBS        Parallel jobs (default: 4)
    -l, --log-level LEVEL      Log level: DEBUG, INFO, WARNING, ERROR (default: INFO)
    -h, --help                 Show this help message

EXAMPLES:
    $(basename "$0") --inventory inventory.yaml
    $(basename "$0") --inventory inventory.yaml --report-dir /var/logs/fabric
    $(basename "$0") --inventory inventory.yaml --email ops@example.com

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--inventory)
            INVENTORY_FILE="$2"
            shift 2
            ;;
        -r|--report-dir)
            REPORT_DIR="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL_RECIPIENT="$2"
            shift 2
            ;;
        -p|--parallel)
            PARALLEL_JOBS="$2"
            shift 2
            ;;
        -l|--log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$INVENTORY_FILE" ]]; then
    log_error "Inventory file is required"
    print_usage
fi

if [[ ! -f "$INVENTORY_FILE" ]]; then
    log_error "Inventory file not found: $INVENTORY_FILE"
    exit 1
fi

# Create report directory
mkdir -p "$REPORT_DIR"
REPORT_DIR_TIMESTAMPED="${REPORT_DIR}/fabric-check_${TIMESTAMP}"
mkdir -p "$REPORT_DIR_TIMESTAMPED"

log_info "Starting fabric health check"
log_info "Report directory: $REPORT_DIR_TIMESTAMPED"
log_info "Timestamp: $TIMESTAMP"
log_info ""

# Initialize report file
REPORT_FILE="${REPORT_DIR_TIMESTAMPED}/health-check-report.txt"
JSON_REPORT="${REPORT_DIR_TIMESTAMPED}/health-check-report.json"

{
    echo "=========================================="
    echo "Juniper Spine-Leaf Fabric Health Check"
    echo "=========================================="
    echo "Timestamp: $(date)"
    echo "Inventory: $INVENTORY_FILE"
    echo ""
} | tee "$REPORT_FILE"

# Check Python availability
if ! command -v python3 &> /dev/null; then
    log_error "Python3 is required but not installed"
    exit 1
fi

# Check required Python modules
log_info "Checking Python dependencies..."
if ! python3 -c "import ncclient, yaml, rich" 2>/dev/null; then
    log_warning "Installing required Python packages..."
    pip3 install -q ncclient pyyaml rich lxml
fi

# Run validation checks
log_info ""
log_info "Running validation checks..."
log_info ""

VALIDATION_REPORT="${REPORT_DIR_TIMESTAMPED}/validation.json"

if [[ -f "${NETCONF_DIR}/netconf_validate.py" ]]; then
    log_info "Executing netconf_validate.py..."
    if python3 "${NETCONF_DIR}/netconf_validate.py" \
        --fabric "$INVENTORY_FILE" \
        --report "$VALIDATION_REPORT" \
        --log-level "$LOG_LEVEL" | tee -a "$REPORT_FILE"; then
        log_success "Validation checks completed"
    else
        log_warning "Some validation checks failed"
    fi
else
    log_error "netconf_validate.py not found at ${NETCONF_DIR}/netconf_validate.py"
fi

# Backup configurations
log_info ""
log_info "Backing up device configurations..."
log_info ""

BACKUP_REPORT="${REPORT_DIR_TIMESTAMPED}/backup-report.json"

if [[ -f "${NETCONF_DIR}/netconf_backup.py" ]]; then
    if python3 "${NETCONF_DIR}/netconf_backup.py" \
        --inventory "$INVENTORY_FILE" \
        --output "${REPORT_DIR_TIMESTAMPED}/backups" \
        --parallel "$PARALLEL_JOBS" \
        --report "$BACKUP_REPORT" \
        --log-level "$LOG_LEVEL" | tee -a "$REPORT_FILE"; then
        log_success "Configuration backup completed"
    else
        log_warning "Configuration backup had errors"
    fi
else
    log_warning "netconf_backup.py not found - skipping backup"
fi

# Get system state information
log_info ""
log_info "Gathering system state information..."
log_info ""

if [[ -f "${NETCONF_DIR}/netconf_get_state.py" ]]; then
    # Extract first device from inventory for state check
    FIRST_DEVICE=$(grep -A 5 "devices:" "$INVENTORY_FILE" | grep "hostname:" | head -1 | awk '{print $2}')
    FIRST_HOST=$(grep -A 5 "hostname: $FIRST_DEVICE" "$INVENTORY_FILE" | grep "host:" | awk '{print $2}')
    FIRST_USER=$(grep -A 10 "hostname: $FIRST_DEVICE" "$INVENTORY_FILE" | grep "username:" | awk '{print $2}')

    if [[ -n "$FIRST_HOST" && -n "$FIRST_USER" ]]; then
        log_info "Getting state from $FIRST_DEVICE ($FIRST_HOST)..."
        STATE_REPORT="${REPORT_DIR_TIMESTAMPED}/state-${FIRST_DEVICE}.json"

        # This will require credentials to be provided
        # For now, just show it's available
        log_info "State retrieval available via netconf_get_state.py"
    fi
else
    log_warning "netconf_get_state.py not found"
fi

# Generate summary
log_info ""
log_info "Generating summary report..."
log_info ""

{
    echo ""
    echo "=========================================="
    echo "Health Check Summary"
    echo "=========================================="
    echo "Timestamp: $(date)"
    echo "Report Directory: $REPORT_DIR_TIMESTAMPED"
    echo ""
    echo "Generated Files:"
    echo "  - Validation Report: $VALIDATION_REPORT"
    echo "  - Backup Report: $BACKUP_REPORT"
    if [[ -d "${REPORT_DIR_TIMESTAMPED}/backups" ]]; then
        echo "  - Backups: ${REPORT_DIR_TIMESTAMPED}/backups"
    fi
    echo ""
    echo "Key Metrics:"

    # Try to extract summary from JSON reports
    if [[ -f "$VALIDATION_REPORT" ]]; then
        FABRIC_HEALTH=$(python3 -c "import json; print(json.load(open('$VALIDATION_REPORT')).get('fabric_health', 'UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
        echo "  - Fabric Health: $FABRIC_HEALTH"
    fi

    if [[ -f "$BACKUP_REPORT" ]]; then
        BACKUP_SUCCESS=$(python3 -c "import json; print(json.load(open('$BACKUP_REPORT')).get('summary', {}).get('successful', 0))" 2>/dev/null || echo "0")
        BACKUP_TOTAL=$(python3 -c "import json; print(json.load(open('$BACKUP_REPORT')).get('summary', {}).get('total', 0))" 2>/dev/null || echo "0")
        echo "  - Backups Successful: $BACKUP_SUCCESS/$BACKUP_TOTAL"
    fi

    echo ""
    echo "=========================================="
} | tee -a "$REPORT_FILE"

# Send email report if requested
if [[ -n "$EMAIL_RECIPIENT" ]]; then
    log_info "Sending email report to $EMAIL_RECIPIENT..."

    if command -v mail &> /dev/null; then
        SUBJECT="Fabric Health Check Report - ${TIMESTAMP}"
        {
            cat "$REPORT_FILE"
            echo ""
            echo "Full report available at: $REPORT_DIR_TIMESTAMPED"
        } | mail -s "$SUBJECT" "$EMAIL_RECIPIENT"

        log_success "Email report sent to $EMAIL_RECIPIENT"
    else
        log_warning "mail command not found - cannot send email report"
    fi
fi

# Final status
log_success ""
log_success "Fabric health check completed!"
log_success "Reports saved to: $REPORT_DIR_TIMESTAMPED"
log_success ""

exit 0
