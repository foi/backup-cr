require "./backup-cr/system-helpers"
require "./backup-cr/server"

module BackupCr
  include SystemHelpers
  include BackupCr::Web

  VERSION       = "0.5.3"
  CONFIG        = Hash(String, String).new
  CONFIG_FIELDS = {
    "BACKUP_CR_LISTEN_ON",
    "BACKUP_CR_PORT",
    "BACKUP_CR_HOST",
    "BACKUP_CR_USER",
    "BACKUP_CR_GROUP",
    "BACKUP_CR_PATH",
    "BACKUP_CR_DOCKER_VOLUME_BACKUP_PATH",
    "BACKUP_CR_VM_BACKUP_PATH",
    "BACKUP_CR_FILES_BACKUP_PATH",
    "BACKUP_CR_GZIP_COMPRESSION_LEVEL",
    "BACKUP_CR_KEEP_VERSIONS_COUNT",
    "BACKUP_CR_BACKUP_FILE_EXTENSION",
    "BACKUP_CR_ALLOWED_FROM_IPS",
    "BACKUP_CR_DEFAULT_SNAPSHOT_SIZE",
    "BACKUP_CR_DD_BS_SIZE",
    "BACKUP_CR_COMMAND",
  }
  QUEUE = Hash(String, Hash(String, String)).new
  PATHS = Hash(String, String | Nil).new

  if File.exists?(".env")
    puts ".env-file found. Reading config..."
    File.read(".env").split("\n").map { |e| e.split("=") }.each do |conf_el|
      if CONFIG_FIELDS.includes?(conf_el[0])
        CONFIG[conf_el[0].split("BACKUP_CR_")[1]] = conf_el[1]
      end
    end
    puts "Config reads successfully."
  else
    puts "Reading config from environment..."
    CONFIG_FIELDS.each do |field|
      if ENV[field]?
        CONFIG[field.split("BACKUP_CR_")[1]] = ENV[field]
      else
        STDERR.puts "Config field #{field} is missing."
      end
    end
    puts "Config reads successfully."
  end
  IS_LOCAL = CONFIG["HOST"]?.nil? ? true : false
  PATHS["PATH"] = CONFIG["PATH"]?
  PATHS["DOCKER_VOLUME_BACKUP_PATH"] = CONFIG["DOCKER_VOLUME_BACKUP_PATH"]?
  PATHS["FILES_BACKUP_PATH"] = CONFIG["FILES_BACKUP_PATH"]?
  PATHS["VM_BACKUP_PATH"] = CONFIG["VM_BACKUP_PATH"]?

  DOCKER = Process.find_executable("docker")
end

server = BackupCr::Web::Server.new
server.draw_routes
server.start
