# RedHat Cluster Role

An Ansible role that provides automated installation and configuration of high availability clusters on RedHat/CentOS systems using Pacemaker and Corosync.

## How It Works

1. **Preparation & Installation**
   - Installs required packages (pacemaker, corosync, pcs, kdump)
   - Configures authentication using encrypted cluster password (Vault-protected)
   - Sets up required firewall rules for cluster communication

2. **Cluster Formation**
   - Creates the cluster with specified nodes
   - Configures corosync communication
   - Enables and configures STONITH using fence_kdump
   - Sets up watchdog device monitoring

3. **Resource Configuration**
   - Configures Virtual IP (floating IP) with automated failover
   - Sets up shared storage with NFS mounts
   - Configures application services with monitoring
   - Implements resource constraints and dependencies

4. **Network Monitoring**
   - Implements network watchdog service
   - Configures heartbeat monitoring
   - Sets up network failure detection
   - Manages automatic failover triggers

5. **Validation & Testing**
   - Verifies cluster configuration
   - Tests resource failover
   - Validates STONITH configuration
   - Checks NFS mounts and permissions

## Dependencies

This role has no external dependencies on other roles. However, it requires:
- Proper DNS resolution or /etc/hosts configuration for all nodes
- Network connectivity between nodes
- Valid SSH configuration allowing connection between nodes
- Valid NFS shared

## Key Features

- **Comprehensive Cluster Setup**
  - Automated multi-node cluster deployment
  - Secure authentication with vault-encrypted passwords
  - Advanced STONITH configuration using fence_kdump
  - No-quorum policy management
  - Automated firewall configuration

- **Advanced Watchdog Implementation**
  - Hardware watchdog integration with /dev/watchdog
  - Network failure detection
  - NFS mount monitoring
  - Customizable failure thresholds
  - Reboot control system
  - Heartbeat monitoring

- **Resource Management**
  - Virtual IP (floating IP) configuration
  - NFS shared storage integration
  - Resource dependencies and constraints
  - Automatic failover handling

## Variables

You can define the varibles directly in the playbook that will apply de the role.
Please take as reference the variables present at `defaults/main.yml`.

## Example Playbook

```yaml
---
- hosts: cluster_nodes
  become: true
  vars:
    infra__redhat_cluster_name: "prod_cluster"
    infra__redhat_cluster_password: "vault_encrypted"

    infra__set_cluster_hostname: false
    infra__redhat_cluster_update_password: false

    infra__redhat_cluster_nodes:
      - name: "node1"
        hostname: "node1"
        ip: "192.168.6.45"

      - name: "node2"
        hostname: "node2"
        ip: "192.168.6.46"

    # Floating IP
    infra__redhat_cluster_virtual_ip: "192.168.6.37"
    infra__redhat_cluster_virtual_ip_cidr: "22"
    infra__redhat_cluster_virtual_ip_interface: "ens18"  # Change to the appropriate interface
    infra__redhat_cluster_dns_for_virtual_ip: "test.example.com"

    # NFS configuration
    infra__redhat_cluster_nfs_server: "192.168.4.36"
    infra__redhat_cluster_nfs_share: "/var/lib/vz/nfs-export"
    infra__redhat_cluster_mount_point: "/opt/nfs-shared"

    # Watchdog NFS arbitrator configuration
    infra__redhat_cluster_watchdog_enabled_by_default: true
    infra__redhat_cluster_watchdog_nfs_witness_dir: "/opt/nfs-witness"
    infra__redhat_cluster_watchdog_active_nfs_failure_threshold: 60    # In seconds
    infra__redhat_cluster_watchdog_standby_nfs_failure_threshold: 180  # In seconds
    infra__redhat_cluster_watchdog_state_threshold: 60                 # In seconds
    infra__redhat_cluster_watchdog_arbitrator: "192.168.4.24"   # Hostname or IP

    # Hardware watchdog configuration
    infra__redhat_cluster_watchdog_device: "/dev/watchdog"
    infra__redhat_cluster_watchdog_interval: "10"
    infra__redhat_cluster_watchdog_heartbeat_file: "/var/run/arbitrator-heartbeat"
    infra__redhat_cluster_watchdog_heartbeat_change: "180"  # 3 minutes in seconds for reboot trigger

    # Resource monitoring configuration
    infra__redhat_cluster_resource_monitor_interval: "30s"
    infra__redhat_cluster_ip_monitor_interval: "10s"
    infra__redhat_cluster_fs_monitor_interval: "20s"

    # Cluster systemd services
    infra__redhat_cluster_services_list:
      - "tomcat"

  roles:
    - redhat_cluster
```
## Important Notes

Remember to start watchog service manually if you did not change to true `infra__redhat_cluster_watchdog_enabled_by_default`.
Watchdog service is stopped by default for security reasons and to avoid restarts if there is a problem with the files creation or permissions.
```bash
systemctl start watchdog && systemctl status watchdog
```

## Role Tags

- `prepare`: Initial system preparation
- `install`: Package installation
- `configure`: Basic cluster setup
- `stonith`: STONITH/fencing configuration
- `watchdog`: Watchdog service setup
- `resources`: Resource configuration
- `reboot_control`: Reboot management setup
- `diagnostics`: Install monitoring tools
- `validate`: Run validation tasks
- `cluster_test`: Create script for cluster test suite.
- `configure_systemd_services`: Systemd services to add to cluster. Order will be respected.

## Testing and Validation

```bash
# Execute complete script that has been set up at /usr/local/bin
cluster_tests

# Manual checks
# Check cluster status
pcs status

# Verify resources
pcs resource status

# Test failover
pcs node standby <node1>

# Clean resource failures
pcs resource cleanup

# View constraints
pcs constraint show --full

# Check logs
journalctl -u watchdog
journalctl -u network-watchdog
```

## Maintenance Operations

```bash
# Stop cluster on all nodes
pcs cluster stop --all

# Start cluster on all nodes
pcs cluster start --all

# Put node in maintenance
pcs node maintenance nodename

# Remove from maintenance
pcs node unmaintenance nodename

# Maintenance active for all cluster services
pcs property set maintenance-mode=true

# Resource refresh to cleanup errors
pcs resource cleanup && pcs resource refresh
```

## Command Reference Guide for manual installation

### Initial Setup Commands

```bash
# Install required repositories ONLY for ALMA LINUX
dnf install -y dnf-utils
dnf config-manager --set-enabled highavailability

# Install required repositories for RED HAT
subscription-manager repos --enable "rhel-9-for-x86_64-highavailability-rpms"

# Install packages
dnf install -y pcs pacemaker resource-agents watchdog fence-agents kexec-tools fence-agents-all nfs-utils nmap-ncat policycoreutils-python-utils libselinux-utils

# Configure firewall
firewall-cmd --permanent --add-service=high-availability
firewall-cmd --reload
```

### Cluster Configuration Commands

```bash
# Set cluster admin password
passwd hacluster

# Enable and start cluster service
systemctl enable --now pcsd

# Authenticate cluster nodes (replace with your node names)
pcs host auth <node1> <node2> -u hacluster

# Create cluster
pcs cluster setup <cluster_name> <node1> <node2>

# Start cluster
pcs cluster enable --all
pcs cluster start --all
```

### Resource Management Commands

```bash
# Create Virtual IP resource
pcs resource create virtual_ip IPaddr2 \
    ip=<virtual_ip_address> \
    cidr_netmask=<netmask> \
    nic=<network_interface> \
    op monitor interval=10s

# Create NFS mount resource
pcs resource create fs_shared Filesystem \
    device="<nfs_server>:<nfs_share>" \
    directory="<mount_point>" \
    fstype="nfs" \
    options="noatime,sync" \
    op monitor interval=20s

# Create service resource (example with Tomcat)
pcs resource create tomcat_service systemd:tomcat \
    op monitor interval=30s
```

### Constraint Management

```bash
# Create order constraints
pcs constraint order virtual_ip then fs_shared
pcs constraint order fs_shared then tomcat_service

# Create colocation constraints
pcs constraint colocation add fs_shared with virtual_ip INFINITY
pcs constraint colocation add tomcat_service with fs_shared INFINITY
```

### Monitoring and Status Commands

```bash
# Check cluster status
pcs status

# View cluster configuration
pcs config

# Show resource status
pcs resource show

# View all constraints
pcs constraint config

# Monitor logs
journalctl -u watchdog
journalctl -u network-watchdog
```

### Node Management Commands

```bash
# Set node maintenance mode
pcs node maintenance <node_name>
pcs node unmaintenance <node_name>

# Set node standby (for testing)
pcs node standby <node_name>
pcs node unstandby <node_name>
```

### Troubleshooting Commands

```bash
# Clean up resource failures
pcs resource cleanup

# Delete a resource
pcs resource delete <resource_name>

# Check STONITH status
pcs stonith config

# Verify resource constraints
pcs constraint config

# Check specific service status
systemctl status <service_name>
```
### Example of network-watchdog.sh
```bash
DNS_VIP="test.example.com"  # DNS for the virtual IP
# Configure other node directly from cluster_nodes variable
# Checking if this is the other node
if [[ "node1" != "$HOSTNAME" ]]; then
    OTHER_NODE="node1"
    OTHER_NODE_IP="192.168.6.45"
fi

# Checking if this is the other node
if [[ "node2" != "$HOSTNAME" ]]; then
    OTHER_NODE="node2"
    OTHER_NODE_IP="192.168.6.46"
fi

# If for some reason OTHER_NODE wasn't set by the above loop
if [ -z "$OTHER_NODE" ]; then
    # Fallback to trying to determine from /etc/hosts
    OTHER_NODE=$(grep -v "$HOSTNAME" /etc/hosts | grep -v "localhost" | grep -v "$DNS_VIP" | grep -v "\-mgmt" | head -n 1 | awk '{print $2}')

    if [ -z "$OTHER_NODE" ]; then
        echo "Error: Could not determine the other node's hostname" | logger -t cluster_arbitrator
        # Don't exit, try to continue with what we can do
    fi
fi

STATE_THRESHOLD=60                        # Threshold (in seconds) for peer state file freshness
ACTIVE_NFS_FAILURE_THRESHOLD=60           # For active node: if NFS fails for >60 seconds, go standby
STANDBY_NFS_FAILURE_THRESHOLD=180         # For standby node: if NFS fails for >300 seconds, reboot

# File to track when NFS failures begin
NFS_FAILURE_FILE="/var/run/nfs_failure.timestamp"

# Create/update heartbeat file for hardware watchdog
touch /var/run/arbitrator-heartbeat

SELF_STATE_FILE="${NFS_WITNESS_DIR}/${HOSTNAME}_state.json"
OTHER_STATE_FILE="${NFS_WITNESS_DIR}/${OTHER_NODE}_state.json"

# Logging function: writes to both a log file and the system logger
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp [$level] $message" >> "$LOG_FILE"
    logger -t cluster_arbitrator -p "daemon.$level" "$message"

    # For critical messages, save additional diagnostic information
    if [ "$level" = "alert" ] || [ "$level" = "crit" ] || [ "$level" = "emerg" ]; then
        {
            echo "-------- DIAGNOSTIC INFO --------"
            echo "Date: $(date)"
            echo "Hostname: $HOSTNAME"
            echo "Current role: $(is_active_node && echo 'ACTIVE' || echo 'STANDBY')"
            echo "Gateway status: $(check_gateway && echo 'UP' || echo 'DOWN')"
            echo "Arbitrator status: $(check_arbitrator && echo 'UP' || echo 'DOWN')"
            echo "NFS status: $(check_nfs_rw && echo 'OK' || echo 'FAILED')"
            echo "NFS failure duration: $(get_nfs_failure_duration) seconds"
            echo "Mount points:"
            mount | grep nfs
            echo "Peer state file:"
            if [ -f "$OTHER_STATE_FILE" ]; then
                cat "$OTHER_STATE_FILE"
            else
                echo "NOT FOUND"
            fi
            echo "Self state file:"
            if [ -f "$SELF_STATE_FILE" ]; then
                cat "$SELF_STATE_FILE"
            else
                echo "NOT FOUND"
            fi
            echo "Cluster status:"
            pcs status 2>/dev/null || echo "Failed to get cluster status"
            echo "Process list:"
            ps aux | grep -E 'watchdog|heartbeat|pcs|pacemaker|corosync|nfs'
            echo "Last 20 lines from system log:"
            tail -n 20 /var/log/messages 2>/dev/null || journalctl -n 20 2>/dev/null
            echo "-------- END DIAGNOSTIC INFO --------"
        } >> "${LOG_FILE}.diagnostics.$(date +%s)"
    fi
}

# Function to update this node's state file (heartbeat) in the NFS witness directory.
update_state() {
    local status="$1"  # "active" or "standby"
    local now
    now=$(date +%s)

    # Verify if NFS is mounted
    if ! check_nfs_mounted "${NFS_WITNESS_DIR}"; then
        log "error" "Cannot update state file: NFS not mounted at ${NFS_WITNESS_DIR}"
        return 1
    fi

    # Ensure directory exists
    mkdir -p "${NFS_WITNESS_DIR}" 2>/dev/null

    # Write the state file with error redirection
    log "info" "Attempting to update state file to '$status' with timestamp $now"
    if ! cat > "$SELF_STATE_FILE" 2>/dev/null <<EOF
{
    "hostname": "$HOSTNAME",
    "last_update": $now,
    "status": "$status"
}
EOF
    then
        log "error" "Failed to write to state file: $SELF_STATE_FILE"
        return 1
    fi

    # Verify file exists
    if [ ! -f "$SELF_STATE_FILE" ]; then
        log "error" "State file does not exist after writing: $SELF_STATE_FILE"
        return 1
    fi

    # Verify content is correct
    local stored_timestamp
    stored_timestamp=$(grep '"last_update":' "$SELF_STATE_FILE" 2>/dev/null | sed 's/[^0-9]*//g')
    if [ -z "$stored_timestamp" ]; then
        log "error" "Cannot read timestamp from state file after writing"
        return 1
    elif [ "$stored_timestamp" != "$now" ]; then
        log "error" "Timestamp in file does not match: expected=$now, actual=$stored_timestamp"
        return 1
    fi

    log "info" "State file successfully updated to '$status' with timestamp $now"
    return 0
}

# Function to check connectivity to the Gateway (using ping)
check_gateway() {
    ping -c 1 -W 2 "$GATEWAY" > /dev/null 2>&1
    return $?
}

# Function to check if the Arbitrator responds on SSH (port 22) using netcat
check_arbitrator() {
    nc -z -w3 "$ARBITRATOR" 22 > /dev/null 2>&1
    return $?
}

# Function to check if NFS directory is actually mounted
check_nfs_mounted() {
    local mount_point="$1"
    # Use findmnt to check if the directory is actually mounted
    findmnt -t nfs,nfs4 "$mount_point" > /dev/null 2>&1
    return $?
}

# Improved function to check NFS read/write capability
check_nfs_rw() {
    local test_file="${NFS_WITNESS_DIR}/${WITNESS_FILE}"

    # First check if NFS is actually mounted
    if ! check_nfs_mounted "${NFS_WITNESS_DIR}"; then
        log "warning" "NFS mount point ${NFS_WITNESS_DIR} is not mounted"
        return 1
    fi

    # Get the device ID of the mount point and parent directory
    local mount_dev=$(stat -c %d "${NFS_WITNESS_DIR}" 2>/dev/null)
    local parent_dev=$(stat -c %d "$(dirname "${NFS_WITNESS_DIR}")" 2>/dev/null)

    # If they're the same, the directory is not a mount point
    if [ "$mount_dev" = "$parent_dev" ]; then
        log "warning" "NFS mount point ${NFS_WITNESS_DIR} is not a separate filesystem"
        return 1
    fi

    # Try to write to the file
    echo "test" > "$test_file" 2>/dev/null
    if [ $? -ne 0 ]; then
        log "warning" "Cannot write to NFS mount ${NFS_WITNESS_DIR}"
        return 1
    fi

    # Try to read from the file
    grep -q "test" "$test_file" 2>/dev/null
    if [ $? -ne 0 ]; then
        log "warning" "Cannot read from NFS mount ${NFS_WITNESS_DIR}"
        rm -f "$test_file" 2>/dev/null
        return 1
    fi

    # Clean up
    rm -f "$test_file"
    return 0
}

# Function to check the freshness of the peer's state file on NFS.
check_peer_state() {
    if [ ! -f "$OTHER_STATE_FILE" ]; then
        log "warning" "Peer state file ($OTHER_STATE_FILE) does not exist."
        return 1
    fi

    local other_timestamp
    other_timestamp=$(grep '"last_update":' "$OTHER_STATE_FILE" | sed 's/[^0-9]*//g')
    if [ -z "$other_timestamp" ]; then
        log "warning" "Failed to parse peer timestamp from $OTHER_STATE_FILE."
        return 1
    fi

    local now diff
    now=$(date +%s)
    diff=$((now - other_timestamp))
    log "info" "Peer state file is $diff seconds old (threshold: $STATE_THRESHOLD)."
    if [ $diff -le $STATE_THRESHOLD ]; then
        return 0
    else
        return 1
    fi
}

# Function to determine if this node is active.
is_active_node() {
    if pcs status nodes | grep "$HOSTNAME" | grep -i "Standby"; then
        return 1  # Nodo en standby
    else
        return 0  # Nodo activo
    fi
}

# Functions to record and clear NFS failure timestamps.
record_nfs_failure() {
    if [ ! -f "$NFS_FAILURE_FILE" ]; then
        date +%s > "$NFS_FAILURE_FILE"
    fi
}

clear_nfs_failure() {
    if [ -f "$NFS_FAILURE_FILE" ]; then
        rm -f "$NFS_FAILURE_FILE"
    fi
}

# Function to get the duration since the first NFS failure was recorded.
get_nfs_failure_duration() {
    if [ -f "$NFS_FAILURE_FILE" ]; then
        local start_time now duration
        start_time=$(cat "$NFS_FAILURE_FILE")
        now=$(date +%s)
        duration=$((now - start_time))
        echo "$duration"
    else
        echo "0"
    fi
}

# Run connectivity tests
check_gateway && gateway_status=0 || gateway_status=1
check_arbitrator && arbitrator_status=0 || arbitrator_status=1
check_nfs_rw && nfs_status=0 || nfs_status=1

log "info" "Status check: Gateway=${gateway_status}, Arbitrator=${arbitrator_status}, NFS=${nfs_status}"

# Update the state file at the beginning if NFS is accessible
if [ $nfs_status -eq 0 ]; then
    # Get the current node status from the cluster
    if pcs status nodes | grep "$HOSTNAME" | grep -i "Standby"; then
        log "info" "Node is in standby according to the cluster, updating state"
        update_state "standby"

        # If node is in standby but not in maintenance, and NFS is available, try to take it out of standby
        if ! pcs status nodes | grep "$HOSTNAME" | grep -i "maintenance"; then
            log "notice" "Node is in standby but not in maintenance, and NFS is available. Attempting to remove standby."
            if pcs node unstandby "$HOSTNAME"; then
                log "notice" "Successfully removed standby from node $HOSTNAME"
                update_state "active"
                log "notice" "State updated to active after removing standby"
            else
                log "error" "Error trying to remove standby from node $HOSTNAME"

                # Try an alternative command if the first one fails
                if pcs cluster unstandby "$HOSTNAME" 2>/dev/null; then
                    log "notice" "Successfully removed standby using alternative command"
                    update_state "active"
                    log "notice" "State updated to active after removing standby"
                fi
            fi
        else
            log "info" "Node is in maintenance mode, not attempting to remove standby"
        fi
    else
        log "info" "Node is active according to the cluster, updating state"
        update_state "active"
    fi
fi

if [ $nfs_status -eq 0 ]; then
    clear_nfs_failure
else
    record_nfs_failure
fi

# Determine node role based on its actual cluster state
is_active_node
if [ $? -eq 0 ]; then
    # Active node logic
    log "info" "Node is active."
    if [ $gateway_status -eq 0 ] && [ $arbitrator_status -eq 0 ] && [ $nfs_status -eq 0 ]; then
        log "info" "Active node: Gateway, Arbitrator, and NFS are operational. No action required."
    else
        duration=$(get_nfs_failure_duration)
        log "warning" "Active node: NFS failure detected for $duration seconds."
        if [ "$duration" -ge "$ACTIVE_NFS_FAILURE_THRESHOLD" ]; then
            log "notice" "Active node: NFS failure exceeded threshold. Transitioning to standby."
            pcs node standby "$HOSTNAME"
            # We don't update state here because NFS is not available
        fi
    fi
else
    # Standby node logic
    log "info" "Node is standby."
    if [ $gateway_status -eq 0 ] && [ $arbitrator_status -eq 0 ] && [ $nfs_status -eq 0 ]; then
        log "info" "Standby node: Connectivity is healthy."
        if check_peer_state; then
            log "info" "Standby node: Peer state is up-to-date. Remaining in standby."
        else
            log "notice" "Standby node: Peer state is stale. Attempting to acquire cluster resources."
            pcs node unstandby "$HOSTNAME"
            pcs stonith fence "$OTHER_NODE"
            update_state "active"
        fi
    else
        duration=$(get_nfs_failure_duration)
        log "warning" "Standby node: NFS failure detected for $duration seconds."
        if [ "$duration" -ge "$STANDBY_NFS_FAILURE_THRESHOLD" ]; then
            log "alert" "Standby node: NFS failure exceeded threshold (${duration}s > ${STANDBY_NFS_FAILURE_THRESHOLD}s). WOULD REBOOT node."
            log "alert" "*** IMPORTANT: Recording diagnostic information before potential reboot ***"
            # Save complete cluster status
            pcs status > "${LOG_FILE}.preboot_cluster_status.$(date +%s)" 2>/dev/null
            # Detailed log of critical services
            systemctl status watchdog heartbeat-updater network-watchdog pcsd corosync pacemaker > "${LOG_FILE}.preboot_services.$(date +%s)" 2>/dev/null

            # Try to resolve the issue before rebooting
            log "notice" "Attempt recovery: Forcing resource cleanup"
            pcs resource cleanup 2>/dev/null || true

            # Wait 30 seconds to see if recovery works
            log "notice" "Waiting 30 seconds to see if cleanup resolves the issue..."
            sleep 30

            # Check if the problem persists
            if check_nfs_rw; then
                log "notice" "NFS is now accessible after cleanup! Aborting reboot."
                clear_nfs_failure
            else
                log "alert" "NFS still unavailable after cleanup. Will reboot in 10 seconds unless interrupted."
                sleep 10
                log "emerg" "REBOOTING NODE due to persistent NFS failure"
                /sbin/reboot -f
            fi
        fi
    fi
fi

exit 0
```
