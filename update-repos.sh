#!/bin/sh
set -e
REPO_PATH=$PWD
export GPG_TTY=$(tty)
rpm --addsign /mnt/remote-backup-cr-repo/rpms/*.rpm
createrepo_c --update /mnt/remote-backup-cr-repo/rpms/
cd /mnt/remote-backup-cr-repo/debs
dpkg-scanpackages --arch amd64 pool/ > /mnt/remote-backup-cr-repo/debs/dists/stable/main/binary-amd64/Packages
cat < /mnt/remote-backup-cr-repo/debs/dists/stable/main/binary-amd64/Packages | gzip -9 > /mnt/remote-backup-cr-repo/debs/dists/stable/main/binary-amd64/Packages.gz
cd "$REPO_PATH"
./generate-deb-release-file.sh
cd /mnt/remote-backup-cr-repo/debs/dists/stable/
cat < Release | gpg -abs --clearsign > InRelease
cat < Release | gpg -abs > Release.gpg
