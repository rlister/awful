require 'aws-sdk-ssm'

module Awful
  class Ssm < Cli
    COLORS = {
      Success:   :green,
      TimedOut:  :red,
      Cancelled: :red,
      Failed:    :red
    }

    no_commands do
      def ssm
        @ssm ||= Aws::SSM::Client.new
      end
    end

    desc 'ls [PREFIX]', 'list parameters'
    def ls(prefix = '/')
      filters = [ { key: :Name, option: :BeginsWith, values: [ prefix.sub(/^(\w)/, '/\1') ] } ]
      ssm.describe_parameters(parameter_filters: filters).each do |response|
        response.parameters.each { |p| puts p.name }
        sleep 0.1               # this api will throttle easily
      end
    end

    desc 'get NAME', 'get parameter value'
    method_option :decrypt, aliases: '-d', type: :boolean, default: false, desc: 'decrypt SecureString'
    def get(name)
      puts ssm.get_parameter(name: name, with_decryption: options[:decrypt]).parameter.value
    rescue Aws::SSM::Errors::ParameterNotFound => e
      error(e.message)
    end

    desc 'path NAME', 'get parameters by path'
    method_option :decrypt,   aliases: '-d', type: :boolean, default: false, desc: 'decrypt SecureString'
    method_option :recursive, aliases: '-r', type: :boolean, default: false, desc: 'recurse hierarchy'
    method_option :show,      aliases: '-s', type: :boolean, default: false, desc: 'show values'
    def path(path)
      cmd = options[:show] ? ->(p) { puts "#{p.name} #{p.value}" } : ->(p) { puts p.name }
      ssm.get_parameters_by_path(path: path, with_decryption: options[:decrypt], recursive: options[:recursive]).each do |response|
        response.parameters.each(&cmd.method(:call))
      end
    end

    desc 'put NAME VALUE', 'put parameter'
    method_option :description, aliases: '-d', type: :string,  default: nil,     desc: 'description for params'
    method_option :key_id,      aliases: '-k', type: :string,  default: nil,     desc: 'KMS key for SecureString params'
    method_option :overwrite,   aliases: '-o', type: :boolean, default: false,   desc: 'overwrite existing params'
    method_option :type,        aliases: '-t', type: :string,  default: :String, desc: 'String, StringList, SecureString'
    def put(name, value)
      ssm.put_parameter(
        name:        name,
        value:       value,
        description: options[:description],
        type:        options[:type],
        key_id:      options[:key_id],
        overwrite:   options[:overwrite],
      )
    rescue Aws::SSM::Errors::ParameterAlreadyExists => e
      error(e.message)
    end

    desc 'delete NAME', 'delete parameter'
    def delete(name)
      if yes?("Really delete parameter #{name}?", :yellow)
        ssm.delete_parameter(name: name)
      end
    rescue Aws::SSM::Errors::ParameterNotFound => e
      error(e.message)
    end

    desc 'history NAME', 'get parameter history'
    method_option :decrypt, aliases: '-d', type: :boolean, default: false, desc: 'decrypt SecureString'
    def history(name)
      ssm.get_parameter_history(name: name, with_decryption: options[:decrypt]).each do |p|
        print_table p.parameters.map { |h|
          [ h.version, h.last_modified_date, h.value ]
        }
      end
    end

    desc 'commands', 'list commands'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    def commands
      ssm.list_commands.commands.output do |cmds|
        if options[:long]
          print_table cmds.map { |c|
            [
              c.command_id,
              c.instance_ids.join(','),
              c.document_name,
              color(c.status),
              c.requested_date_time,
              c.comment
            ]
          }
        else
          puts cmds.map(&:command_id)
        end
      end
    end

    desc 'dump ID', 'get details of command invocation for command ID'
    def dump(id)
      ssm.list_command_invocations(command_id: id, details: true).command_invocations.output do |cmds|
        cmds.each do |cmd|
          puts YAML.dump(stringify_keys(cmd.to_hash))
        end
      end
    end

    desc 'documents NAME', 'list documents matching NAME'
    method_option :long,           aliases: '-l', type: :boolean, default: false,   desc: 'Long listing'
    method_option :platform_types, aliases: '-p', type: :string,  default: 'Linux', desc: 'Platform type to show'
    def documents(name = '.')
      filter = [{key: 'PlatformTypes', value: options[:platform_types].capitalize}]
      ssm.list_documents(document_filter_list: filter).document_identifiers.select do |doc|
        doc.name.match(/#{name}/i)
      end.output do |docs|
        if options[:long]
          print_table docs.map { |d| [d.name, d.platform_types.join(',')] }
        else
          puts docs.map(&:name)
        end
      end
    end

    desc 'shell_script INSTANCE_IDS', 'run shell script on instances'
    method_option :commands, aliases: '-c', type: :array,   default: [],  desc: 'Commands to run'
    method_option :comment,                 type: :string,  default: nil, desc: 'Brief command description'
    method_option :timeout,  aliases: '-t', type: :numeric, default: nil, desc: 'Timeout in seconds'
    method_option :bucket,   aliases: '-b', type: :string,  default: nil, desc: 'S3 bucket to save output'
    method_option :prefix,   aliases: '-p', type: :string,  default: nil, desc: 'Prefix for S3 output key'
    def shell_script(*instance_ids)
      ssm.send_command(
        instance_ids: instance_ids,
        comment: options[:comment],
        timeout_seconds: options[:timeout],
        output_s3_bucket_name: options[:bucket],
        output_s3_key_prefix: options[:prefix],
        document_name: 'AWS-RunShellScript',
        parameters: {
          commands: options[:commands]
        }
      ).output do |response|
        puts response.command.command_id
      end
    end
  end
end
