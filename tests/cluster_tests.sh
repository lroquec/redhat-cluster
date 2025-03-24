#!/bin/bash
#
# HA Cluster Test Script
# This script performs tests on the HA cluster configuration to verify its functionality
# It connects to nodes remotely when needed to perform the verification
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Node information - Edit these to match your environment
NODE1="192.168.6.45"  # Directly using IPs instead of hostnames
NODE2="192.168.6.46"
SSH_USER="root" # Change to the appropriate user for SSH connections

# Function to execute command with SSH and return result
ssh_get_output() {
    local node=$1
    local cmd=$2
    ssh -q ${SSH_USER}@${node} "$cmd"
}

# Function to print section headers
print_header() {
    echo -e "\n${BLUE}==== $1 ====${NC}\n"
}

# Function to check command status and print result
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ PASS: $1${NC}"
        return 0
    else
        echo -e "${RED}✗ FAIL: $1${NC}"
        return 1
    fi
}

# Function to run command on a remote node
run_on_node() {
    local node=$1
    local cmd=$2
    
    echo -e "${YELLOW}! Running on $node: $cmd${NC}"
    ssh ${SSH_USER}@${node} "$cmd"
    return $?
}

# Function to test connectivity to nodes
test_connectivity() {
    print_header "Testing Node Connectivity"
    
    # Test SSH to node1
    ssh -q -o BatchMode=yes -o ConnectTimeout=5 ${SSH_USER}@${NODE1} exit
    check_status "SSH connection to ${NODE1}"
    
    # Test SSH to node2
    ssh -q -o BatchMode=yes -o ConnectTimeout=5 ${SSH_USER}@${NODE2} exit
    check_status "SSH connection to ${NODE2}"
    
    # Get Virtual IP from the cluster configuration
    echo -e "${YELLOW}! Connecting to ${NODE1} to get Virtual IP...${NC}"
    
    # Try to extract the Virtual IP from pcs status output
    VIRTUAL_IP=$(ssh_get_output ${NODE1} "pcs status resources | grep -i 'virtual_ip' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'")
    
    # If that fails, try to get it from cluster resource configuration
    if [ -z "$VIRTUAL_IP" ]; then
        VIRTUAL_IP=$(ssh_get_output ${NODE1} "pcs resource config virtual_ip | grep -oE 'ip=[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | cut -d= -f2")
    fi
    
    # If both methods fail, prompt for manual entry
    if [ -z "$VIRTUAL_IP" ]; then
        echo -e "${YELLOW}! Could not automatically determine Virtual IP${NC}"
        echo -e "${YELLOW}! Please enter the Virtual IP manually:${NC}"
        read -r VIRTUAL_IP
        if [ -z "$VIRTUAL_IP" ]; then
            echo -e "${RED}✗ FAIL: No Virtual IP provided${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✓ Using Virtual IP: ${VIRTUAL_IP}${NC}"
    
    # Test ping to Virtual IP
    ping -c 3 ${VIRTUAL_IP} &>/dev/null
    check_status "Ping to Virtual IP (${VIRTUAL_IP})"
}

# Function to test watchdog configuration on both nodes
test_watchdog() {
    print_header "Testing Watchdog Configuration"
    
    # Test on node1
    echo -e "${YELLOW}! Testing watchdog on ${NODE1}:${NC}"
    
    run_on_node ${NODE1} "systemctl is-active --quiet watchdog"
    check_status "Watchdog service is running on ${NODE1}"
    
    run_on_node ${NODE1} "test -f /var/run/arbitrator-heartbeat && [ \"\$(stat -c %a /var/run/arbitrator-heartbeat)\" = \"666\" ]"
    check_status "Heartbeat file exists with correct permissions on ${NODE1}"
    
    # Test on node2
    echo -e "${YELLOW}! Testing watchdog on ${NODE2}:${NC}"
    
    run_on_node ${NODE2} "systemctl is-active --quiet watchdog"
    check_status "Watchdog service is running on ${NODE2}"
    
    run_on_node ${NODE2} "test -f /var/run/arbitrator-heartbeat && [ \"\$(stat -c %a /var/run/arbitrator-heartbeat)\" = \"666\" ]"
    check_status "Heartbeat file exists with correct permissions on ${NODE2}"
    
    # Update heartbeat and check logs on both nodes
    run_on_node ${NODE1} "touch /var/run/arbitrator-heartbeat && sleep 2 && journalctl -u watchdog --since \"1 minute ago\" | grep -q \"file /var/run/arbitrator-heartbeat was last changed\""
    check_status "Watchdog recognized heartbeat file update on ${NODE1}"
    
    run_on_node ${NODE2} "touch /var/run/arbitrator-heartbeat && sleep 2 && journalctl -u watchdog --since \"1 minute ago\" | grep -q \"file /var/run/arbitrator-heartbeat was last changed\""
    check_status "Watchdog recognized heartbeat file update on ${NODE2}"
}

# Function to test cluster status
test_cluster_status() {
    print_header "Testing Cluster Status"
    
    # Run tests on node1
    echo -e "${YELLOW}! Checking cluster status from ${NODE1}:${NC}"
    
    # Check cluster status
    run_on_node ${NODE1} "pcs status &>/dev/null"
    check_status "Cluster status command works"
    
    # Get and show the actual online nodes text
    echo -e "${YELLOW}! Actual node list:${NC}"
    node_list=$(run_on_node ${NODE1} "pcs status | grep -A1 'Node List:' | grep 'Online:'")
    echo -e "${YELLOW}${node_list}${NC}"
    
    # Check if "node1" and "node2" are shown as online - fix the grep pattern
    run_on_node ${NODE1} "pcs status | grep -A1 'Node List:' | grep 'Online:' | grep -q 'node1' && pcs status | grep -A1 'Node List:' | grep 'Online:' | grep -q 'node2'"
    check_status "Both nodes are online"
    
    # Check if all resources are running
    run_on_node ${NODE1} "pcs status | grep -q \"virtual_ip\" && pcs status | grep -q \"fs_shared\" && pcs status | grep -q \"fence-kdump\""
    check_status "All expected resources are configured"
    
    # Check STONITH
    run_on_node ${NODE1} "pcs stonith status &>/dev/null"
    check_status "STONITH is configured"
    
    # Check if STONITH is enabled - get and display the actual property
    stonith_status=$(run_on_node ${NODE1} "pcs property config | grep stonith-enabled")
    echo -e "${YELLOW}! STONITH status: ${stonith_status}${NC}"
    
    # Now check based on what we see
    run_on_node ${NODE1} "pcs property config | grep stonith-enabled | grep -q true"
    check_status "STONITH is enabled"
    
    # Get and display full cluster status
    echo -e "${YELLOW}! Full cluster status:${NC}"
    run_on_node ${NODE1} "pcs status"
}

# Function to test virtual IP
test_virtual_ip() {
    print_header "Testing Virtual IP"
    
    # Get the current active node for virtual_ip - show the grep command and output for debugging
    echo -e "${YELLOW}! Checking which node has the virtual IP...${NC}"
    resources_output=$(run_on_node ${NODE1} "pcs status resources")
    echo -e "${YELLOW}! Resources output:${NC}"
    echo "$resources_output"
    
    virtual_ip_line=$(echo "$resources_output" | grep -i "virtual_ip")
    echo -e "${YELLOW}! Virtual IP line: $virtual_ip_line${NC}"
    
    active_node=""
    if echo "$virtual_ip_line" | grep -q "Started.*node1"; then
        active_node="node1"
    elif echo "$virtual_ip_line" | grep -q "Started.*node2"; then
        active_node="node2"
    fi
    
    if [ -z "$active_node" ]; then
        echo -e "${RED}✗ FAIL: Could not determine which node has the virtual IP${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}! INFO: Virtual IP is currently on $active_node${NC}"
    
    # Figure out the IP of the active node
    if [ "$active_node" = "node1" ]; then
        active_node_ip=${NODE1}
    else
        active_node_ip=${NODE2}
    fi
    
    # Check if virtual IP is pingable
    ping -c 3 ${VIRTUAL_IP} &>/dev/null
    check_status "Virtual IP is pingable"
    
    # Check if the IP is configured on the active node
    run_on_node $active_node_ip "ip a | grep -q \"${VIRTUAL_IP}\""
    check_status "Virtual IP is configured on the interface of $active_node"
}

# Function to test NFS mounts
test_nfs_mounts() {
    print_header "Testing NFS Mounts"
    
    # Determine which node has the active resources
    resources_output=$(run_on_node ${NODE1} "pcs status resources")
    
    active_node=""
    active_node_ip=""
    if echo "$resources_output" | grep -i "fs_shared" | grep -q "Started.*node1"; then
        active_node="node1"
        active_node_ip=${NODE1}
    elif echo "$resources_output" | grep -i "fs_shared" | grep -q "Started.*node2"; then
        active_node="node2"
        active_node_ip=${NODE2}
    fi
    
    if [ -z "$active_node" ]; then
        echo -e "${RED}✗ FAIL: Could not determine which node has the active resources${NC}"
        echo -e "${YELLOW}! Resources output:${NC}"
        echo "$resources_output"
        return 1
    fi
    
    echo -e "${YELLOW}! NFS resources are active on $active_node ($active_node_ip)${NC}"
    
    # Check if the directories exist on the active node
    echo -e "${YELLOW}! Checking NFS mount directories on $active_node:${NC}"
    nfs_shared_exists=$(run_on_node $active_node_ip "test -d /opt/nfs-shared && echo 'yes' || echo 'no'")
    nfs_witness_exists=$(run_on_node $active_node_ip "test -d /opt/nfs-witness && echo 'yes' || echo 'no'")
    
    echo -e "${YELLOW}! NFS shared directory exists: ${nfs_shared_exists}${NC}"
    echo -e "${YELLOW}! NFS witness directory exists: ${nfs_witness_exists}${NC}"
    
    if [ "$nfs_shared_exists" = "no" ] || [ "$nfs_witness_exists" = "no" ]; then
        echo -e "${RED}✗ FAIL: NFS directories don't exist on $active_node${NC}"
        echo -e "${YELLOW}! Please verify the paths of your NFS mount points${NC}"
        
        # Attempt to discover actual mount points
        echo -e "${YELLOW}! Attempting to discover NFS mounts on $active_node:${NC}"
        run_on_node $active_node_ip "mount | grep nfs"
        
        # Skip the remaining NFS tests
        return 1
    fi
    
    # Test only on the active node
    echo -e "${YELLOW}! Testing NFS mounts on $active_node:${NC}"
    
    # Check if the filesystems are mounted
    run_on_node $active_node_ip "mount | grep -q \"/opt/nfs-shared\" && mount | grep -q \"/opt/nfs-witness\""
    check_status "NFS mounts are present on $active_node"
    
    # Show the actual mounts for reference
    echo -e "${YELLOW}! Actual mounts on $active_node:${NC}"
    run_on_node $active_node_ip "mount | grep nfs"
    
    # Check if we can write to NFS
    run_on_node $active_node_ip "echo \"test\" > /opt/nfs-witness/test_${active_node}.tmp && test -f /opt/nfs-witness/test_${active_node}.tmp && rm -f /opt/nfs-witness/test_${active_node}.tmp"
    check_status "Can write to NFS witness directory from $active_node"
    
    # Check for node state files, but first verify the path
    echo -e "${YELLOW}! Checking for state files in /opt/nfs-witness...${NC}"
    witness_files=$(run_on_node $active_node_ip "ls -la /opt/nfs-witness/ | grep -E 'node[0-9]+_state'")
    
    if [ -n "$witness_files" ]; then
        echo -e "${YELLOW}! Found files:${NC}"
        echo "$witness_files"
        echo -e "${GREEN}✓ PASS: Node state files exist on $active_node${NC}"
    else
        echo -e "${YELLOW}! No state files found with pattern 'node*_state*'${NC}"
        
        # Alternative check: look for any JSON files that might be state files
        echo -e "${YELLOW}! Looking for alternative state files (*.json)...${NC}"
        json_files=$(run_on_node $active_node_ip "ls -la /opt/nfs-witness/ | grep -E '\.json'")
        
        if [ -n "$json_files" ]; then
            echo -e "${YELLOW}! Found JSON files:${NC}"
            echo "$json_files"
            echo -e "${GREEN}✓ PASS: Found potential state files on $active_node${NC}"
        else
            echo -e "${RED}✗ FAIL: No state files found${NC}"
        fi
    fi
}

# Function to test failover
test_failover() {
    print_header "Testing Manual Failover"
    
    # Get the current active node for resources
    resources_output=$(run_on_node ${NODE1} "pcs status resources")
    echo -e "${YELLOW}! Resources output:${NC}"
    echo "$resources_output"
    
    virtual_ip_line=$(echo "$resources_output" | grep -i "virtual_ip")
    
    active_node=""
    if echo "$virtual_ip_line" | grep -q "Started.*node1"; then
        active_node="node1"
        active_node_ip=${NODE1}
        standby_node="node2"
        new_active_ip=${NODE2}
    elif echo "$virtual_ip_line" | grep -q "Started.*node2"; then
        active_node="node2"
        active_node_ip=${NODE2}
        standby_node="node1"
        new_active_ip=${NODE1}
    fi
    
    if [ -z "$active_node" ]; then
        echo -e "${RED}✗ FAIL: Could not determine active node${NC}"
        return 1
    fi
    
    # Determine standby target and new active node
    echo -e "${YELLOW}! INFO: Current active node is $active_node ($active_node_ip)${NC}"
    echo -e "${YELLOW}! INFO: Will fail over to $standby_node ($new_active_ip)${NC}"
    
    echo -e "${YELLOW}! WARNING: Will put $active_node in standby mode${NC}"
    echo -e "${YELLOW}! Press CTRL+C now to abort, or wait 5 seconds to continue${NC}"
    sleep 5
    
    # Put the active node in standby
    run_on_node ${NODE1} "pcs node standby $active_node"
    check_status "Put $active_node in standby mode"
    
    # Wait for resources to migrate
    echo -e "${YELLOW}! INFO: Waiting for resources to migrate (15 seconds)...${NC}"
    sleep 15
    
    # Check if resources moved to the other node
    resources_output_after=$(run_on_node ${NODE1} "pcs status resources")
    echo -e "${YELLOW}! Resources output after failover:${NC}"
    echo "$resources_output_after"
    
    if echo "$resources_output_after" | grep -i "virtual_ip" | grep -q "Started.*$standby_node"; then
        echo -e "${GREEN}✓ PASS: Resources successfully failed over to $standby_node${NC}"
    else
        echo -e "${RED}✗ FAIL: Resources did not fail over correctly${NC}"
    fi
    
    # Check if virtual IP is now on the new node
    run_on_node $new_active_ip "ip a | grep -q \"${VIRTUAL_IP}\""
    check_status "Virtual IP is configured on $standby_node after failover"
    
    # Put the node back online
    run_on_node ${NODE1} "pcs node unstandby $active_node"
    check_status "Put $active_node back online"
    
    # Final cluster status
    echo -e "${YELLOW}! INFO: Final cluster status:${NC}"
    run_on_node ${NODE1} "pcs status resources"
}

# Main execution
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}=== HA Cluster Configuration Test ===${NC}"
echo -e "${BLUE}=====================================${NC}"

# Display configuration
echo -e "${YELLOW}! Configuration:${NC}"
echo -e "${YELLOW}! - Node 1: ${NODE1}${NC}"
echo -e "${YELLOW}! - Node 2: ${NODE2}${NC}"
echo -e "${YELLOW}! - SSH User: ${SSH_USER}${NC}"
echo

# Test connectivity first
test_connectivity

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ FAIL: Could not connect to one or more nodes. Please check connectivity and SSH configuration.${NC}"
    exit 1
fi

# Run all tests
test_watchdog
test_cluster_status
test_virtual_ip
test_nfs_mounts

echo -e "\n${YELLOW}Do you want to test manual failover? This will temporarily disrupt services. (y/N)${NC}"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    test_failover
else
    echo -e "${YELLOW}Skipping failover test.${NC}"
fi

echo -e "\n${BLUE}=====================================${NC}"
echo -e "${BLUE}===== Test Execution Complete =======${NC}"
echo -e "${BLUE}=====================================${NC}"
