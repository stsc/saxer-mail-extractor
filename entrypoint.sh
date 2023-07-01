#!/bin/bash

# turn on bash's job control
set -m

# config example handling
if [ ! -r /config/crontab ] ; then
	cp /config.example/crontab /config/crontab
else
	echo "config/crontab not readable! exiting..."
	exit 1
fi
if [ ! -r /config/mail_extractor.cfg ] ; then
	cp /config.example/mail_extractor.cfg /config/mail_extractor.cfg
else
	echo "config/mail_extractor.cfg not readable! exiting..."
	exit 1
fi

# Copy crontab file to the cron.d directory
cp /config/crontab /etc/cron.d/crontab
# Give execution rights on the cron job
chmod 0644 /etc/cron.d/crontab
# Apply cron job
crontab /etc/cron.d/crontab
# execute cron in foreground mode and put it in background
cron -f &
# wait for all processes to exit
wait -n
# Exit with status of process that exited first
exit $?
