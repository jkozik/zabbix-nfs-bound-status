#!/bin/bash
################################################################################
# install.sh
#
# Installation script for Kubernetes PVC monitoring in Zabbix
#
# This script:
# 1. Installs the check script to Zabbix external scripts directory
# 2. Sets proper ownership and permissions
# 3. Configures access to kubeconfig for zabbix user
#
# Prerequisites:
# - Zabbix server/proxy installed
# - kubectl installed and configured
# - User kubeconfig at ~/.kube/config
#
# Usage: sudo ./install.sh
################################################################################

set -e  # Exit on error

# Configuration
SCRIPT_NAME="check_k8s_pvc_bound.sh"
ZABBIX_SCRIPTS_DIR="/usr/lib/zabbix/externalscripts"
KUBECONFIG_PATH="${HOME}/.kube/config"
ZABBIX_USER="zabbix"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "==============================================="
echo "Kubernetes PVC Monitoring - Zabbix Installation"
echo "==============================================="
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERROR: This script must be run with sudo${NC}"
    echo "Usage: sudo ./install.sh"
    exit 1
fi

# Get the actual user (not root when using sudo)
ACTUAL_USER="${SUDO_USER:-$USER}"
ACTUAL_HOME=$(eval echo ~$ACTUAL_USER)
KUBECONFIG_PATH="$ACTUAL_HOME/.kube/config"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Zabbix scripts directory: $ZABBIX_SCRIPTS_DIR"
echo "  Kubeconfig path: $KUBECONFIG_PATH"
echo "  Zabbix user: $ZABBIX_USER"
echo "  Actual user: $ACTUAL_USER"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}ERROR: kubectl is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} kubectl is installed"

# Check if kubeconfig exists
if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo -e "${RED}ERROR: kubeconfig not found at $KUBECONFIG_PATH${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} kubeconfig found"

# Check if Zabbix scripts directory exists
if [ ! -d "$ZABBIX_SCRIPTS_DIR" ]; then
    echo -e "${YELLOW}WARNING: Zabbix scripts directory not found${NC}"
    echo "Creating directory: $ZABBIX_SCRIPTS_DIR"
    mkdir -p "$ZABBIX_SCRIPTS_DIR"
fi
echo -e "${GREEN}✓${NC} Zabbix scripts directory exists"

# Check if zabbix user exists
if ! id "$ZABBIX_USER" &>/dev/null; then
    echo -e "${RED}ERROR: User '$ZABBIX_USER' does not exist${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Zabbix user exists"

echo ""
echo "Installing script..."

# Update kubeconfig path in script
sed -i "s|KUBECONFIG_PATH=\".*\"|KUBECONFIG_PATH=\"$KUBECONFIG_PATH\"|" "$SCRIPT_NAME"

# Copy script to Zabbix directory
cp "$SCRIPT_NAME" "$ZABBIX_SCRIPTS_DIR/"
echo -e "${GREEN}✓${NC} Script copied to $ZABBIX_SCRIPTS_DIR/"

# Set ownership and permissions
chown $ZABBIX_USER:$ZABBIX_USER "$ZABBIX_SCRIPTS_DIR/$SCRIPT_NAME"
chmod 755 "$ZABBIX_SCRIPTS_DIR/$SCRIPT_NAME"
echo -e "${GREEN}✓${NC} Permissions set"

# Configure kubeconfig access
echo ""
echo "Configuring kubeconfig access for zabbix user..."

# Set execute permission on home directory and .kube directory
chmod o+x "$ACTUAL_HOME"
chmod o+x "$ACTUAL_HOME/.kube"
echo -e "${GREEN}✓${NC} Directory permissions set"

# Set ACL for zabbix user to read kubeconfig
if command -v setfacl &> /dev/null; then
    setfacl -m u:$ZABBIX_USER:r "$KUBECONFIG_PATH"
    echo -e "${GREEN}✓${NC} ACL set for kubeconfig"
else
    echo -e "${YELLOW}WARNING: setfacl not found, setting file permissions instead${NC}"
    chmod 644 "$KUBECONFIG_PATH"
fi

# Test the installation
echo ""
echo "Testing installation..."

# Test as zabbix user
TEST_PVC="test-pvc"  # This will return 0 (not found) but proves the script works
RESULT=$(su -s /bin/bash -c "$ZABBIX_SCRIPTS_DIR/$SCRIPT_NAME $TEST_PVC default" $ZABBIX_USER 2>&1)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Script executes successfully as zabbix user"
    echo "  Test result: $RESULT (0 is expected for non-existent PVC)"
else
    echo -e "${RED}ERROR: Script failed to execute${NC}"
    echo "  Error: $RESULT"
    exit 1
fi

# Test with actual PVC if provided
echo ""
echo -e "${YELLOW}To test with an actual PVC, run:${NC}"
echo "  sudo -u $ZABBIX_USER $ZABBIX_SCRIPTS_DIR/$SCRIPT_NAME <pvc-name> default"

echo ""
echo "==============================================="
echo -e "${GREEN}Installation completed successfully!${NC}"
echo "==============================================="
echo ""
echo "Next steps:"
echo "1. Create Zabbix external check item with key:"
echo "   check_k8s_pvc_bound.sh[<pvc-name>,<namespace>]"
echo ""
echo "2. Example for nwcom weather station:"
echo "   check_k8s_pvc_bound.sh[nwcom-persistent-storage,default]"
echo ""
echo "3. See README.md for complete Zabbix configuration"
echo ""
