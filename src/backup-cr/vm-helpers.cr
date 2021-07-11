module BackupCr
  module VmHelpers
    private def get_vm_list
      run_command("virsh list --all --name").chomp.chomp.split("\n").select { |e| e != "" }
    end

    private def is_vm_exists(vm_name)
      ok = false
      _out = run_command("virsh list --all --name").chomp.chomp
      if _out.size != 0
        ok = _out.split("\n").includes?(vm_name)
      end
      return ok
    end

    private def get_vm_disks(vm_name)
      results = Array(String).new
      run_command("virsh dumpxml #{vm_name}").not_nil!.scan(/<source dev=(?:'|")\/dev\/(.+?)(?:'|")\/>/) { |r| results << r[1].to_s }
      results
    end
  end
end
