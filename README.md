# backup-cr ![static build x86_84](https://github.com/foi/backup-cr/actions/workflows/ci.yml/badge.svg)

development in progress

## HOW TO INSTALL

### Deb-like

```
sudo su
apt install -y apt-transport-https
echo -e "deb http://repos.foifirst.space/backup-cr/debs stable main" > /etc/apt/sources.list.d/backup-cr.list
wget -O - http://repos.foifirst.space/foi.gpg | apt-key add -
apt update
apt install backup-cr

```
### RPM-like

```
sudo su
cat << EOF > /etc/yum.repos.d/backup-cr.repo
[backup-cr]
name=backup-cr repo
baseurl=http://repos.foifirst.space/backup-cr/rpms
enabled=1
gpgcheck=1
skip_if_unavailable=1
gpgkey=http://repos.foifirst.space/foi.gpg
EOF
yum install backup-cr
```

## FEATURES

0. single executable with no dependencies
1. backup files, lvm volumes, docker volumes with configurable gzip compression level
2. save it to local path or remote path via sshfs and public key auth
3. ability to custom hook for events
4. ACL based on ip-adresses
5. custom backup extension (simple ransomware protection)
6. config via ENV variables or .env file

## Contributors

- [foi](https://github.com/foi) - creator and maintainer
