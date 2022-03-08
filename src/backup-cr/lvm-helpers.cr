module BackupCr
  module LvmHelpers
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
                "lvs" => finded_lv,
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

    private def get_vgs_report
      _result = JSON.parse(run_command("vgs --reportformat json").not_nil!)
      _result["report"]? ? _result["report"] : "Error when reading vgs!"
    end

    private def get_lvs_report
      _result = JSON.parse(run_command("lvs --reportformat json").not_nil!)
      _result["report"]? ? _result["report"] : "Error when reading lvs!"
    end

    private def get_snapshot_name(lv)
      return "#{lv}_BACKUP_CR_snap"
    end

    private def create_snapshot(vg, lv)
      create_snapshot_result = run_command("lvcreate --size #{CONFIG["BACKUP_CR_DEFAULT_SNAPSHOT_SIZE"]? ? CONFIG["BACKUP_CR_DEFAULT_SNAPSHOT_SIZE"] : "4G"} --snapshot --name #{get_snapshot_name(lv)} /dev/#{vg}/#{lv}")
      puts create_snapshot_result
      return create_snapshot_result
    end

    private def remove_snapshot(vg, lv)
      remove_snapshot_result = run_command("lvremove -y #{vg}/#{lv}")
      puts remove_snapshot_result
      return remove_snapshot_result
    end
  end
end
