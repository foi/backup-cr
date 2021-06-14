#!/bin/sh
# $1 - hostname, $2 - event, $3 - message
curl -s -X POST https://api.telegram.org/bot$TELEGRAM_BOT_ID/sendMessage -d chat_id=$TELEGRAM_CHANNEL_ID -d text="[BACKUP-CR] $1 / $2 - $3"