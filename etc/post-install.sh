#!/usr/bin/env sh
ENV_FILE=/opt/backup-cr/.env
CUSTOM_FILE=/opt/backup-cr/custom.env
if [ ! -f $ENV_FILE ]; then
  cp "$ENV_FILE".local.example $ENV_FILE
fi
if [ ! -f $CUSTOM_FILE ]; then
  cp "$CUSTOM_FILE".example $CUSTOM_FILE
fi
chmod 600 $ENV_FILE
chmod 600 $CUSTOM_FILE
if groupadd backup-files && useradd -m -G backup-files backup-worker; then
  echo "User and group created successfully."
else
  echo "Failed to create backup-files group and backup-worker user - maybe it's already exists"
fi

if [ -x "$(command -v systemctl)" ];
then
  systemctl daemon-reload
  systemctl start backup-cr
  if systemctl is-active --quiet backup-cr
  then
    systemctl restart backup-cr
  else 
    systemctl enable --now backup-cr
  fi
fi

