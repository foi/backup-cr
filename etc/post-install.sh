#!/bin/sh
FILE=/opt/backup-cr/.env
CUSTOM_FILE=/opt/backup-cr/custom.env
if [ ! -f $FILE ]; then
  cp /opt/backup-cr/.env.local.example /opt/backup-cr/.env
fi
if [ ! -f $CUSTOM_FILE ]; then
  cp /opt/backup-cr/custom.env.example /opt/backup-cr/custom.env
fi
if groupadd -g 5000 backup-files && useradd -u 5000 -m -G backup-files backup-worker; then
  echo "User and group created successfully."
else
  echo "Failed to create backup-files group and backup-worker user - maybe it's already exists"
fi
systemctl daemon-reload
systemctl enable --now backup-cr