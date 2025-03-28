#!/bin/bash
# Post-installation monitoring script to detect and log reboots
# This script should be deployed and executed after role installation

LOG_DIR="/var/log/cluster_diagnostics"
MONITOR_LOG="$LOG_DIR/post_install_monitor.log"
mkdir -p "$LOG_DIR"

echo "Starting post-installation monitoring at $(date)" >> "$MONITOR_LOG"
echo "Uptime: $(uptime)" >> "$MONITOR_LOG"
echo "" >> "$MONITOR_LOG"

# Get initial data
echo "Initial cluster status at $(date):" >> "$MONITOR_LOG"
pcs status >> "$MONITOR_LOG" 2>&1
echo "" >> "$MONITOR_LOG"

echo "Initial watchdog status:" >> "$MONITOR_LOG"
systemctl status watchdog >> "$MONITOR_LOG" 2>&1
echo "" >> "$MONITOR_LOG"

echo "Initial heartbeat status:" >> "$MONITOR_LOG"
ls -la /var/run/arbitrator-heartbeat >> "$MONITOR_LOG" 2>&1
echo "" >> "$MONITOR_LOG"

# Set up monitor for 30 minutes
echo "Monitoring system for 30 minutes..." >> "$MONITOR_LOG"

# Create uptime check that runs every minute
for i in {1..30}; do
  sleep 60
  echo "Uptime check $i at $(date): $(uptime)" >> "$MONITOR_LOG"
  
  # Check if uptime is less than 60 seconds, which would indicate a reboot
  UPTIME_SECONDS=$(cat /proc/uptime | awk '{print $1}' | cut -d. -f1)
  if [ "$UPTIME_SECONDS" -lt 60 ]; then
    echo "REBOOT DETECTED at $(date)!" >> "$MONITOR_LOG"
    echo "System was rebooted less than 60 seconds ago" >> "$MONITOR_LOG"
    echo "Collecting post-reboot diagnostics..." >> "$MONITOR_LOG"
    
    {
      echo "===== POST-REBOOT DIAGNOSTICS ====="
      echo "Date: $(date)"
      echo "Uptime: $(uptime)"
      echo ""
      
      echo "===== LAST SYSTEM BOOT ====="
      who -b
      echo ""
      
      echo "===== SYSTEM LOGS AROUND REBOOT ====="
      journalctl -b -1 -n 100 2>/dev/null || echo "Previous boot logs not available"
      echo ""
      
      echo "===== CURRENT SERVICES STATUS ====="
      systemctl status watchdog heartbeat-updater network-watchdog pcsd corosync pacemaker
      echo ""
      
      echo "===== CLUSTER STATUS AFTER REBOOT ====="
      pcs status 2>/dev/null || echo "Failed to get cluster status"
      echo ""
    } >> "$MONITOR_LOG"
  fi
  
  # Check watchdog and heartbeat file every 5 minutes
  if [ $((i % 5)) -eq 0 ]; then
    echo "Periodic service check at $(date):" >> "$MONITOR_LOG"
    systemctl status watchdog >> "$MONITOR_LOG" 2>&1
    ls -la /var/run/arbitrator-heartbeat >> "$MONITOR_LOG" 2>&1
    echo "Cluster status:" >> "$MONITOR_LOG"
    pcs status >> "$MONITOR_LOG" 2>&1
    echo "" >> "$MONITOR_LOG"
  fi
done

echo "Monitoring complete at $(date)" >> "$MONITOR_LOG"
echo "Final system status:" >> "$MONITOR_LOG"
uptime >> "$MONITOR_LOG"
pcs status >> "$MONITOR_LOG" 2>&1
