# Kubernetes PVC Bound Status Monitoring for Zabbix

Monitor Kubernetes Persistent Volume Claim (PVC) bound status through Zabbix agent UserParameters.

## Purpose

This monitoring solution detects when Kubernetes NFS-backed PVCs become unbound during cluster rebuilds or configuration issues. It's particularly useful for stateful applications like weather station services that rely on NFS storage.

## Overview

**Problem Solved:** During Kubernetes cluster rebuilds, PVCs can fail to bind to their Persistent Volumes (PVs), causing application failures that are difficult to diagnose.

**Solution:** A lightweight UserParameter that queries Kubernetes API via kubectl to verify PVC binding status and reports to Zabbix for alerting and visualization.

## Architecture
```
┌─────────────────┐
│  Zabbix Server  │
└────────┬────────┘
         │ Agent request (TLS/PSK)
         │ k8s.pvc.bound[pvc-name,namespace]
         ▼
┌──────────────────────────┐
│   Zabbix Agent (knode)   │
│   UserParameter          │
└────────┬─────────────────┘
         │ Executes script
         ▼
┌──────────────────────────┐
│ check_k8s_pvc_bound.sh   │
│ (runs as zabbix user)    │
└────────┬─────────────────┘
         │ kubectl --kubeconfig=...
         ▼
┌──────────────────────────┐
│   Kubernetes API         │
│   (checks PVC status)    │
└──────────────────────────┘
```

## Why UserParameter Instead of External Check?

✅ **Runs on agent side** - Works even when Zabbix server is remote or containerized  
✅ **Survives upgrades** - Not affected by Zabbix server container updates  
✅ **Uses existing agent** - No additional infrastructure needed  
✅ **TLS support** - Works with encrypted agent connections  
✅ **Standard approach** - Follows Zabbix best practices  

## Files

- **check_k8s_pvc_bound.sh** - Main monitoring script
- **install.sh** - Automated installation script
- **README.md** - This documentation

## Prerequisites

- Zabbix agent installed and running on Kubernetes node
- kubectl installed and configured
- User kubeconfig at `~/.kube/config`
- Kubernetes cluster with PVCs to monitor
- Network access from Zabbix server to agent

## Installation

### Quick Install
```bash
# Clone repository
cd ~/projects
git clone https://github.com/jkozik/zabbix-nfs-bound-status.git
cd zabbix-nfs-bound-status

# Run installer
sudo ./install.sh
```

The installer will:
1. Copy script to `/usr/local/bin/`
2. Create UserParameter config in `/etc/zabbix/zabbix_agentd.d/`
3. Set proper permissions for zabbix user
4. Configure kubeconfig access
5. Restart Zabbix agent

### Manual Installation

If you prefer manual installation:

#### 1. Install Script
```bash
sudo cp check_k8s_pvc_bound.sh /usr/local/bin/
sudo chmod 755 /usr/local/bin/check_k8s_pvc_bound.sh
```

#### 2. Create UserParameter
```bash
sudo tee /etc/zabbix/zabbix_agentd.d/kubernetes_pvc.conf <<'CONF'
##
## Kubernetes PVC Monitoring UserParameters
##
UserParameter=k8s.pvc.bound[*],/usr/local/bin/check_k8s_pvc_bound.sh $1 $2
CONF
```

#### 3. Configure Permissions
```bash
# Allow zabbix user to traverse directories
sudo chmod o+x /home/jkozik
sudo chmod o+x /home/jkozik/.kube

# Allow zabbix user to read kubeconfig
sudo setfacl -m u:zabbix:r /home/jkozik/.kube/config
```

#### 4. Restart Agent
```bash
sudo systemctl daemon-reload
sudo systemctl restart zabbix-agent
```

### Verify Installation
```bash
# Test script manually
sudo -u zabbix /usr/local/bin/check_k8s_pvc_bound.sh nwcom-persistent-storage default
# Should return: 1 (if PVC exists and is bound)

# Test UserParameter (requires zabbix-get)
zabbix_get -s 127.0.0.1 -k "k8s.pvc.bound[nwcom-persistent-storage,default]"
# Should return: 1
```

## Zabbix Configuration

### Create Item

**Data collection → Hosts → [Your Kubernetes Node] → Items → Create item**

**Basic Configuration:**
- **Name**: `K8s PVC - nwcom Bound Status`
- **Type**: `Zabbix agent`
- **Key**: `k8s.pvc.bound[nwcom-persistent-storage,default]`
  - First parameter: PVC name
  - Second parameter: Namespace (default if omitted)
- **Type of information**: `Numeric (unsigned)`
- **Update interval**: `5m`
- **History storage period**: `7d`

**Value Mapping:**
Create or select value mapping:
- `0` = `Unbound` (or `Down`)
- `1` = `Bound` (or `Up`)

**Description:**
```
Monitors Kubernetes PVC binding status via kubectl.
Returns 1 if bound, 0 if unbound or missing.
```

### Create Trigger

**Configuration → Hosts → [Your Host] → Triggers → Create trigger**

- **Name**: `K8s PVC nwcom not bound`
- **Severity**: `High`
- **Expression**: 
```
  last(/knode204.kozik.net/k8s.pvc.bound[nwcom-persistent-storage,default])=0
```
- **OK event generation**: `Recovery expression`
- **Recovery expression**: 
```
  last(/knode204.kozik.net/k8s.pvc.bound[nwcom-persistent-storage,default])=1
```
- **Description**: 
```
  Kubernetes PVC nwcom-persistent-storage is not in Bound state.
  This will prevent applications from accessing NFS storage.
  
  Troubleshooting:
  - kubectl get pvc nwcom-persistent-storage
  - kubectl get pv nwcom-persistent-storage
  - kubectl describe pvc nwcom-persistent-storage
  
  Common causes:
  - NFS server unreachable (check network/firewall)
  - PV configuration error
  - Storage class issues
  - Insufficient storage capacity
```

### Add to Map (Optional)

Create visual map showing storage connectivity:

**Monitoring → Maps → Edit Map**

1. Add host elements for your services
2. Create link between elements
3. Configure **Link indicators**:
   - **Type**: `Trigger`
   - **Trigger**: `[Host]: K8s PVC nwcom not bound`
   - **Color**: Red (problem) / Green (OK)

This visually shows the NFS storage connection status between services.

## Usage Examples

### Monitor Multiple PVCs

**Weather Station Infrastructure:**
```
# Naperville station
k8s.pvc.bound[nwcom-persistent-storage,default]

# Sanibel/Captiva station
k8s.pvc.bound[sancap-persistent-storage,default]

# Campton Hills station
k8s.pvc.bound[chwcom-persistent-storage,default]
```

### Different Namespaces
```
# Production namespace
k8s.pvc.bound[my-pvc,production]

# Staging namespace
k8s.pvc.bound[my-pvc,staging]

# Development namespace
k8s.pvc.bound[my-pvc,dev]
```

### Default Namespace
```
# Namespace parameter is optional, defaults to "default"
k8s.pvc.bound[my-pvc]
# Same as: k8s.pvc.bound[my-pvc,default]
```

## Troubleshooting

### Item Shows "Not Supported"

**Check agent logs:**
```bash
sudo tail -50 /var/log/zabbix/zabbix_agentd.log
```

**Common causes:**
1. UserParameter not loaded - restart agent
2. Script not executable - check permissions
3. Script path incorrect in UserParameter
4. Agent not restarted after adding UserParameter

### UserParameter Returns 0 for Existing PVC

**Test as zabbix user:**
```bash
sudo -u zabbix /usr/local/bin/check_k8s_pvc_bound.sh nwcom-persistent-storage default
```

**Check permissions:**
```bash
# Verify zabbix can read kubeconfig
sudo -u zabbix cat /home/jkozik/.kube/config | head -5

# Check directory permissions
ls -la /home/jkozik | grep .kube
ls -la /home/jkozik/.kube/

# Verify ACL
getfacl /home/jkozik/.kube/config | grep zabbix
```

**Fix permissions:**
```bash
sudo chmod o+x /home/jkozik
sudo chmod o+x /home/jkozik/.kube
sudo setfacl -m u:zabbix:r /home/jkozik/.kube/config
```

### TLS/Encryption Errors

**Symptom:** "unencrypted connections are not allowed"

**Solution:** Configure TLS/PSK in Zabbix host configuration

1. Get PSK settings from agent:
```bash
   grep -E "^TLS" /etc/zabbix/zabbix_agentd.conf
   sudo cat /etc/zabbix/zabbix_agentd.psk
```

2. In Zabbix web interface:
   - **Hosts → [Your Host] → Encryption tab**
   - **Connections to host**: `PSK`
   - **PSK identity**: (from agent config)
   - **PSK**: (from .psk file)

### kubectl Not Found

**Error:** Script returns 0 but kubectl works manually

**Solution:** Use full path in script
```bash
# Find kubectl location
which kubectl

# Edit script to use full path
sudo nano /usr/local/bin/check_k8s_pvc_bound.sh
# Change to: /usr/bin/kubectl or /usr/local/bin/kubectl
```

### Kubeconfig Path Changed

**Update script:**
```bash
sudo nano /usr/local/bin/check_k8s_pvc_bound.sh

# Update KUBECONFIG_PATH variable
KUBECONFIG_PATH="/new/path/to/kubeconfig"
```

## Security Considerations

- ✅ Zabbix user has **read-only** access to kubeconfig
- ✅ ACLs provide granular permission control  
- ✅ No write access to Kubernetes cluster
- ✅ Script runs with minimal privileges
- ✅ Compatible with TLS/PSK encrypted agent connections
- ⚠️ Monitor kubeconfig file for unauthorized changes
- ⚠️ Regularly review zabbix user permissions

## Maintenance

### Update Script
```bash
cd ~/projects/zabbix-nfs-bound-status
git pull
sudo cp check_k8s_pvc_bound.sh /usr/local/bin/
```

### Add New PVCs

Just create new items with different parameters:
```
k8s.pvc.bound[new-pvc-name,namespace]
```

No script changes needed!

### Disable Monitoring Temporarily

**Option 1:** Disable item in Zabbix  
**Option 2:** Put host in maintenance mode

## Performance

- **CPU Impact**: Negligible (~0.01% per check)
- **Memory**: < 10 MB per execution
- **Network**: Minimal (kubectl API calls only)
- **Recommended interval**: 5 minutes
- **Concurrent checks**: Safe to monitor 100+ PVCs

## Use Case

This monitoring was developed for weather station infrastructure where multiple geographically-separated stations rely on Kubernetes-orchestrated services with NFS-backed storage. During cluster maintenance or rebuilds, PVC binding issues were the most common failure mode. This monitoring provides immediate visibility into storage connectivity issues.

## Architecture Benefits

**UserParameter Advantages:**
- Works with remote/containerized Zabbix servers
- Survives Zabbix server upgrades
- Standard Zabbix agent approach
- Compatible with all agent features (active checks, encryption)
- Lower latency than external checks

**vs External Checks:**
- External checks run on Zabbix server
- Requires kubectl on server (difficult with containers)
- Requires network access to Kubernetes API from server
- More complex permission management

## Author

Jack Kozik  
Created: January 2025

## Repository

https://github.com/jkozik/zabbix-nfs-bound-status

## License

Free to use and modify for personal and commercial use.

## Changelog

### v2.0 - UserParameter Approach (2025-01-15)
- Changed from external check to UserParameter
- Improved compatibility with containerized Zabbix servers
- Added TLS/PSK support
- Enhanced installation script with better error checking
- Updated documentation

### v1.0 - Initial Release (2025-01-15)
- External check implementation
- Basic monitoring functionality
