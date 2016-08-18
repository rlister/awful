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
      log_groups.output do |groups|
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
      log_streams.output do |streams|
        if options[:long]
          print_table streams.map { |s|
            [ s.log_stream_name, Time.at(s.creation_time.to_i/1000), Time.at(s.last_event_timestamp.to_i/1000) ]
          }
        else
          puts streams.map(&:log_stream_name)
        end
      end
    end

    no_commands do
      ## return n-th latest stream for group
      def latest_stream(group, n = 0)
        n = n.to_i.abs          # convert string and -ves
        logs.describe_log_streams(
          log_group_name: group,
          order_by:       'LastEventTime',
          descending:     true,
          limit:          n + 1
        ).log_streams[n]
      end
    end

    desc 'latest GROUP', 'get name of latest stream for GROUP'
    def latest(group, n = 0)
      latest_stream(group, n).output do |stream|
        puts stream.log_stream_name
      end
    end

    desc 'events GROUP [STREAM]', 'get log events from given, or latest, stream'
    method_option :long,  aliases: '-l', type: :boolean, default: false,           desc: 'long listing including timestamps'
    method_option :limit, aliases: '-n', type: :numeric, default: nil,             desc: 'limit results returned per page'
    method_option :pages, aliases: '-p', type: :numeric, default: Float::INFINITY, desc: 'limit number of pages to output'
    method_option :head,  aliases: '-H', type: :boolean, default: true,            desc: 'start from head, ie first page'
    method_option :tail,  aliases: '-t', type: :numeric, default: nil,             desc: 'show given small number of most recent events'
    def events(group, stream = nil)
      stream ||= latest_stream(group).log_stream_name # use latest stream if none requested

      ## magical tail option returns up to requested number of last events
      opt = options.dup
      if opt[:tail]
        opt[:head]  = false
        opt[:pages] = 1
        opt[:limit] = opt[:tail]
      end

      next_token = nil
      events = []
      pages = 0
      loop do
        response = logs.get_log_events(
          log_group_name:  group,
          log_stream_name: stream,
          start_from_head: opt[:head],
          limit:           opt[:limit],
          next_token:      next_token,
        )

        break if response.events.count == 0 # break on no results as token does not get to nil
        events = events + response.events

        pages += 1
        break if pages >= opt[:pages]

        next_token = response.next_backward_token
        break if next_token.nil? # not sure if this is ever set to nil
      end

      events.output do |ev|
        if options[:long]
          print_table ev.map { |e| [Time.at(e.timestamp.to_i/1000), e.message] }
        else
          puts ev.map(&:message)
        end
      end
    end

  end
end