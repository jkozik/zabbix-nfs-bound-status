# Kubernetes PVC Bound Status Monitoring for Zabbix

Monitor Kubernetes Persistent Volume Claim (PVC) bound status through Zabbix external checks.

## Purpose

This monitoring solution was created to detect when Kubernetes NFS-backed PVCs become unbound during cluster rebuilds or configuration issues. It's particularly useful for stateful applications like weather station services that rely on NFS storage.

## Overview

**Problem Solved:** During Kubernetes cluster rebuilds, PVCs can fail to bind to their Persistent Volumes (PVs), causing application failures that are difficult to diagnose.

**Solution:** A simple external check script that queries Kubernetes API to verify PVC binding status and reports to Zabbix for alerting and visualization.

## Architecture
```
┌─────────────┐
│   Zabbix    │
│   Server    │
└──────┬──────┘
       │ External Check (every 5 min)
       ▼
┌─────────────────────────────┐
│ check_k8s_pvc_bound.sh      │
│ (runs as zabbix user)       │
└──────┬──────────────────────┘
       │ kubectl --kubeconfig=...
       ▼
┌─────────────────────────────┐
│ Kubernetes API              │
│ (checks PVC status)         │
└─────────────────────────────┘
```

## Files

- **check_k8s_pvc_bound.sh** - Main monitoring script
- **install.sh** - Automated installation script
- **README.md** - This documentation

## Prerequisites

- Zabbix server or proxy with external check capability
- kubectl installed and configured
- User kubeconfig at `~/.kube/config`
- Kubernetes cluster with PVCs to monitor

## Installation

### 1. Clone or Download Repository
```bash
cd ~/projects
git clone <your-repo-url> zabbix-nfs-bound-status
# OR download and extract the files
cd zabbix-nfs-bound-status
```

### 2. Review Configuration

Edit `check_k8s_pvc_bound.sh` if your kubeconfig path is different:
```bash
# Default path
KUBECONFIG_PATH="/home/jkozik/.kube/config"

# Update if needed
KUBECONFIG_PATH="/path/to/your/kubeconfig"
```

### 3. Run Installation Script
```bash
sudo ./install.sh
```

The script will:
- Copy the check script to `/usr/lib/zabbix/externalscripts/`
- Set proper ownership and permissions
- Configure directory and file permissions for zabbix user access
- Set ACL on kubeconfig file
- Test the installation

### 4. Manual Test

Test the script with an actual PVC:
```bash
# Test as your user
/usr/lib/zabbix/externalscripts/check_k8s_pvc_bound.sh nwcom-persistent-storage default

# Test as zabbix user
sudo -u zabbix /usr/lib/zabbix/externalscripts/check_k8s_pvc_bound.sh nwcom-persistent-storage default

# Both should return: 1 (if PVC is bound)
```

## Zabbix Configuration

### Create Host

If monitoring a website/service that uses the PVC:

1. **Data collection → Hosts → Create host**
2. **Host name**: `napervilleweather.com` (or your service name)
3. **Visible name**: `Naperville Weather - Website`
4. **Groups**: `Weather Stations`
5. **Interfaces**: None (or dummy interface if required)

### Create Item

**Data collection → Hosts → [Your Host] → Items → Create item**

**Item Configuration:**
- **Name**: `NFS PVC - Bound Status`
- **Type**: `External check`
- **Key**: `check_k8s_pvc_bound.sh[nwcom-persistent-storage,default]`
  - Replace `nwcom-persistent-storage` with your PVC name
  - Replace `default` with your namespace if different
- **Type of information**: `Numeric (unsigned)`
- **Update interval**: `5m`
- **History storage period**: `7d`
- **Value mapping**: `Service state` (0=Down/Unbound, 1=Up/Bound)
- **Description**: `Checks if Kubernetes PVC is in Bound state`

### Create Trigger

**Configuration → Hosts → [Your Host] → Triggers → Create trigger**

**Trigger Configuration:**
- **Name**: `NFS PVC not bound`
- **Severity**: `High`
- **Expression**: 
```
  last(/napervilleweather.com/check_k8s_pvc_bound.sh[nwcom-persistent-storage,default])=0
```
- **OK event generation**: `Recovery expression`
- **Recovery expression**: 
```
  last(/napervilleweather.com/check_k8s_pvc_bound.sh[nwcom-persistent-storage,default])=1
```
- **Description**: 
```
  Kubernetes PVC nwcom-persistent-storage is not in Bound state.
  This will prevent the application from accessing NFS storage.
  
  Troubleshooting:
  - kubectl get pvc nwcom-persistent-storage
  - kubectl get pv nwcom-persistent-storage
  - kubectl describe pvc nwcom-persistent-storage
  
  Common causes:
  - NFS server unreachable
  - PV configuration error
  - Storage class issues
  - Network connectivity problems
```

### Add to Map (Optional)

Create visual map showing PVC status:

1. **Monitoring → Maps → [Your Map] → Edit**
2. Add host elements for your services
3. Create link between services
4. **Link indicators**:
   - **Type**: `Trigger`
   - **Trigger**: `[Host]: NFS PVC not bound`
   - **Color**: Red (problem), Green (OK)

## Usage Examples

### Monitor Multiple Weather Stations

**Naperville:**
```
check_k8s_pvc_bound.sh[nwcom-persistent-storage,default]
```

**Sanibel/Captiva:**
```
check_k8s_pvc_bound.sh[sancap-persistent-storage,default]
```

**Campton Hills:**
```
check_k8s_pvc_bound.sh[chwcom-persistent-storage,default]
```

### Check Different Namespaces
```
check_k8s_pvc_bound.sh[my-pvc,production]
check_k8s_pvc_bound.sh[my-pvc,staging]
```

## Troubleshooting

### Script Returns 0 When PVC is Bound

**Check permissions:**
```bash
# Test as zabbix user
sudo -u zabbix kubectl --kubeconfig=/home/jkozik/.kube/config get pvc

# Check directory permissions
ls -la /home/jkozik | grep .kube
ls -la /home/jkozik/.kube/

# Check file ACL
getfacl /home/jkozik/.kube/config | grep zabbix
```

**Fix permissions:**
```bash
sudo chmod o+x /home/jkozik
sudo chmod o+x /home/jkozik/.kube
sudo setfacl -m u:zabbix:r /home/jkozik/.kube/config
```

### Item Shows "Not Supported"

**Check:**
1. External checks are enabled in Zabbix configuration
2. Script exists and is executable: `ls -la /usr/lib/zabbix/externalscripts/check_k8s_pvc_bound.sh`
3. Script path is correct for your Zabbix installation

### kubectl Command Not Found

**Solution:**
```bash
# Add kubectl to PATH in script or use full path
which kubectl  # Find kubectl location
# Update script to use full path: /usr/local/bin/kubectl
```

## Maintenance

### Update kubeconfig Path

If kubeconfig location changes:

1. Edit script: `/usr/lib/zabbix/externalscripts/check_k8s_pvc_bound.sh`
2. Update `KUBECONFIG_PATH` variable
3. Restart zabbix-server/zabbix-proxy (if needed)

### Monitor New PVCs

Simply create new items with different PVC names in the key parameter:
```
check_k8s_pvc_bound.sh[new-pvc-name,namespace]
```

## Security Considerations

- The zabbix user has **read-only** access to kubeconfig
- ACLs provide granular permission control
- No write access to Kubernetes cluster
- Monitor kubeconfig file for unauthorized changes

## Author

Jack Kozik  
Created: January 2025

## Use Case

This monitoring was developed for weather station infrastructure where multiple geographically-separated stations rely on Kubernetes-orchestrated services with NFS-backed storage. During cluster maintenance or rebuilds, PVC binding issues were the most common failure mode, and this monitoring provides immediate visibility into storage connectivity issues.

## License

Free to use and modify for personal and commercial use.
