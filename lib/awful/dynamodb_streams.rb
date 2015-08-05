module Awful

  class DynamoDBStreams < Cli

    desc 'ls [PATTERN]', 'list dynamodb streams [matching PATTERN]'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(table_name = nil, exclusive_start_stream_arn = nil)
      opts = {
        table_name: table_name,
        exclusive_start_stream_arn: exclusive_start_stream_arn
      }.reject{ |_,v| v.nil? }

      r = dynamodb_streams.list_streams(opts)

      streams = r.streams.tap do |list|
        if options[:long]
          print_table list.map{ |s| [s.stream_arn, s.table_name, s.stream_label] }
        else
          puts list.map(&:stream_arn)
        end
      end

      ## recurse if there is more data to fetch
      if r.last_evaluated_stream_arn
        streams += ls(table_name, r.last_evaluated_stream_arn)
      end

      streams
    end

    desc 'dump ARN', 'describe the stream with ARN as yaml'
    def dump(arn)
      dynamodb_streams.describe_stream(stream_arn: arn).stream_description.tap do |stream|
        puts YAML.dump(stringify_keys(stream.to_hash))
      end
    end

    desc 'shards ARN', 'list shards for stream with ARN'
    def shards(arn)
      dynamodb_streams.describe_stream(stream_arn: arn).stream_description.shards.tap do |shards|
        puts shards.map(&:shard_id)
      end
    end

    desc 'get_records ARN SHARD_ID', 'get records for given stream and shard'
    def get_records(arn, shard_id)
      iterator = dynamodb_streams.get_shard_iterator(stream_arn: arn, shard_id: shard_id, shard_iterator_type: 'TRIM_HORIZON').shard_iterator

      dynamodb_streams.get_records(shard_iterator: iterator).records.tap do |records|
        print_table records.map { |r| [r.event_id, r.event_name, r.dynamodb.sequence_number, r.dynamodb.size_bytes] }
      end
    end

  end

end
