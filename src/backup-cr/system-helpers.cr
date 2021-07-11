module BackupCr
  module SystemHelpers
    private def run_command(cmd : String) : String
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      Process.run(cmd, shell: true, output: out_io, error: err_io)
      result = out_io.to_s
      out_io.clear
      result
    end

    private def get_date
      Time.local.to_s("%F")
    end
  end
end
