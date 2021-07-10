#!/bin/sh
set -e
VERSION=0.5.2
echo "Clean packages..."
rm -f dist/packages/*.rpm
rm -f dist/packages/*.deb
echo "Static compile..."
docker run --rm -it -v "$PWD":/app -w /app crystallang/crystal:1.0.0-alpine crystal build --static --release src/backup-cr.cr -o /app/dist/bin/backup-cr
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
chmod -R 775 dist/tmp/opt/backup-cr
cp custom.env.example dist/tmp/opt/backup-cr/custom.env.example
echo "Creating rpm package..."
docker run --rm -it -v $PWD:/app -w /app/dist/packages foifirst/fpm:ruby2.4-fedora27 fpm -s dir -t rpm -C /app/dist/tmp --name backup-cr --version $VERSION --iteration 1 --after-install /app/etc/post-install.sh --before-install /app/etc/before-install.sh --description "Simple backup system" .
echo "Creating deb package..."
docker run --rm -it -v $PWD:/app -w /app/dist/packages foifirst/fpm:ruby2.4-fedora27 fpm -s dir -t deb -C /app/dist/tmp --name backup-cr --version $VERSION --iteration 1 --after-install /app/etc/post-install.sh --before-install /app/etc/before-install.sh --description "Simple backup system" --deb-no-default-config-files .
echo "Packages have been successfully builds"
cp dist/packages/*.rpm /mnt/remote-backup-cr-repo/rpms/
cp dist/packages/*.deb /mnt/remote-backup-cr-repo/debs/pool/main/
