module BackupCr
  module DockerHelpers
    private def is_docker_volume_exists(vol_name)
      run_command("docker volume ls -q").split("\n").includes?(vol_name)
    end

    private def docker_volume_path
      run_command("docker info | grep \"Docker Root Dir:\"").split(": ")[1].chomp + "/volumes"
    end
  end
end
