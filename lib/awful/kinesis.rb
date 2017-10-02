require 'yaml'

module Awful
  module Short
    def kinesis(*args)
      Awful::Kinesis.new.invoke(*args)
    end
  end

  class Kinesis < Cli
    COLORS = {
      ACTIVE:   :green,
      DELETING: :red,
    }

    no_commands do
      def kinesis
        @_kinesis ||= Aws::Kinesis::Client.new
      end

      def color(string)
        set_color(string, COLORS.fetch(string.to_sym, :yellow))
      end

      ## special-case paginator for streams
      def paginate_streams(thing)
        token = nil
        things = []
        loop do
          resp = yield(token)
          items = resp.send(thing)
          things += items
          token = items.last
          break unless resp.has_more_streams
        end
        things
      end
    end

    desc 'ls', 'list streams'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def ls
      paginate_streams(:stream_names) do |start|
        kinesis.list_streams(exclusive_start_stream_name: start)
      end.output do |streams|
        if options[:long]
          print_table streams.map { |name|
            s = kinesis.describe_stream(stream_name: name).stream_description
            op = s.has_more_shards ? '>' : ''
            [s.stream_name, op + s.shards.count.to_s, color(s.stream_status), s.encryption_type, s.retention_period_hours.to_s + 'h', s.stream_creation_timestamp]
          }
        else
          puts streams
        end
      end
    end

    desc 'dump [NAME]', 'describe a stream by name'
    def dump(name)
      kinesis.describe_stream(stream_name: name).stream_description.output do |stream|
        puts YAML.dump(stringify_keys(stream.to_hash))
      end
    end

  end
end