# MonitorIotaNodeLog

This shellscript can monitor your iota-core docker log for any new unique error and will automatically sent a push notification if found.

# Pre-requisites

You need a one time lifetime [Pushover license](https://pushover.net/pricing) per platform (Android, iPhone, iPad, and Desktop (Android Wear and Apple Watch, too!)) where you want to receive push notifications on for only $5,-

# Installation
1. Clone the repo: `git clone https://github.com/JannemanDev/MonitorIotaNodeLog.git`
2. Copy `settings.conf.example` to `settings.conf` and adjust it. Mandatory to change are the pushover settings.
3. Run `runMonitorIotaNodeLogInBackground.sh` and it will run in the background as a screen under sudo since `docker logs` command needs sudo.

After that you can see and go back to the screen using:  
List screens: `sudo screen -ls`  
Restore screen: `sudo screen -r MonitorIotaNodeLog`  

If you want to detach again and continue running in background use `Ctrl+a d`
