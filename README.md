# backup-cr

TODO: Write a description here

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

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/foi/backup-cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [foi](https://github.com/foi) - creator and maintainer
