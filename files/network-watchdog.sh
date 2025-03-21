#!/bin/bash

# Set full PATH to access all commands
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Get the second node from /etc/hosts file
OTHER_NODE=$(/bin/grep -v $(/bin/hostname) /etc/hosts | /bin/grep -v localhost | /bin/grep -v virtual-ip | /usr/bin/head -1 | /usr/bin/awk '{print $1}')
GATEWAY_IP=$(/usr/sbin/ip route | /bin/grep default | /usr/bin/awk '{print $3}')

# Can I see the other node?
can_see_node=0
/bin/ping -c 1 -W 1 $OTHER_NODE > /dev/null 2>&1
if [ $? -eq 0 ]; then
    can_see_node=1
fi

# Can I see the gateway?
can_see_gateway=0
/bin/ping -c 1 -W 1 $GATEWAY_IP > /dev/null 2>&1
if [ $? -eq 0 ]; then
    can_see_gateway=1
fi

# Check application service status
app_ok=0
/usr/bin/systemctl is-active --quiet myapp && app_ok=1

# Check if resources are on this node
resources_active=0
/usr/sbin/pcs status | /bin/grep -A 20 "Resources" | /bin/grep -q "$(/bin/hostname)" && resources_active=1

# Check if cluster is in maintenance mode
maintenance_mode=0
/usr/sbin/pcs property config | /bin/grep -q "maintenance-mode: true" && maintenance_mode=1

# Check if this node is in standby
standby_mode=0
/usr/sbin/pcs status | /bin/grep "$(/bin/hostname)" | /bin/grep -q "standby" && standby_mode=1

# Do nothing if cluster is in maintenance or node in standby
if [ $maintenance_mode -eq 1 ] || [ $standby_mode -eq 1 ]; then
    /usr/bin/logger -p daemon.notice "Cluster in maintenance or node in standby. No action taken."
    exit 0
fi

# CASE 1: Network problems but services running
if [ $can_see_node -eq 0 ] && [ $can_see_gateway -eq 1 ]; then
    /usr/bin/logger -p daemon.notice "Can't see the other node but can see the gateway. The other node is probably down."
    # In this case stay active because it seems the other node is down
fi

# CASE 2: Network isolation (can't see node or gateway)
if [ $can_see_node -eq 0 ] && [ $can_see_gateway -eq 0 ] && [ $resources_active -eq 1 ]; then
    /usr/bin/logger -p daemon.alert "ALERT! I'm isolated from the network and have active resources. Rebooting."
    # Request reboot without using watchdog directly
    /usr/bin/systemctl reboot
fi

# CASE 3: Application service down while resources are active
if [ $app_ok -eq 0 ] && [ $resources_active -eq 1 ]; then
    # Try to restart the service first
    /usr/bin/logger -p daemon.warning "Service myapp down, trying to restart..."
    /usr/bin/systemctl restart myapp
    /bin/sleep 10  # Wait for it to start
    
    # Check if it recovered
    if ! /usr/bin/systemctl is-active --quiet myapp; then
        /usr/bin/logger -p daemon.error "The myapp service could not recover. Notifying the cluster."
        # Try to move resources to the other node
        /usr/sbin/pcs resource failcount reset app_service
        /usr/sbin/pcs resource move app_service
        
        # If after trying to move resources, the service is still down, consider rebooting the node
        /bin/sleep 10
        if ! /usr/bin/systemctl is-active --quiet myapp && /usr/sbin/pcs status | /bin/grep -A 20 "Resources" | /bin/grep -q "$(/bin/hostname)"; then
            /usr/bin/logger -p daemon.alert "ALERT! Service myapp still down after attempting recovery. Initiating reboot."
            # Request reboot without using watchdog directly
            /usr/bin/systemctl reboot
        fi
    fi
fi

# We don't attempt to interact directly with the watchdog because it's already
# being managed by the system's watchdog service
exit 0
