require 'yaml'

module Awful
  module Short
    def firehose(*args)
      Awful::Firehose.new.invoke(*args)
    end
  end

  class Firehose < Cli
    COLORS = {
      ACTIVE:   :green,
      DELETING: :red,
    }

    no_commands do
      def firehose
        @_firehose ||= Aws::Firehose::Client.new
      end

      ## special-case paginator for delivery streams
      def paginate_delivery_streams(thing)
        token = nil
        things = []
        loop do
          resp = yield(token)
          items = resp.send(thing)
          things += items
          token = items.last
          break unless resp.has_more_delivery_streams
        end
        things
      end
    end

    desc 'ls', 'list firehose streams'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def ls
      paginate_delivery_streams(:delivery_stream_names) do |start|
        firehose.list_delivery_streams(exclusive_start_delivery_stream_name: start)
      end.output do |streams|
        if options[:long]
          print_table streams.map { |name|

            s = firehose.describe_delivery_stream(delivery_stream_name: name).delivery_stream_description
            op = s.has_more_destinations ? '>' : ''
            [s.delivery_stream_name, op + s.destinations.count.to_s, color(s.delivery_stream_status), s.delivery_stream_type, 'v' + s.version_id.to_s, s.create_timestamp]
          }
        else
          puts streams
        end
      end
    end

    desc 'dump NAME', 'describe firehose stream'
    def dump(name)
      firehose.describe_delivery_stream(delivery_stream_name: name).delivery_stream_description.output do |stream|
        puts YAML.dump(stringify_keys(stream.to_hash))
      end
    end

  end
end
