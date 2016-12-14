require 'time'

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

      ## human-readable timestamp
      def human_time(timestamp)
        if timestamp.nil?
          '-'
        else
          Time.at(timestamp.to_i/1000)
        end
      end
    end

    desc 'ls [PREFIX]', 'list log groups'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(prefix = nil)
      paginate(:log_groups) do |token|
        logs.describe_log_groups(log_group_name_prefix: prefix, next_token: token)
      end.output do |groups|
        if options[:long]
          print_table groups.map { |group|
            [
              group.log_group_name,
              group.retention_in_days,
              human_time(group.creation_time),
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
    method_option :long,  aliases: '-l', default: false, desc: 'long listing'
    method_option :limit, aliases: '-n', default: 50,    desc: 'limit number of results per page call'
    method_option :alpha, aliases: '-a', default: false, desc: 'order by name'
    def streams(group, prefix = nil)
      paginate(:log_streams) do |token|
        logs.describe_log_streams(
          log_group_name: group,
          log_stream_name_prefix: prefix,
          order_by: options[:alpha] ? 'LogStreamName' : 'LastEventTime',
          descending: (not options[:alpha]), # want desc order if by time for most recent first
          limit: options[:limit],
          next_token: token,
        )
      end.output do |streams|
        if options[:long]
          print_table streams.map { |s|
            [ s.log_stream_name, human_time(s.creation_time), human_time(s.last_event_timestamp) ]
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
    method_option :long,   aliases: '-l', type: :boolean, default: false,           desc: 'long listing including timestamps'
    method_option :stream, aliases: '-s', type: :string,  default: nil,             desc: 'specific stream to read instead of latest'
    method_option :limit,  aliases: '-n', type: :numeric, default: nil,             desc: 'limit results returned per page'
    method_option :pages,  aliases: '-p', type: :numeric, default: Float::INFINITY, desc: 'limit number of pages to output'
    method_option :head,   aliases: '-H', type: :boolean, default: true,            desc: 'start from head, ie first page'
    method_option :tail,   aliases: '-t', type: :numeric, default: nil,             desc: 'show given small number of most recent events'
    def events(group, nth = 0)
      opt = options.dup
      opt[:stream] ||= latest_stream(group, nth).log_stream_name # use latest stream if none requested

      ## magical tail option returns up to requested number of last events
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
          log_stream_name: opt[:stream],
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
          print_table ev.map { |e| [human_time(e.timestamp), e.message] }
        else
          puts ev.map(&:message)
        end
      end
    end

    desc 'filter GROUP [STREAMS]', 'filter'
    method_option :pattern, aliases: '-p', type: :string, default: nil, desc: 'pattern to filter logs'
    method_option :start,   aliases: '-s', type: :string, default: nil, desc: 'start time'
    method_option :end,     aliases: '-e', type: :string, default: nil, desc: 'end time'
    def filter(group, *streams)
      start_time = options[:start] ? Time.parse(options[:start]).to_i*1000 : nil
      end_time   = options[:end]   ? Time.parse(options[:end]).to_i*1000   : nil
      token = nil
      loop do
        resp = logs.filter_log_events(
          log_group_name: group,
          log_stream_names: streams.empty? ? nil : streams,
          next_token: token,
          start_time: start_time,
          end_time: end_time,
          filter_pattern: options[:pattern],
        )
        resp.events.each do |e|
          time   = set_color(human_time(e.timestamp).utc, :green)
          stream = set_color(e.log_stream_name, :blue)
          puts("#{time}  #{stream}  #{e.message}")
        end
        token = resp.next_token
        break unless token
      end
    end

    desc 'tail GROUP [STREAMS]', 'tail log group streams'
    method_option :numlines, aliases: '-n', type: :numeric, default: 10,    desc: 'number of lines to show'
    method_option :follow,   aliases: '-f', type: :boolean, default: false, desc: 'follow log output'
    method_option :sleep,    aliases: '-s', type: :numeric, default: 3,     desc: 'seconds to sleep between poll for new data'
    method_option :timestamp,               type: :boolean, default: true,  desc: 'show timestamp for each line'
    def tail(group, stream)
      trap('SIGINT', 'EXIT')    # expect to exit with ctrl-c

      ## how to print each line
      out = if options[:timestamp]
        ->(e) { puts("#{set_color(human_time(e.timestamp).utc, :green)}  #{e.message}") }
      else
        ->(e) { puts e.message }
      end

      token = nil
      loop do
        resp = logs.get_log_events(
          log_group_name: group,
          log_stream_name: stream,
          limit: options[:numlines],
          next_token: token,
        )
        resp.events.each do |e|
          out.call(e)
        end
        token = resp.next_forward_token
        options[:follow] ? sleep(options[:sleep]) : break
      end
    end

    desc 'head', 'get log events starting from head of stream'
    method_option :numlines, aliases: '-n', type: :numeric, default: 10,    desc: 'number of lines to show'
    method_option :timestamp,               type: :boolean, default: true,  desc: 'show timestamp for each line'
    def head(group, stream)
      out = options[:timestamp] ? ->(e) { puts("#{set_color(human_time(e.timestamp).utc, :green)}  #{e.message}") } : ->(e) { puts e.message }

      logs.get_log_events(
        log_group_name: group,
        log_stream_name: stream,
        limit: options[:numlines],
        start_from_head: true,
      ).events.each do |e|
        out.call(e)
      end
    end
  end
end