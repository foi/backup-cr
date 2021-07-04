#!/usr/bin/env sh
FILE=/opt/backup-cr/.env
CUSTOM_FILE=/opt/backup-cr/custom.env
if [ ! -f $FILE ]; then
  cp /opt/backup-cr/.env.local.example $FILE
fi
if [ ! -f $CUSTOM_FILE ]; then
  cp /opt/backup-cr/custom.env.example $CUSTOM_FILE
fi
if groupadd -g 5000 backup-files && useradd -u 5000 -m -G backup-files backup-worker; then
  echo "User and group created successfully."
else
  echo "Failed to create backup-files group and backup-worker user - maybe it's already exists"
fi

if [ -x "$(command -v systemctl)" ];
then
  systemctl daemon-reload
  if systemctl is-active --quiet backup-cr
  then
    systemctl restart backup-cr
  else 
    systemctl enable --now backup-cr
  fi
fi

