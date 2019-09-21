#!/bin/sh
set -e
echo "Clean packages..."
rm -f dist/packages/*.rpm
rm -f dist/packages/*.deb
echo "Static compile..."
docker run --rm -it -v $PWD:/app -w /app jrei/crystal-alpine crystal build --static --release src/backup-cr.cr -o /app/dist/bin/backup-cr
echo "Compiled successfully"
chmod +x dist/bin/backup-cr
mkdir -p dist/tmp/usr/lib/systemd/system
mkdir -p dist/tmp/opt/backup-cr
mv dist/bin/backup-cr dist/tmp/opt/backup-cr
cp send-to-telegram-channel.sh dist/tmp/opt/backup-cr/send-to-telegram-channel.sh.example
cp .env.remote.example dist/tmp/opt/backup-cr
cp .env.local.example dist/tmp/opt/backup-cr
cp etc/backup-cr.service dist/tmp/usr/lib/systemd/system
touch dist/tmp/opt/backup-cr/custom.env.example
echo $'TELEGRAM_CHANNEL_ID=changeme\nTELEGRAM_BOT_ID=changeme' > dist/tmp/opt/backup-cr/custom.env.example
date=$(date '+%Y.%m.%d')
echo "Creating rpm package..."
docker run --rm -it -v $PWD:/app -w /app/dist/packages foifirst/fpm:ruby2.4-fedora27 fpm -s dir -t rpm -C /app/dist/tmp --name backup-cr --version $date --iteration 1 --after-install /app/etc/post-install.sh --description "Agile lvm volumes backup system" .
echo "Creating deb package..."
docker run --rm -it -v $PWD:/app -w /app/dist/packages foifirst/fpm:ruby2.4-fedora27 fpm -s dir -t deb -C /app/dist/tmp --name backup-cr --version $date --iteration 1 --after-install /app/etc/post-install.sh --description "Agile lvm volumes backup system" --deb-no-default-config-files .
echo "Packages has been successfully builds"