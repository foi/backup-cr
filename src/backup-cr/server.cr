require "router"
require "json"
require "./backup-helpers"
require "./system-helpers"
require "./lvm-helpers"
require "./docker-helpers"
require "./vm-helpers"

module BackupCr
  module Web
    class Server
      include Router
      include BackupCr::SystemHelpers
      include BackupCr::BackupHelpers
      include BackupCr::LvmHelpers
      include BackupCr::DockerHelpers
      include BackupCr::VmHelpers

      class AccessHandler
        include HTTP::Handler

        private def get_ip(context)
          remote_address_raw = context.request.remote_address
          return remote_address_raw.is_a?(Socket::IPAddress) ? remote_address_raw.address : "127.0.0.1"
        end

        def call(context)
          if CONFIG["ALLOWED_FROM_IPS"].split(",").includes?(get_ip(context))
            call_next(context)
          else
            context.response.status_code = 401
            context.response.print "401"
            context
          end
        end
      end

      private def perform_response(context, content_type, text, message_text, condition)
        if condition
          yield
          context.response.content_type = content_type
          context.response.print text
          send_to_external_command(text, message_text)
          context
        else
          context.response.status_code = 401
          context.response.print "401"
          context
        end
      end

      def draw_routes
        get "/api/get_paths" do |context, params|
          context.response.content_type = "application/json"
          context.response.print PATHS.to_json
          context
        end

        get "/api/files_in/:pathname" do |context, params|
          if PATHS[params["pathname"]]?.nil?
            context.response.status_code = 500
            context.response.print "#{params["pathname"]} is not found"
            context
          else
            begin
              context.response.content_type = "application/json"
              context.response.print get_files_in_path(PATHS[params["pathname"]].not_nil!).to_json
            rescue ex
              STDERR.puts ex.message
              context.response.status_code = 500
              context.response.print ex.message
            end
            context
          end
        end

        get "/api/mount_size/:pathname" do |context, params|
          if PATHS[params["pathname"]]?.nil?
            context.response.status_code = 500
            context.response.print "#{params["pathname"]} is not found"
            context
          else
            begin
              context.response.content_type = "application/json"
              context.response.print get_mount_size(PATHS[params["pathname"]].not_nil!).to_json
            rescue ex
              STDERR.puts ex.message
              context.response.status_code = 500
              context.response.print ex.message
            end
            context
          end
        end

        get "/api/lvm_structure" do |context, params|
          context.response.content_type = "application/json"
          context.response.print get_lvm_structure.to_json
          context
        end

        get "/api/vm_list" do |context, params|
          context.response.content_type = "application/json"
          vm_data = get_vm_list.map do |vm|
            {"vm" => vm, "disks" => get_vm_disks(vm).not_nil!}
          end
          context.response.print vm_data.to_json
          context
        end

        get "/" do |context, params|
          context.response.content_type = "text/html"
          {% if flag?(:release) %}
            # https://github.com/crystal-lang/crystal/issues/1649
            context.response.print {{ `cat #{__DIR__}/../index.html`.stringify }}
          {% else %}
            context.response.print File.read("index.html")
          {% end %}
          context
        end

        get "/statuses.json" do |context, params|
          context.response.content_type = "application/json"
          context.response.print QUEUE.to_json
          context
        end

        get "/status/:volume" do |context, params|
          context.response.content_type = "text/plain"
          context.response.print QUEUE[params["volume"]]? && QUEUE[params["volume"]]["status"]? ? QUEUE[params["volume"]]["status"] : "OK"
          context
        end

        get "/backup/vm-xml/:vm_name" do |context, params|
          perform_response(context, "text/plain", "ok", "vm-xml: #{params["vm_name"]}", is_vm_exists(params["vm_name"])) do
            backup_vm_xml(params["vm_name"], get_keep_versions_count(context.request.query_params))
          end
        end

        get "/backup/lv/:vg/:volume" do |context, params|
          perform_response(context, "text/plain", "queued", "lvm volume: #{params["volume"]}", are_exists_vg_and_lv(params["vg"], params["volume"]) == "ok") do
            spawn backup_lv(params["vg"], params["volume"], get_keep_versions_count(context.request.query_params))
          end
        end

        get "/backup/docker-volume/:docker_volume" do |context, params|
          perform_response(context, "text/plain", "queued", "docker volume: #{params["docker_volume"]}", DOCKER && is_docker_volume_exists(params["docker_volume"])) do
            spawn backup_folder(params["docker_volume"], get_keep_versions_count(context.request.query_params))
          end
        end

        get "/backup/files/" do |context, params|
          condition = context.request.query_params["path"]? && Dir.exists?(context.request.query_params["path"]) && Dir.entries(context.request.query_params["path"]).size > 2
          if Dir.entries(context.request.query_params["path"]).size == 2
            send_to_external_command("backup-files", "#{context.request.query_params["path"]} is empty. Backup is stopped.")
          end
          perform_response(context, "text/plain", "queued", "folder: #{context.request.query_params["path"]}", condition) do
            spawn backup_folder(context.request.query_params["path"], get_keep_versions_count(context.request.query_params))
          end
        end
      end

      def start
        server = HTTP::Server.new([
          HTTP::ErrorHandler.new,
          HTTP::LogHandler.new,
          AccessHandler.new,
          route_handler,
        ])
        server.bind_tcp(Socket::IPAddress.new(CONFIG["LISTEN_ON"], CONFIG["PORT"].to_i32))
        puts "backup-cr #{VERSION} is listen on #{CONFIG["LISTEN_ON"]}:#{CONFIG["PORT"]}. Feel free to open issue: github.com/foi/backup-cr"
        server.listen
      end
    end
  end
end
