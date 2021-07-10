# backup-cr ![static build x86_84](https://github.com/foi/backup-cr/actions/workflows/ci.yml/badge.svg)

development in progress

## HOW TO INSTALL

### Deb-like

```
sudo su
apt install -y apt-transport-https
echo -e "deb https://repos.foifirst.me/backup-cr/debs stable main" > /etc/apt/sources.list.d/backup-cr.list
wget -O - https://repos.foifirst.me/foi.gpg | apt-key add -
apt update
apt install backup-cr

```
### RPM-like

```

```

## FEATURES

0. single executable with no dependencies
1. backup files, lvm volumes, docker volumes with configurable gzip compression level
2. save it to local path or remote path via sshfs and public key auth
3. ability to custom hook for events
4. ACL based on ip-adresses
5. custom backup extension (simple ransomware protection)
6. config via ENV variables or .env file

## Installation

# server

  1. create group with fixed group id: sudo groupadd -g 5000 backup-files
  2. create user with fixed id: sudo useradd -u 5000 -m -G backup-files backup-worker
  3. chown -R backup-worker:backup-files backup-files

# backup fileserver

  1. create group with fixed group id: sudo groupadd -g 5000 backup-files
  2. create user with fixed id: sudo useradd -u 5000 -m -G backup-files backup-worker
  3. chown -R backup-worker:backup-files PATH_TO_BACKUP_FILES

# client

## Usage

TODO: Write usage instructions here

## TODO

* Should work without lvm
* web ui

## Contributing

1. Fork it (<https://github.com/foi/backup-cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [foi](https://github.com/foi) - creator and maintainer
