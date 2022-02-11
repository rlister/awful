require 'aws-sdk-ssm'

module Awful
  module Short
    def ssm(*args)
      Awful::Ssm.new.invoke(*args)
    end
  end

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

      def color(string)
        set_color(string, COLORS.fetch(string.to_sym, :yellow))
      end
    end

    desc 'ls', 'list commands'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    def ls
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
