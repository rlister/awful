module Awful
  module Short
    def dyn_streams(*args)
      Awful::Streams.new.invoke(*args)
    end
  end

  class Streams < Cli
    no_commands do
      def streams
        @streams ||= Aws::DynamoDBStreams::Client.new
      end
    end

    desc 'ls [NAME]', 'list dynamodb streams [for table NAME]'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(table_name = nil, exclusive_start_stream_arn = nil)
      response = streams.list_streams(
        table_name: table_name,
        exclusive_start_stream_arn: exclusive_start_stream_arn
      )

      streams = response.streams

      ## output
      if options[:long]
        print_table streams.map{ |s| [s.table_name, s.stream_arn] }.sort
      else
        puts streams.map(&:stream_arn)
      end

      ## recurse if there is more data to fetch
      streams += ls(table_name, response.last_evaluated_stream_arn) if response.last_evaluated_stream_arn
      streams
    end

    desc 'dump ARN', 'describe the stream with ARN as yaml'
    def dump(arn)
      streams.describe_stream(stream_arn: arn).stream_description.output do |stream|
        puts YAML.dump(stringify_keys(stream.to_hash))
      end
    end

    desc 'shards ARN', 'list shards for stream with ARN'
    def shards(arn)
      streams.describe_stream(stream_arn: arn).stream_description.shards.output do |shards|
        puts shards.map(&:shard_id)
      end
    end

    desc 'get_records ARN SHARD_ID', 'get records for given stream and shard'
    def get_records(arn, shard_id)
      iterator = streams.get_shard_iterator(stream_arn: arn, shard_id: shard_id, shard_iterator_type: 'TRIM_HORIZON').shard_iterator

      streams.get_records(shard_iterator: iterator).records.output do |records|
        print_table records.map { |r| [r.event_id, r.event_name, r.dynamodb.sequence_number, r.dynamodb.size_bytes] }
      end
    end
  end
end