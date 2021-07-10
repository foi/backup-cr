#!/bin/sh
set -e
cd /mnt/remote-backup-cr-repo/debs/dists/stable/
rm -f Release && rm -f InRelease && rm -f Release.gpg
do_hash() {
    HASH_NAME=$1
    HASH_CMD=$2
    echo "$HASH_NAME:" >> Release
    for f in $(find -type f); do
        f=$(echo "$f" | cut -c3-) # remove ./ prefix
        if [ "$f" = "Release" ]; then
            continue
        fi
        echo " $(${HASH_CMD} ${f}  | cut -d" " -f1) $(wc -c $f)" >> Release
    done
}

cat << EOF > Release
Origin:backup-cr repo
Label: -
Suite: stable
Codename: stable
Version: 1.0
Architectures: amd64
Components: main
Description: simple backup system
Date: $(date -Ru)
EOF
do_hash "MD5Sum" "md5sum"
do_hash "SHA1" "sha1sum"
do_hash "SHA256" "sha256sum"