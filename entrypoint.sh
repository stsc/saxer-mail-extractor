#!/bin/bash

# turn on bash's job control
set -m

# config example handling
if [ ! -r /config/crontab ] ; then
	echo "no config/crontab, copy example config"
	cp /config.example/crontab /config/crontab
fi
if [ ! -r /config/mail_extractor.cfg ] ; then
	echo "no config/mail_extractor.cfg, copy example config"
	cp /config.example/mail_extractor.cfg /config/mail_extractor.cfg
fi

# Copy crontab file to the cron.d directory
cp /config/crontab /etc/cron.d/crontab
# Give execution rights on the cron job
chmod 0644 /etc/cron.d/crontab
# Apply cron job
crontab /etc/cron.d/crontab
# execute cron in foreground mode and put it in background
cron -f &
# execute nginx in foreground mode and put it in background
nginx -g 'daemon off;' &
# wait for all processes to exit
wait -n
# Exit with status of process that exited first
exit $?
