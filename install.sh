#!/bin/bash
################################################################################
# install.sh
#
# Installation script for Kubernetes PVC monitoring via Zabbix UserParameter
#
# This script:
# 1. Installs the check script to /usr/local/bin
# 2. Creates UserParameter configuration for Zabbix agent
# 3. Sets proper ownership and permissions
# 4. Configures access to kubeconfig for zabbix user
# 5. Restarts Zabbix agent to load new UserParameter
#
# Prerequisites:
# - Zabbix agent installed and running
# - kubectl installed and configured
# - User kubeconfig at ~/.kube/config
# - Kubernetes cluster accessible
#
# Usage: sudo ./install.sh
################################################################################

set -e  # Exit on error

# Configuration
SCRIPT_NAME="check_k8s_pvc_bound.sh"
INSTALL_DIR="/usr/local/bin"
USERPARAMETER_DIR="/etc/zabbix/zabbix_agentd.d"
USERPARAMETER_FILE="kubernetes_pvc.conf"
KUBECONFIG_PATH="${HOME}/.kube/config"
ZABBIX_USER="zabbix"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================================"
echo "Kubernetes PVC Monitoring - Zabbix UserParameter Setup"
echo "========================================================"
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
echo "  Script install directory: $INSTALL_DIR"
echo "  UserParameter directory: $USERPARAMETER_DIR"
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

# Check if Zabbix agent config directory exists
if [ ! -d "$USERPARAMETER_DIR" ]; then
    echo -e "${YELLOW}WARNING: UserParameter directory not found${NC}"
    echo "Creating directory: $USERPARAMETER_DIR"
    mkdir -p "$USERPARAMETER_DIR"
fi
echo -e "${GREEN}✓${NC} UserParameter directory exists"

# Check if zabbix user exists
if ! id "$ZABBIX_USER" &>/dev/null; then
    echo -e "${RED}ERROR: User '$ZABBIX_USER' does not exist${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Zabbix user exists"

# Check if Zabbix agent is running
AGENT_RUNNING=false
if systemctl is-active --quiet zabbix-agent; then
    AGENT_SERVICE="zabbix-agent"
    AGENT_RUNNING=true
    echo -e "${GREEN}✓${NC} Zabbix agent is running (zabbix-agent)"
elif systemctl is-active --quiet zabbix-agent2; then
    AGENT_SERVICE="zabbix-agent2"
    AGENT_RUNNING=true
    echo -e "${GREEN}✓${NC} Zabbix agent is running (zabbix-agent2)"
else
    echo -e "${YELLOW}WARNING: Zabbix agent is not running${NC}"
fi

echo ""
echo "Installing script..."

# Update kubeconfig path in script
sed -i "s|KUBECONFIG_PATH=\".*\"|KUBECONFIG_PATH=\"$KUBECONFIG_PATH\"|" "$SCRIPT_NAME"

# Copy script to installation directory
cp "$SCRIPT_NAME" "$INSTALL_DIR/"
echo -e "${GREEN}✓${NC} Script copied to $INSTALL_DIR/"

# Set ownership and permissions
chown root:root "$INSTALL_DIR/$SCRIPT_NAME"
chmod 755 "$INSTALL_DIR/$SCRIPT_NAME"
echo -e "${GREEN}✓${NC} Permissions set on script"

echo ""
echo "Creating UserParameter configuration..."

# Create UserParameter configuration
cat > "$USERPARAMETER_DIR/$USERPARAMETER_FILE" <<'USERPARAMETER_EOF'
##
## Kubernetes PVC Monitoring UserParameters
##
## Check if a Kubernetes PVC is in Bound state
## Usage: k8s.pvc.bound[<pvc-name>,<namespace>]
## Returns: 1 if bound, 0 if not bound or missing
##
## Example:
##   k8s.pvc.bound[nwcom-persistent-storage,default]
##   k8s.pvc.bound[my-pvc,production]
##

UserParameter=k8s.pvc.bound[*],/usr/local/bin/check_k8s_pvc_bound.sh $1 $2
USERPARAMETER_EOF

echo -e "${GREEN}✓${NC} UserParameter configuration created"

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

# Test script execution as zabbix user
TEST_PVC="test-nonexistent-pvc"
RESULT=$(su -s /bin/bash -c "$INSTALL_DIR/$SCRIPT_NAME $TEST_PVC default" $ZABBIX_USER 2>&1)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Script executes successfully as zabbix user"
    echo "  Test result: $RESULT (0 is expected for non-existent PVC)"
else
    echo -e "${RED}ERROR: Script failed to execute${NC}"
    echo "  Error: $RESULT"
    exit 1
fi

# Restart Zabbix agent if it's running
if [ "$AGENT_RUNNING" = true ]; then
    echo ""
    echo "Restarting Zabbix agent to load UserParameter..."
    
    systemctl daemon-reload
    systemctl restart $AGENT_SERVICE
    
    if systemctl is-active --quiet $AGENT_SERVICE; then
        echo -e "${GREEN}✓${NC} Zabbix agent restarted successfully"
    else
        echo -e "${RED}ERROR: Failed to restart Zabbix agent${NC}"
        systemctl status $AGENT_SERVICE
        exit 1
    fi
fi

# Test with actual PVC if provided
echo ""
echo -e "${BLUE}Testing with actual PVC (optional):${NC}"
echo "  To test with an actual PVC, run:"
echo "  sudo -u $ZABBIX_USER $INSTALL_DIR/$SCRIPT_NAME <pvc-name> <namespace>"
echo ""
echo "  Example:"
echo "  sudo -u $ZABBIX_USER $INSTALL_DIR/$SCRIPT_NAME nwcom-persistent-storage default"

echo ""
echo "========================================================"
echo -e "${GREEN}Installation completed successfully!${NC}"
echo "========================================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Test the UserParameter locally:"
echo "   zabbix_get -s 127.0.0.1 -k \"k8s.pvc.bound[<pvc-name>,<namespace>]\""
echo ""
echo "2. In Zabbix web interface, create an item:"
echo "   - Type: Zabbix agent"
echo "   - Key: k8s.pvc.bound[nwcom-persistent-storage,default]"
echo "   - Type of information: Numeric (unsigned)"
echo "   - Value mapping: 0=Unbound, 1=Bound"
echo ""
echo "3. Create a trigger:"
echo "   - Expression: last(/host/k8s.pvc.bound[...])=0"
echo ""
echo "4. See README.md for complete configuration details"
echo ""
echo "UserParameter key format:"
echo "  k8s.pvc.bound[<pvc-name>,<namespace>]"
echo ""
echo "Example keys:"
echo "  k8s.pvc.bound[nwcom-persistent-storage,default]"
echo "  k8s.pvc.bound[sancap-persistent-storage,default]"
echo "  k8s.pvc.bound[my-pvc,production]"
echo ""
