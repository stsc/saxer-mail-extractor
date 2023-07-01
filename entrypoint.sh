#!/bin/sh

# Copy crontab file to the cron.d directory
cp /config/crontab /etc/cron.d/crontab
# Give execution rights on the cron job
chmod 0644 /etc/cron.d/crontab
# Apply cron job
crontab /etc/cron.d/crontab
# execute cron in foreground mode
cron -f || exit 1

