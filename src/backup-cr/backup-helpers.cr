module BackupCr
  module BackupHelpers
    private def parse_df_output(df_output, path)
      splitted = df_output.split("\n")
      if splitted.size == 2 && splitted[1]?
        dfdata = splitted[1].split(" ").reject { |e| e == "" }
        if (dfdata[0]? && dfdata[1]? && dfdata[2]? && dfdata[3]? && dfdata[4]? && dfdata[5]?)
          {
            "device"              => dfdata[0],
            "total_size_in_b"     => dfdata[1].to_i64?,
            "total_size_h"        => dfdata[1].to_i64.not_nil!.humanize,
            "used_size_in_b"      => dfdata[2].to_i64?,
            "used_size_in_h"      => dfdata[2].to_i64.not_nil!.humanize,
            "available_size_in_b" => dfdata[3].to_i64?,
            "available_size_in_h" => dfdata[3].to_i64.not_nil!.humanize,
            "percent_used"        => dfdata[4],
            "mountpoint"          => dfdata[5],
          }
        end
      else
        STDERR.puts "Something went wrong while reading df output of #{path}: #{df_output}"
      end
    end

    private def get_keep_versions_count(query_params) : Int32
      if query_params.has_key?("keep_versions_count") && query_params["keep_versions_count"].to_i?
        return query_params["keep_versions_count"].to_i
      else
        return CONFIG["KEEP_VERSIONS_COUNT"].to_i
      end
    end

    private def does_this_path_exist?(path)
      ok = Dir.exists?(path)
      puts "#{path} #{ok ? "is exist." : "is not exist!"}"
    end

    private def get_mount_size(path : String)
      _raw_df_output = IS_LOCAL ? run_command("df -B1 #{path}") : run_command("ssh -i id_rsa #{CONFIG["USER"]}@#{CONFIG["HOST"]} 'df -B1 #{path}'")
      unless _raw_df_output.nil?
        parse_df_output(_raw_df_output.chomp, path)
      end
    end

    private def backup_folder(object, keep_versions_count)
      is_docker_volume = true
      # p object
      folder = if (object.includes?("/"))
                 is_docker_volume = false
                 object.split("/").last
               else
                 object
               end
      puts "is docker volume? - #{is_docker_volume}"
      QUEUE[object] = {
        "created_at" => Time.local.to_s,
        "status"     => "queued",
      }
      filename = "#{folder}.#{is_docker_volume ? "docker_volume" : "folder"}.#{get_date}.tar.gz.#{CONFIG["BACKUP_FILE_EXTENSION"]}"
      puts "Forming backup path..."
      path = if is_docker_volume
               CONFIG["DOCKER_VOLUME_BACKUP_PATH"]? ? CONFIG["DOCKER_VOLUME_BACKUP_PATH"] : CONFIG["PATH"]
             else
               CONFIG["FILES_BACKUP_PATH"]? ? CONFIG["FILES_BACKUP_PATH"] : CONFIG["PATH"]
             end
      send_to_external_command(object, "start archiving: #{object}")
      QUEUE[object]["status"] = "archiving"
      puts "Forming command for backup..."
      command = if is_docker_volume
                  if IS_LOCAL
                    "tar -zcf #{path}/#{filename} -C #{docker_volume_path}/#{folder}/_data/ ."
                  else
                    "tar czf - #{docker_volume_path}/#{folder}/_data/ | ssh  -o \"StrictHostKeyChecking no\" -i id_rsa #{CONFIG["USER"]}@#{CONFIG["HOST"]} \"dd of=#{path}/#{filename}\""
                  end
                else
                  if IS_LOCAL
                    "tar -zcf #{path}/#{filename} -C #{object}/ ."
                  else
                    "tar czf - #{object} | ssh -o \"StrictHostKeyChecking no\" -i id_rsa #{CONFIG["USER"]}@#{CONFIG["HOST"]} \"dd of=#{path}/#{filename}\""
                  end
                end
      puts command
      _archive_cmd_result = run_command(command)
      send_to_external_command("files/docker volume", "archiving #{object} complete: #{_archive_cmd_result}")
      _chown_chmod_output = chown_chmod(path, filename)
      send_to_external_command("files/docker volume", "chmod & chown #{object}: #{_chown_chmod_output}")
      remove_old_backups(path, folder, keep_versions_count)
      QUEUE.delete(object)
    end

    private def backup_vm_xml(vm_name, keep_versions_count)
      filename = "#{vm_name}.vm-xml.#{get_date}.xml.#{CONFIG["BACKUP_FILE_EXTENSION"]}"
      path = CONFIG["VM_BACKUP_PATH"]? ? CONFIG["VM_BACKUP_PATH"] : CONFIG["PATH"]
      command = if IS_LOCAL
                  "virsh dumpxml #{vm_name} > #{path}/#{filename}"
                else
                  "virsh dumpxml #{vm_name} | ssh -o \"StrictHostKeyChecking no\" -i id_rsa #{CONFIG["USER"]}@#{CONFIG["HOST"]} 'cat > #{path}/#{filename}'"
                end
      puts command
      _backup_cmd_out = run_command(command)
      send_to_external_command("vm xml", "#{vm_name} saved: #{_backup_cmd_out}")
      _chown_chmod_output = chown_chmod(path, filename)
      send_to_external_command("vm xml", "chmod & chown #{vm_name}: #{_chown_chmod_output}")
      send_to_external_command("vm xml", "удаление старых #{vm_name}.vm-xml.")
      remove_old_backups(path, "#{vm_name}.vm-xml", keep_versions_count)
    end

    private def backup_lv(vg, lv, keep_versions_count)
      vglv = "#{vg}/#{lv}"
      QUEUE[vglv] = {
        "created_at" => Time.local.to_s,
        "status"     => "creating snapshot",
      }
      _create_snapshot_output = create_snapshot(vg, lv)
      send_to_external_command("created snapshot", get_snapshot_name(lv))
      QUEUE[vglv]["status"] = "archiving"
      date = get_date
      backup_file_name = "#{lv}.lv.#{date}.gz.#{CONFIG["BACKUP_FILE_EXTENSION"]}"
      bs_size = CONFIG["DD_BS_SIZE"]? ? CONFIG["DD_BS_SIZE"] : "8M"
      path = CONFIG["VM_BACKUP_PATH"]? ? CONFIG["VM_BACKUP_PATH"] : CONFIG["PATH"]
      backup_full_path = if IS_LOCAL
                           "#{System.hostname}@#{path}/#{backup_file_name}"
                         else
                           "#{CONFIG["HOST"]}@#{path}/#{backup_file_name}"
                         end
      backup_command = if IS_LOCAL
                         "dd if=/dev/#{vg}/#{get_snapshot_name(lv)} bs=#{bs_size} | gzip -#{CONFIG["GZIP_COMPRESSION_LEVEL"]}cf > #{path}/#{backup_file_name}"
                       else
                         "dd if=/dev/#{vg}/#{get_snapshot_name(lv)} bs=#{bs_size} | gzip -#{CONFIG["GZIP_COMPRESSION_LEVEL"]} - | ssh -o \"StrictHostKeyChecking no\" -i id_rsa #{CONFIG["USER"]}@#{CONFIG["HOST"]} dd of=#{path}/#{backup_file_name} bs=#{bs_size}"
                       end
      puts backup_command
      send_to_external_command("archiving to", backup_full_path)
      _backup_output = run_command(backup_command)
      send_to_external_command("backup #{backup_full_path}", _backup_output)
      chown_chmod_command = if IS_LOCAL
                              "chown #{CONFIG["USER"]}:#{CONFIG["GROUP"]} #{path}/#{backup_file_name} && chmod 660 #{path}/#{backup_file_name}"
                            else
                              "ssh -o \"StrictHostKeyChecking no\" -i id_rsa #{CONFIG["USER"]}@#{CONFIG["HOST"]} 'chown #{CONFIG["USER"]}:#{CONFIG["GROUP"]} #{path}/#{backup_file_name} && chmod 660 #{path}/#{backup_file_name}'"
                            end
      _chown_output = run_command(chown_chmod_command)
      send_to_external_command("chmod 660 && chown #{CONFIG["USER"]}:#{CONFIG["GROUP"]}", "#{backup_full_path}, #{_chown_output}")
      _remove_snapshot_output = remove_snapshot(vg, get_snapshot_name(lv))
      QUEUE.delete(vglv)
      send_to_external_command("removed snapshot", get_snapshot_name(lv))
      remove_old_backups(path, "#{lv}.lv", keep_versions_count)
      send_to_external_command("Произведено удаление старых lv: ", lv)
    end

    private def chown_chmod(path, backup_file_name)
      cmd = if IS_LOCAL
              "chown #{CONFIG["USER"]}:#{CONFIG["GROUP"]} #{path}/#{backup_file_name} && chmod 660 #{path}/#{backup_file_name}"
            else
              "ssh -o \"StrictHostKeyChecking no\" -i id_rsa #{CONFIG["USER"]}@#{CONFIG["HOST"]} 'chown #{CONFIG["USER"]}:#{CONFIG["GROUP"]} #{path}/#{backup_file_name} && chmod 660 #{path}/#{backup_file_name}'"
            end
      return run_command(cmd)
    end

    private def send_to_external_command(event, message)
      puts "#{event}:#{message}"
      begin
        run_command("#{CONFIG["COMMAND"]} #{System.hostname} \"#{event}\" \"#{message}\"")
      rescue ex
        STDERR.puts ex.message
      end
    end

    private def get_files_in_path(path : String)
      if CONFIG.has_key?("HOST")
        puts path
        raw_files = run_command("ssh -i id_rsa #{CONFIG["USER"]}@#{CONFIG["HOST"]} 'stat -c '%y,%n,%s' #{path}/* | grep #{CONFIG["BACKUP_FILE_EXTENSION"]}'")
        puts raw_files
        files_data = raw_files.split("\n").reject { |f| f == "" }.map { |e| e.split(",") }
        if files_data.size > 0
          files_data.map do |e|
            {"modification_time" => e[0], "name" => e[1], "size" => e[2].to_i64.humanize}
          end
        else
          return [] of String
        end
      else
        files = Dir.glob("#{path}/*.#{CONFIG["BACKUP_FILE_EXTENSION"]}")
        if files.size > 0
          files.map do |f|
            file_info = Hash(String, String | Nil).new
            file_info = {"modification_time" => nil, "name" => f, "size" => nil}
            if fi = File.info("#{f}")
              file_info["modification_time"] = fi.modification_time.to_local.to_s
              file_info["name"] = f
              file_info["size"] = fi.size.humanize
            end
            file_info
          end
        else
          return [] of String
        end
      end
    end

    private def remove_old_backups(path, filename_template, keep_versions_count)
      puts "Find in #{path} by template #{filename_template} old backups, keeps up to #{keep_versions_count} versions"
      old_backups = if IS_LOCAL
                      run_command("ls -t #{path} | grep #{filename_template}").split("\n").skip(keep_versions_count)
                    else
                      run_command("ssh -i id_rsa -o \"StrictHostKeyChecking no\" #{CONFIG["USER"]}@#{CONFIG["HOST"]} 'ls -t #{path} | grep #{filename_template}'").split("\n").skip(keep_versions_count)
                    end
      if old_backups.size > 0
        puts "It will be deleted #{old_backups.join(", ")}"
        old_backups.each do |f|
          if IS_LOCAL
            run_command("rm -f #{path}/#{f}")
          else
            run_command("ssh -i id_rsa -o \"StrictHostKeyChecking no\" #{CONFIG["USER"]}@#{CONFIG["HOST"]} 'rm -f #{path}/#{f}'")
          end
        end
        send_to_external_command("removed old backups", old_backups.join(", "))
      end
    end
  end
end
