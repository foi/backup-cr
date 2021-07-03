#!/bin/sh
if [ -x "$(command -v systemctl)" ];
then
  if systemctl is-active --quiet backup-cr;
  then
    systemctl stop backup-cr
  fi
fi