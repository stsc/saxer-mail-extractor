#!/bin/sh

# config example handling
[ ! -r /config/crontab ] && cp /config.example/crontab /config/crontab || exit 1
[ ! -r /config/mail_extractor.cfg ] && cp /config.example/mail_extractor.cfg  /config/mail_extractor.cfg || exit 1

# Copy crontab file to the cron.d directory
cp /config/crontab /etc/cron.d/crontab
# Give execution rights on the cron job
chmod 0644 /etc/cron.d/crontab
# Apply cron job
crontab /etc/cron.d/crontab
# execute cron in foreground mode
cron -f || exit 2

