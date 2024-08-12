# MonitorIotaNodeLog

This shellscript can monitor your iota-core docker log for any new unique error and will automatically sent a push notification if found. It also monitor the health of the iota-core container and node itself and inx-indexer.
It's customizable so you monitor for certain keywords or even regex patterns. It will only sent a push when a new type of log item matches and when containers or node health changes.
Also at startup and shutdown a push message is sent with some general info.

You can run multiple instances so you can monitor multiple containers and nodes. Just use a different settings file and use it as commandline argument.

After running you can find all unique errors per node (identity) in the specified `TMP_DIR`.
For the first round when it checks the log you can specify with `TIME_WINDOW_FIRST_ROUND` a different timespan to search the log for certain `SEARCH_WORDS` (for example errors).
After first round it will re-check the log every specified `LOOP_FREQUENCY`.
See `Settings` section below for more details and default values.

# Pre-requisites

You need a one time lifetime [Pushover license](https://pushover.net/pricing) per platform (Android, iOS (iPhone/iPad), and Desktop (Android Wear and Apple Watch, too!)) where you want to receive push notifications on for only $5,-

# Installation
1. Clone the repo: `git clone https://github.com/JannemanDev/MonitorIotaNodeLog.git`
2. Copy `settings.conf.example` to `settings.conf` and adjust it. Mandatory to change are the pushover settings.
3. Run `runMonitorIotaNodeLogInBackground.sh` and it will run in the background as a screen under sudo since `docker logs` command needs sudo.

After that you can see and go back to the screen using:  
List screens: `sudo screen -ls`  
Restore screen: `sudo screen -r MonitorIotaNodeLog`  

If you want to detach again and continue running in background use `Ctrl+a d`

# Settings

```shellscript
# Pushover settings
PUSHOVER_USER_KEY=""
PUSHOVER_APP_TOKEN=""

# Format for Time Window, Loop Frequency and Health Check settings:
#   [s|m|h|d] (seconds, minutes, hours, days)
# Set the time span to read from the docker logs for (only) the first round
# If empty whole log will be read
TIME_WINDOW_FIRST_ROUND="1d"

# Check docker log frequency. After this timespan the docker log will be read again.
LOOP_FREQUENCY="2m"

# Health check frequency for iota-core and inx-indexer
HEALTH_CHECK_FREQUENCY="5s"

# Push notification limits
MAX_PUSH_NOTIFICATIONS_PER_ROUND=5
MAX_PUSH_NOTIFICATIONS_TOTAL=100

# Temporary files directory
TMP_DIR="./tmp"

# Search words (regex is allowed)
SEARCH_WORDS=("error" "fail" "critical" "warning" "panic")
#SEARCH_WORDS=("error")

# Docker container names
CORE_DOCKER_CONTAINER_NAME="iota-core"
INDEXER_DOCKER_CONTAINER_NAME="inx-indexer"

# SED patterns to generalize all filtered log lines that contain SEARCH_WORDS
SED_PATTERNS=(
    's/\b[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\s+//g'
    's/\(0x[a-fA-F0-9]+:[0-9]+\)//g'
    's/P2P\.peer[0-9]+/P2P.peerX/g'
    's/peerID: [a-zA-Z0-9]+/peerID: xxx/g'
    's/[0-9A-Za-z]{52}/xxx/g'
    's/\/dns\/[^ ]+/\/dns\/xxx/g'
    's/\/ip4\/[^ ]+/\/ip4\/xxx/g'
    's/\/ip6\/[^ ]+/\/ip6\/xxx/g'
    's/with slot [0-9]+/with slot xxx/g'
    's/([0-9]{1,3}.){3}[0-9]{1,3}:[0-9]{1,5}/x.x.x.x:y/g'
    's/\[[0-9]+.[0-9]+ms\]/[x ms]/g'
    's/\[rows:[0-9]+\]/[rows: x]/g'
    's/\(.+?,.+?,.+?,.+?,.+?,.+?\)/(x,x,x,x,x,x)/g'
    's/\(max [0-9]+ seconds\)/\(max x seconds\)/g'
)
```
