#!/bin/bash

# Start the monitor script in a detached screen session
sudo screen -d -m -S MonitorIotaNodeLog ./monitorIotaNodeLog.sh

# Detach from Linux Screen Session: Ctrl+a d
# List screens: sudo screen -ls
# Restore screen: sudo screen -r MonitorIotaNodeLog
