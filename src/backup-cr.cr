# Hack to prevent a segfault for static linking
{% if flag?(:static) %}
  require "llvm/lib_llvm"
  require "llvm/enums"
{% end %}

require "router"
require "json"

class BackupCrServer
  include Router

  @@io = IO::Memory.new

  @@docker = true

  @@QUEUE = Hash(String, Hash(String, String)).new

  @@CONFIG_FIELDS = [
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
    "BACKUP_CR_STATS_ALLOWED_FROM_IPS",
    "BACKUP_CR_BACKUP_ALLOWED_FROM_IPS",
    "BACKUP_CR_DEFAULT_SNAPSHOT_SIZE",
    "BACKUP_CR_DD_BS_SIZE",
    "BACKUP_CR_COMMAND",
  ]

  def initialize
    @CONFIG = Hash(String, String).new

    if File.exists?(".env")
      puts ".env-file found. Reading config..."
      File.read(".env").split("\n").map { |e| e.split("=") }.each do |conf_el|
        if @@CONFIG_FIELDS.includes?(conf_el[0])
          @CONFIG[conf_el[0].split("BACKUP_CR_")[1]] = conf_el[1]
        end
      end
      puts "Config reads successfully."
    else
      puts "Reading config from environment..."
      @@CONFIG_FIELDS.each do |field|
        if ENV[field]?
          @CONFIG[field.split("BACKUP_CR_")[1]] = ENV[field]
        else
          STDERR.puts "Config field #{field} is missing."
        end
      end
      puts "Config reads successfully."
    end
    @IS_LOCAL = @CONFIG["HOST"]?.nil? ? true : false
    check_id_rsa
    check_executables
    check_group(@CONFIG["GROUP"])
    check_user(@CONFIG["USER"], @CONFIG["GROUP"])
    send_to_external_command("backup-cr started", "#{Time.local}")
  end

  private def check_id_rsa
    unless @IS_LOCAL
      unless File.exists?("./id_rsa")
        STDERR.puts "id_rsa is not found; please generate with ssh-keygen (without passphrase!)"
        exit(1)
      end
    end
  end

  def draw_routes
    get "/api/lvm_structure" do |context, params|
      if @CONFIG["STATS_ALLOWED_FROM_IPS"].split(",").includes?(get_ip(context))
        context.response.content_type = "application/json"
        context.response.print get_lvm_structure.to_json
        context
      else
        restrict(context)
      end
    end

    get "/api/vm_list" do |context, params|
      if @CONFIG["STATS_ALLOWED_FROM_IPS"].split(",").includes?(get_ip(context))
        context.response.content_type = "application/json"
        vm_data = get_vm_list.map do |vm|
          {"vm" => vm, "disks" => get_vm_disks(vm).not_nil!}
        end
        context.response.print vm_data.to_json
        context
      else
        restrict(context)
      end
    end

    get "/" do |context, params|
      if @CONFIG["STATS_ALLOWED_FROM_IPS"].split(",").includes?(get_ip(context))
        context.response.content_type = "text/html"
        # https://github.com/crystal-lang/crystal/issues/1649
        # context.response.print {{ `cat #{__DIR__}/../index.html`.stringify }}
        context.response.print File.read("index.html")
        context
      else
        restrict(context)
      end
    end

    get "/statuses.json" do |context, params|
      if @CONFIG["STATS_ALLOWED_FROM_IPS"].split(",").includes?(get_ip(context))
        context.response.content_type = "application/json"
        context.response.print @@QUEUE.to_json
        context
      else
        restrict(context)
      end
    end

    get "/status/:volume" do |context, params|
      if @CONFIG["STATS_ALLOWED_FROM_IPS"].split(",").includes?(get_ip(context))
        context.response.content_type = "text/plain"
        context.response.print @@QUEUE[params["volume"]]? && @@QUEUE[params["volume"]]["status"]? ? @@QUEUE[params["volume"]]["status"] : "OK"
        context
      else
        restrict(context)
      end
    end

    get "/backup/vm-xml/:vm_name" do |context, params|
      ip = get_ip(context)
      puts "Got backup vm-xml #{params} from #{ip}"
      condition = @CONFIG["BACKUP_ALLOWED_FROM_IPS"].split(",").includes?(ip) && is_vm_exists(params["vm_name"])
      perform_response(context, "text/plain", "ok", "vm-xml: #{params["vm_name"]}", condition) do
        backup_vm_xml(params["vm_name"])
      end
    end

    get "/backup/lv/:vg/:volume" do |context, params|
      ip = get_ip(context)
      puts "Got lv backup #{params} from #{ip}"
      condition = @CONFIG["BACKUP_ALLOWED_FROM_IPS"].split(",").includes?(ip) && are_exists_vg_and_lv(params["vg"], params["volume"]) == "ok"
      perform_response(context, "text/plain", "queued", "lvm volume: #{params["volume"]}", condition) do
        spawn backup_lv(params["vg"], params["volume"])
      end
    end

    get "/backup/docker-volume/:docker_volume" do |context, params|
      ip = get_ip(context)
      condition = @CONFIG["BACKUP_ALLOWED_FROM_IPS"].split(",").includes?(ip) && @@docker && is_docker_volume_exists(params["docker_volume"])
      puts condition
      perform_response(context, "text/plain", "queued", "docker volume: #{params["docker_volume"]}", condition) do
        spawn backup_folder(params["docker_volume"])
      end
    end

    get "/backup/files/" do |context, params|
      ip = get_ip(context)
      condition = @CONFIG["BACKUP_ALLOWED_FROM_IPS"].split(",").includes?(ip) && context.request.query_params["path"]? && Dir.exists?(context.request.query_params["path"])
      perform_response(context, "text/plain", "queued", "folder: #{context.request.query_params["path"]}", condition) do
        spawn backup_folder(context.request.query_params["path"])
      end
    end
  end

  private def does_this_path_exist?(path)
    ok = Dir.exists?(path)
    puts "#{path} #{ok ? "is exist." : "is not exist!"}"
  end

  private def backup_folder(object)
    is_docker_volume = true
    # p object
    folder = if (object.includes?("/"))
               is_docker_volume = false
               object.split("/").last
             else
               object
             end
    puts "is docker volume? - #{is_docker_volume}"
    @@QUEUE[folder] = {
      "created_at" => Time.local.to_s,
      "status"     => "Added to queue",
    }
    filename = "#{folder}.#{is_docker_volume ? "docker_volume" : "folder"}.#{get_date}.tar.gz.#{@CONFIG["BACKUP_FILE_EXTENSION"]}"
    puts "Forming backup path..."
    path = if is_docker_volume
             @CONFIG["DOCKER_VOLUME_BACKUP_PATH"]? ? @CONFIG["DOCKER_VOLUME_BACKUP_PATH"] : @CONFIG["PATH"]
           else
             @CONFIG["FILES_BACKUP_PATH"]? ? @CONFIG["FILES_BACKUP_PATH"] : @CONFIG["PATH"]
           end

    send_to_external_command(object, "start archiving: #{object}")
    @@QUEUE[folder]["status"] = "archiving"
    puts "Forming command for backup..."
    command = if is_docker_volume
                if @IS_LOCAL
                  "tar -zcf #{path}/#{filename} -C #{docker_volume_path}/#{folder}/_data/ ."
                else
                  "tar czf - #{docker_volume_path}/#{folder}/_data/ | ssh  -o \"StrictHostKeyChecking no\" -i id_rsa #{@CONFIG["USER"]}@#{@CONFIG["HOST"]} \"dd of=#{path}/#{filename}\""
                end
              else
                if @IS_LOCAL
                  "tar -zcf #{path}/#{filename} -C #{object}/ ."
                else
                  "tar czf - #{object} | ssh -o \"StrictHostKeyChecking no\" -i id_rsa #{@CONFIG["USER"]}@#{@CONFIG["HOST"]} \"dd of=#{path}/#{filename}\""
                end
              end
    puts command
    _archive_cmd_result = run_command(command)
    send_to_external_command("files/docker volume", "archiving #{object} complete: #{_archive_cmd_result}")
    _chown_chmod_output = chown_chmod(path, filename)
    send_to_external_command("files/docker volume", "chmod & chown #{object}: #{_chown_chmod_output}")
    remove_old_backups(path, folder)
    @@QUEUE.delete(folder)
  end

  private def backup_vm_xml(vm_name)
    filename = "#{vm_name}.vm-xml.#{get_date}.xml.#{@CONFIG["BACKUP_FILE_EXTENSION"]}"
    path = @CONFIG["VM_BACKUP_PATH"]? ? @CONFIG["VM_BACKUP_PATH"] : @CONFIG["PATH"]
    command = if @IS_LOCAL
                "virsh dumpxml #{vm_name} > #{path}/#{filename}"
              else
                "virsh dumpxml #{vm_name} | ssh -o \"StrictHostKeyChecking no\" -i id_rsa #{@CONFIG["USER"]}@#{@CONFIG["HOST"]} 'cat > #{path}/#{filename}'"
              end
    puts command
    _backup_cmd_out = run_command(command)
    send_to_external_command("vm xml", "#{vm_name} saved: #{_backup_cmd_out}")
    _chown_chmod_output = chown_chmod(path, filename)
    send_to_external_command("vm xml", "chmod & chown #{vm_name}: #{_chown_chmod_output}")
    send_to_external_command("vm xml", "удаление старых #{vm_name}.vm-xml.")
    remove_old_backups(path, "#{vm_name}.vm-xml")
  end

  private def get_vm_list
    run_command("virsh list --all --name").chomp.chomp.split("\n").select { |e| e != "" }
  end

  private def get_vm_disks(vm_name)
    results = Array(String).new
    run_command("virsh dumpxml #{vm_name}").not_nil!.scan(/<source dev=(?:'|")\/dev\/(.+?)(?:'|")\/>/) { |r| results << r[1].to_s }
    results
  end

  private def is_vm_exists(vm_name)
    ok = false
    _out = run_command("virsh list --all --name").chomp.chomp
    if _out.size != 0
      ok = _out.split("\n").includes?(vm_name)
    end
    return ok
  end

  private def perform_response(context, content_type, text, message_text, condition)
    if condition
      yield
      context.response.content_type = content_type
      context.response.print text
      send_to_external_command(text, message_text)
      context
    else
      restrict(context)
    end
  end

  private def get_ip(context)
    context.request.remote_address.not_nil!.split(":")[0]
  end

  private def restrict(context : HTTP::Server::Context)
    context.response.status_code = 401
    context.response.print "401"
    context
  end

  private def is_docker_volume_exists(vol_name)
    run_command("docker volume ls -q").split("\n").includes?(vol_name)
  end

  private def check_executables
    if run_command("which gzip").size == 0
      STDERR.puts "gzip is not found in the PATH"
      exit(1)
    end
    if run_command("which sshfs").size == 0
      STDERR.puts "sshfs is not found in the PATH; you need to install: sudo apt install sshfs/pacman -S sshfs/dnf install sshfs"
      exit(1)
    end
    if run_command("which docker").size == 0
      puts "Docker is not found in the PATH; backup docker volumes will be unavailable"
      @@docker = false
    end
  end

  private def check_group(group)
    if run_command("cat /etc/group | grep #{group}").size == 0
      STDERR.puts("Group #{group} is not found, please add: sudo groupadd -g 5000 #{group}")
      exit(1)
    end
  end

  private def check_user(user, group)
    if run_command("cat /etc/passwd | grep #{user}").size == 0
      STDERR.puts("User #{user} is not found, please add: sudo useradd -u 5000 -m -G #{group} #{user}")
      exit(1)
    end
  end

  def start
    server = HTTP::Server.new([
      HTTP::ErrorHandler.new,
      HTTP::LogHandler.new,
      route_handler,
    ])
    server.bind_tcp(Socket::IPAddress.new(@CONFIG["LISTEN_ON"], @CONFIG["PORT"].to_i32))
    puts "backup-cr is listen on #{@CONFIG["LISTEN_ON"]}:#{@CONFIG["PORT"]}"
    server.listen
  end

  private def docker_volume_path
    run_command("docker info | grep \"Docker Root Dir:\"").split(": ")[1].chomp + "/volumes"
  end

  private def get_date
    Time.local.to_s("%F")
  end

  private def backup_lv(vg, lv)
    @@QUEUE[lv] = {
      "created_at" => Time.local.to_s,
      "status"     => "creating snapshot",
    }
    _create_snapshot_output = create_snapshot(vg, lv)
    send_to_external_command("created snapshot", get_snapshot_name(lv))
    @@QUEUE[lv]["status"] = "archiving"
    date = get_date
    backup_file_name = "#{lv}.lv.#{date}.gz.#{@CONFIG["BACKUP_FILE_EXTENSION"]}"
    bs_size = @CONFIG["DD_BS_SIZE"]? ? @CONFIG["DD_BS_SIZE"] : "8M"
    path = @CONFIG["VM_BACKUP_PATH"]? ? @CONFIG["VM_BACKUP_PATH"] : @CONFIG["PATH"]
    backup_full_path = if @IS_LOCAL
                         "#{System.hostname}@#{path}/#{backup_file_name}"
                       else
                         "#{@CONFIG["HOST"]}@#{path}/#{backup_file_name}"
                       end
    backup_command = if @IS_LOCAL
                       "dd if=/dev/#{vg}/#{get_snapshot_name(lv)} bs=#{bs_size} | gzip -#{@CONFIG["GZIP_COMPRESSION_LEVEL"]}cf > #{path}/#{backup_file_name}"
                     else
                       "dd if=/dev/#{vg}/#{get_snapshot_name(lv)} bs=#{bs_size} | gzip -#{@CONFIG["GZIP_COMPRESSION_LEVEL"]} - | ssh -o \"StrictHostKeyChecking no\" -i id_rsa #{@CONFIG["USER"]}@#{@CONFIG["HOST"]} dd of=#{path}/#{backup_file_name} bs=#{bs_size}"
                     end
    puts backup_command
    send_to_external_command("archiving to", backup_full_path)
    _backup_output = run_command(backup_command)
    send_to_external_command("backup #{backup_full_path}", _backup_output)
    chown_chmod_command = if @IS_LOCAL
                            "chown #{@CONFIG["USER"]}:#{@CONFIG["GROUP"]} #{path}/#{backup_file_name} && chmod 660 #{path}/#{backup_file_name}"
                          else
                            "ssh -o \"StrictHostKeyChecking no\" -i id_rsa #{@CONFIG["USER"]}@#{@CONFIG["HOST"]} 'chown #{@CONFIG["USER"]}:#{@CONFIG["GROUP"]} #{path}/#{backup_file_name} && chmod 660 #{path}/#{backup_file_name}'"
                          end
    _chown_output = run_command(chown_chmod_command)
    send_to_external_command("chmod 660 && chown #{@CONFIG["USER"]}:#{@CONFIG["GROUP"]}", "#{backup_full_path}, #{_chown_output}")
    _remove_snapshot_output = remove_snapshot(vg, get_snapshot_name(lv))
    @@QUEUE.delete(lv)
    send_to_external_command("removed snapshot", get_snapshot_name(lv))
    remove_old_backups(path, "#{lv}.lv")
    send_to_external_command("Произведено удаление старых lv: ", lv)
  end

  private def chown_chmod(path, backup_file_name)
    cmd = if @IS_LOCAL
            "chown #{@CONFIG["USER"]}:#{@CONFIG["GROUP"]} #{path}/#{backup_file_name} && chmod 660 #{path}/#{backup_file_name}"
          else
            "ssh -o \"StrictHostKeyChecking no\" -i id_rsa #{@CONFIG["USER"]}@#{@CONFIG["HOST"]} 'chown #{@CONFIG["USER"]}:#{@CONFIG["GROUP"]} #{path}/#{backup_file_name} && chmod 660 #{path}/#{backup_file_name}'"
          end
    return run_command(cmd)
  end

  private def get_snapshot_name(lv)
    return "#{lv}_BACKUP_CR_snap"
  end

  private def create_snapshot(vg, lv)
    create_snapshot_result = run_command("lvcreate --size #{@CONFIG["BACKUP_CR_DEFAULT_SNAPSHOT_SIZE"]? ? @CONFIG["BACKUP_CR_DEFAULT_SNAPSHOT_SIZE"] : "4G"} --snapshot --name #{get_snapshot_name(lv)} /dev/#{vg}/#{lv}")
    puts create_snapshot_result
    return create_snapshot_result
  end

  private def remove_snapshot(vg, lv)
    remove_snapshot_result = run_command("lvremove -y #{vg}/#{lv}")
    puts remove_snapshot_result
    return remove_snapshot_result
  end

  private def send_to_external_command(event, message)
    puts "#{event}:#{message}"
    begin
      run_command("#{@CONFIG["COMMAND"]} #{System.hostname} \"#{event}\" \"#{message}\"")
    rescue ex
      STDERR.puts ex.message
    end
  end

  private def get_vgs_report
    _result = JSON.parse(run_command("vgs --reportformat json").not_nil!)
    _result["report"]? ? _result["report"] : "Error when reading vgs!"
  end

  private def get_lvs_report
    _result = JSON.parse(run_command("lvs --reportformat json").not_nil!)
    _result["report"]? ? _result["report"] : "Error when reading lvs!"
  end

  private def get_lvm_structure
    _vgs, _lvs = [run_command("vgs --reportformat json"), run_command("lvs --reportformat json")]
    _tmp_vgs, _tmp_lvs = [JSON.parse(_vgs), JSON.parse(_lvs)]
    # IMPORTANT NOT Hash(String, String) | Hash(String, Array(Hash(String, String)) but Hash(String, String | Array(Hash(String, String)))
    lvm_structure = Hash(String, Hash(String, String | Array(Hash(String, String)))).new
    if _tmp_vgs && _tmp_lvs && _tmp_vgs["report"]? && _tmp_lvs["report"]?
      _vgs_with_report, _lvs_with_report = [
        (Hash(String, Array(Hash(String, Array(Hash(String, String)))))).from_json(_vgs),
        (Hash(String, Array(Hash(String, Array(Hash(String, String)))))).from_json(_lvs),
      ]
      vgs = _vgs_with_report["report"]? && _vgs_with_report["report"][0]? && _vgs_with_report["report"][0]["vg"]? ? _vgs_with_report["report"][0]["vg"] : nil
      lvs = _lvs_with_report["report"]? && _lvs_with_report["report"][0]? && _lvs_with_report["report"][0]["lv"]? ? _lvs_with_report["report"][0]["lv"] : nil
      if vgs && lvs
        vgs.each do |vg|
          if vg["vg_name"]? && vg["vg_size"]? && vg["vg_free"]? && vg["pv_count"]?
            finded_lv = lvs.select do |lv|
              lv["lv_name"]? && lv["vg_name"]? && lv["lv_size"]? && lv["vg_name"] == vg["vg_name"]
            end
            lvm_structure[vg["vg_name"]] = {
              "vg_size"  => vg["vg_size"],
              "vg_free"  => vg["vg_free"],
              "pv_count" => vg["pv_count"],
              "lvs":        finded_lv,
            }
          end
        end
      end
    end
    return lvm_structure
  rescue ex
    STDERR.puts ex.message
    nil
  end

  private def are_exists_vg_and_lv(vg, lv)
    result = ""
    _vgs_output = run_command("vgs #{vg}")
    if _vgs_output.includes?("not found")
      result = "#{vg} does not exist!"
    else
      _lvs_output = run_command("lvs #{vg} --reportformat json")
      _lvs_json = JSON.parse(_lvs_output.not_nil!)
      if _lvs_json["report"]?
        if _lvs_json["report"].as_a?
          if _lvs_json["report"].as_a[0]? && _lvs_json["report"].as_a[0]["lv"]? && _lvs_json["report"].as_a[0]["lv"].as_a? && _lvs_json["report"].as_a[0]["lv"].as_a.size > 0
            lvs = _lvs_json["report"].as_a[0]["lv"].as_a
            lv_names = lvs.map do |lv|
              lv.as_h? && lv.as_h["lv_name"]? && lv.as_h["lv_name"].as_s? ? lv.as_h["lv_name"].as_s : ""
            end
            if lv_names.includes?(lv)
              result = "ok"
            else
              result = "#{lv} is not found in #{vg}"
            end
          else
            result = "Error - not found any lv in #{vg}"
          end
        end
      else
        result = "Error when find logical volume #{lv}"
      end
    end
    return result
  end

  private def remove_old_backups(path, filename_template)
    puts "Find in #{path} by template #{filename_template} old backups"
    old_backups = if @IS_LOCAL
                    run_command("ls -t #{path} | grep #{filename_template}").split("\n").skip(@CONFIG["KEEP_VERSIONS_COUNT"].to_i)
                  else
                    run_command("ssh -i id_rsa -o \"StrictHostKeyChecking no\" #{@CONFIG["USER"]}@#{@CONFIG["HOST"]} 'ls -t #{path} | grep #{filename_template}'").split("\n").skip(@CONFIG["KEEP_VERSIONS_COUNT"].to_i)
                  end
    if old_backups.size > 0
      puts "It will be deleted #{old_backups.join(", ")}"
      old_backups.each do |f|
        if @IS_LOCAL
          run_command("rm -f #{path}/#{f}")
        else
          run_command("ssh -i id_rsa -o \"StrictHostKeyChecking no\" #{@CONFIG["USER"]}@#{@CONFIG["HOST"]} 'rm -f #{path}/#{f}'")
        end
      end
      send_to_external_command("removed old backups", old_backups.join(", "))
    end
  end

  private def run_command(cmd : String) : String
    Process.run(cmd, shell: true, output: @@io)
    result = @@io.to_s
    @@io.clear
    result
  end
end

s = BackupCrServer.new
s.draw_routes
s.start
