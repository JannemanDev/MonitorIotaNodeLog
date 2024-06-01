# MonitorIotaNodeLog

This shellscript can monitor your iota-core docker log for any new unique error and will automatically sent a push notification if found.
Copy `settings.conf.example` to `settings.conf` and adjust it. Mandatory to change are the pushover settings.
Then just run `runMonitorIotaNodeLogInBackground.sh` and it will run in the background as a screen under sudo since `docker logs` command needs sudo.

After that you can see and go back to the screen using:
List screens: `sudo screen -ls`
Restore screen: `sudo screen -r MonitorIotaNodeLog`

If you want to detach again and continue running in background use `Ctrl+a d`
