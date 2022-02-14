require 'aws-sdk-secretsmanager'

module Awful
  class Secret < Cli
    COLORS = {
      AWSCURRENT: :green
    }

    no_commands do
      def client
        @_client ||= Aws::SecretsManager::Client.new
      end
    end

    desc 'ls', 'list secrets'
    def ls(prefix = nil)
      client.list_secrets.map(&:secret_list).flatten.tap do |secrets|
        secrets.select! { |s| s.name.start_with?(prefix) } if prefix
      end.map do |s|
        [ s.name, s.created_date, s.primary_region ]
      end.tap do |list|
        print_table list.sort
      end
    end

    desc 'get SECRET', 'get secret value'
    method_option :show,     aliases: '-s', type: :boolean, default: false, desc: 'show secret values'
    method_option :previous, aliases: '-p', type: :boolean, default: false, desc: 'show previous value'
    def get(id)
      string = client.get_secret_value(secret_id: id).secret_string
      begin
        hash = JSON.parse(string)
        hash.each { |k,v| hash[k] = "#{v.bytesize} bytes" } unless options[:show]
        print_table hash.sort
      rescue JSON::ParserError
        puts string
      end
    end

    desc 'history SECRET', 'get secret versions'
    def history(id)
      print_table client.list_secret_version_ids(secret_id: id).versions.map { |v|
        [ v.version_id, color(v.version_stages.join(',')), v.created_date ]
      }
    end

    desc 'delete SECRET', 'delete secret'
    method_option :window, aliases: '-w', type: :numeric, default: 7, desc: 'recovery window in days'
    def delete(id)
      if yes?("Really delete secret #{id}?", :yellow)
        puts client.delete_secret(secret_id: id, recovery_window_in_days: options[:window]).deletion_date
      end
    end

  end
end
