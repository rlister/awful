module Awful
  module Short
    def cwlogs(*args)
      Awful::CloudWatchLogs.new.invoke(*args)
    end
  end

  class CloudWatchLogs < Cli
    no_commands do
      def logs
        @logs ||= Aws::CloudWatchLogs::Client.new
      end
    end

    desc 'ls [PREFIX]', 'list log groups'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(prefix = nil)
      next_token = nil
      log_groups = []
      loop do
        response = logs.describe_log_groups(log_group_name_prefix: prefix, next_token: next_token)
        log_groups = log_groups + response.log_groups
        next_token = response.next_token
        break if next_token.nil?
      end

      ## return and output groups
      log_groups.tap do |groups|
        if options[:long]
          print_table groups.map { |group|
            [
              group.log_group_name,
              group.retention_in_days,
              Time.at(group.creation_time.to_i/1000),
              group.stored_bytes,
            ]
          }
        else
          puts groups.map(&:log_group_name)
        end
      end
    end

    desc 'create NAME', 'create log group'
    def create(name)
      logs.create_log_group(log_group_name: name)
    end

    desc 'delete NAME', 'delete named log group'
    def delete(name)
      logs.delete_log_group(log_group_name: name)
    end

  end
end