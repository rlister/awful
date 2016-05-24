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

    desc 'streams GROUP [PREFIX]', 'list log streams for GROUP'
    method_option :long,  aliases: '-l', default: false, desc: 'Long listing'
    method_option :limit, aliases: '-n', default: 50,    desc: 'Count to limit returned results'
    method_option :alpha, aliases: '-a', default: false, desc: 'Order by name'
    def streams(group, prefix = nil)
      next_token = nil
      log_streams = []
      loop do
        response = logs.describe_log_streams(
          log_group_name: group,
          log_stream_name_prefix: prefix,
          order_by: options[:alpha] ? 'LogStreamName' : 'LastEventTime',
          descending: (not options[:alpha]), # want desc order if by time for most recent first
          limit: options[:limit],
          next_token: next_token
        )
        log_streams = log_streams + response.log_streams
        next_token = response.next_token
        break if next_token.nil?
        break if log_streams.count >= options[:limit].to_i
      end
      log_streams.tap do |streams|
        if options[:long]
          print_table streams.map { |s| [s.log_stream_name, Time.at(s.last_event_timestamp.to_i/1000)] }
        else
          puts streams.map(&:log_stream_name)
        end
      end
    end

    no_commands do
      def latest_stream(group)
        logs.describe_log_streams(
          log_group_name: group,
          order_by: 'LastEventTime',
          descending: true,
          limit: 1
        ).log_streams.first
      end
    end

    desc 'latest GROUP', 'get name of latest stream for GROUP'
    def latest(group)
      latest_stream(group).tap do |stream|
        puts stream.log_stream_name
      end
    end

    desc 'events GROUP [STREAM]', 'get log events from given, or latest, stream'
    method_option :long,  aliases: '-l', default: false, desc: 'Long listing'
    method_option :limit, aliases: '-n', default: 50,    desc: 'Count to limit returned results'
    def events(group, stream = nil)
      next_token = nil
      events = []
      loop do
        response = logs.get_log_events(
          log_group_name: group,
          log_stream_name: stream || latest_stream(group).log_stream_name,
          start_from_head: true,
          limit: options[:limit],
          next_token: next_token
        )
        break if response.events.count == 0 # break on no results as token does not get to nil
        events = events + response.events
        next_token = response.next_backward_token
        break if events.count >= options[:limit].to_i
        break if next_token.nil? # not sure if this is ever set to nil
      end
      events.tap do |ev|
        if options[:long]
          print_table ev.map { |e| [Time.at(e.timestamp.to_i/1000), e.message] }
        else
          puts ev.map(&:message)
        end
      end
    end

  end
end