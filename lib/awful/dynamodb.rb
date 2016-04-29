require 'awful/dynamodb_streams'

module Awful
  module Short
    def dyn(*args)
      Awful::DynamoDB.new.invoke(*args)
    end
  end

  class DynamoDB < Cli
    COLORS = {
      CREATING: :yellow,
      UPDATING: :yellow,
      DELETING: :red,
      ACTIVE:   :green,
    }

    no_commands do
      def color(string)
        set_color(string, COLORS.fetch(string.to_sym, :yellow))
      end

      ## return array of tables names matching name
      def all_matching_tables(name)
        dynamodb.list_tables.table_names.select do |table|
          table.match(name)
        end
      end
    end

    desc 'ls [PATTERN]', 'list dynamodb tables [matching PATTERN]'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      tables = all_matching_tables(name)

      if options[:long]
        tables.map do |table|
          dynamodb.describe_table(table_name: table).table
        end.tap do |list|
          print_table list.map { |t| [ t.table_name, color(t.table_status), t.item_count, t.table_size_bytes, t.creation_date_time ] }
        end
      else
        tables.tap { |t| puts t }
      end
    end

    desc 'dump NAME', 'dump table with name'
    def dump(name)
      all_matching_tables(name).map do |table_name|
        dynamodb.describe_table(table_name: table_name).table.to_hash.tap do |table|
          puts YAML.dump(stringify_keys(table))
        end
      end
    end

    desc 'create_table NAME', 'create table with NAME'
    def create_table(name, file = nil)
      opt = load_cfg(options, file)
      params = only_keys_matching(opt, %i[attribute_definitions key_schema])
      params[:table_name] = name
      params[:provisioned_throughput] = only_keys_matching(opt[:provisioned_throughput], %i[read_capacity_units write_capacity_units])

      ## scrub unwanted keys from LSIs
      if opt.has_key?(:local_secondary_indexes)
        params[:local_secondary_indexes] = opt[:local_secondary_indexes].map do |lsi|
          only_keys_matching(lsi, %i[index_name key_schema projection])
        end
      end

      ## scrub unwanted keys from GSIs
      if opt.has_key?(:global_secondary_indexes)
        params[:global_secondary_indexes] = opt[:global_secondary_indexes].map do |gsi|
          only_keys_matching(gsi, %i[index_name key_schema projection]).tap do |g|
            if gsi[:provisioned_throughput]
              g[:provisioned_throughput] = only_keys_matching(gsi[:provisioned_throughput], %i[read_capacity_units write_capacity_units])
            end
          end
        end
      end

      dynamodb.create_table(params)
    end

    desc 'throughput NAME', 'get or update provisioned throughput for table NAME'
    method_option :read_capacity_units,  aliases: '-r', type: :numeric, default: nil,   desc: 'Read capacity units'
    method_option :write_capacity_units, aliases: '-w', type: :numeric, default: nil,   desc: 'Write capacity units'
    method_option :gsi,                  aliases: '-g', type: :array,   default: [],    desc: 'GSIs to update'
    method_option :all,                                 type: :boolean, default: false, desc: 'Update all GSIs for the table'
    method_option :table,                               type: :boolean, default: true,  desc: 'Update througput on table'
    def throughput(name)
      table = dynamodb.describe_table(table_name: name).table

      ## current is hash of current provisioned throughput
      current = table.provisioned_throughput.to_h

      ## loop-safe version of GSIs (in case nil)
      global_secondary_indexes = table.global_secondary_indexes || []

      ## get throughput for each GSI
      global_secondary_indexes.each do |gsi|
        current[gsi.index_name] = gsi.provisioned_throughput.to_h
      end

      ## if no updates requested, just print throughput and return table details
      unless options[:read_capacity_units] or options[:write_capacity_units]
        puts YAML.dump(stringify_keys(current))
        return table
      end

      ## parameters for update request
      params = { table_name: name }

      ## add table throughput unless told not to
      params[:provisioned_throughput] = {
        read_capacity_units:  options[:read_capacity_units]  || current[:read_capacity_units],
        write_capacity_units: options[:write_capacity_units] || current[:write_capacity_units]
      } if options[:table]

      ## list of requested GSIs, or all for this table
      gsis = options[:gsi]
      gsis = global_secondary_indexes.map(&:index_name) if options[:all]
      params[:global_secondary_index_updates] = gsis.map do |gsi|
        {
          update: {
            index_name: gsi,
            provisioned_throughput: {
              read_capacity_units:  options[:read_capacity_units]  || current[gsi][:read_capacity_units],
              write_capacity_units: options[:write_capacity_units] || current[gsi][:write_capacity_units]
            }
          }
        }
      end

      ## make the update request
      params.reject! { |_,v| v.empty? } # sdk hates empty global_secondary_index_updates
      update_table(params)
    end

    desc 'enable_streams NAME', 'enable/disable streams on the table'
    method_option :stream_view_type, aliases: '-t', default: 'NEW_IMAGE', desc: 'view type for the stream (NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES, KEYS_ONLY)'
    method_option :disable,          aliases: '-d', default: false,       desc: 'disable the stream'
    def enable_streams(name)
      stream_specification = {stream_enabled: !options[:disable]}
      stream_specification.merge!(stream_view_type: options[:stream_view_type].upcase) unless options[:disable]
      update_table(table_name: name, stream_specification: stream_specification)
    end

    desc 'delete NAME', 'delete table with NAME'
    def delete_table(name)
      confirmation = ask("to delete #{name} and all its data, type the name of table to delete:", :yellow)
      if confirmation == name
        say("deleting table #{name}")
        dynamodb.delete_table(table_name: name)
      else
        say("confirmation failed for #{name}", :red)
      end
    end

    no_commands do

      ## uses simple_json to get Aws::Plugins::Protocols::JsonRpc output from scan;
      ## this also means request params need to be raw strings and not symbols, etc
      def scan_to_file(name, exclusive_start_key, fd)
        r = dynamodb_simple.scan('TableName' => name, 'ExclusiveStartKey' => exclusive_start_key)
        r['Items'].each do |item|
          fd.puts JSON.generate(item)
        end

        ## recurse if more data to get
        if r.has_key?('LastEvaluatedKey')
          scan_to_file(name, r['LastEvaluatedKey'], fd)
        end
      end


      def update_table(options)
        response = dynamodb.update_table options

        wait_table_update response.data.table_description.table_name, 2
        response
      end


      def wait_table_update table_name, interval
        while current_table_status(table_name) != 'ACTIVE'
          sleep interval
        end
      end


      def current_table_status table_name
        response = dynamodb.describe_table table_name: table_name

        response.data.table.table_status
      end
    end

    desc 'copy [region/]SRC [region/]DEST', 'copy data from table region/SRC to table region/DEST'
    method_option :dots,       aliases: '-d', type: :boolean, default: false, desc: 'Show dots for put_item progress'
    method_option :no_clobber, aliases: '-n', type: :boolean, default: false, desc: 'Do not overwrite existing items'
    def copy(src, dst)
      src_table, src_region = src.split('/').reverse # parse region/table into [table, region]
      dst_table, dst_region = dst.split('/').reverse

      ## clients are potentially for different regions
      src_client = Aws::DynamoDB::Client.new({region: src_region}.reject{|_,v| v.nil?})
      dst_client = Aws::DynamoDB::Client.new({region: dst_region}.reject{|_,v| v.nil?})

      ## params for put_item call
      params = {table_name: dst_table}

      ## add condition not to overwrite existing primary keys (hash or composite hash AND range)
      if options[:no_clobber]
        keys = dst_client.describe_table(table_name: dst_table).table.key_schema.map(&:attribute_name)
        params.merge!(condition_expression: keys.map{|key| "attribute_not_exists(#{key})"}.join(' AND '))
      end

      ## lame progress indicator, pass true for put, false for skip
      dots = options[:dots] ? ->(x){print x ? '.' : 'x'} : ->(_){}

      ## recursive closure to scan some items from src and put to dest;
      ## would be more studly as an anonymous y-combinator, but we should write readable code instead
      scan_and_put = ->(myself, key) {
        r = src_client.scan(table_name: src_table, exclusive_start_key: key, return_consumed_capacity: 'INDEXES')
        print "[#{Time.now}] [#{src_table}] scanned:#{r.count} key:#{r.last_evaluated_key || 'nil'}"
        put = skipped = 0
        r.items.each do |item|
          begin
            dst_client.put_item(params.merge(item: item))
            put += 1
            dots.call(true)
          rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException #item key exists
            skipped += 1
            dots.call(false)
          end
        end
        print "\n"
        puts "[#{Time.now}] [#{dst_table}] put:#{put} skipped:#{skipped}"

        ## recurse if there are more keys to scan
        if r.last_evaluated_key
          myself.call(myself, r.last_evaluated_key)
        end
      }

      ## start scanning data
      scan_and_put.call(scan_and_put, nil)
    end

    desc 'scan NAME', 'scan table with NAME'
    method_option :output, aliases: '-o', type: :string, default: nil, desc: 'Output filename (default: stdout)'
    def scan(name, exclusive_start_key = nil)
      fd = options[:output] ? File.open(options[:output], 'w') : $stdout.dup # open output file or stdout
      scan_to_file(name, exclusive_start_key, fd)
      fd.close
    end

    desc 'put_items NAME', 'puts json items into the table with NAME'
    method_option :no_clobber, aliases: '-n', type: :boolean, default: false, desc: 'Do not overwrite existing items'
    def put_items(name, file = nil)
      params = {'TableName' => name}

      ## set a condition not to overwrite items with existing primary key(s)
      if options[:no_clobber]
        keys = dynamodb.describe_table(table_name: name).table.key_schema.map(&:attribute_name)
        params.merge!('ConditionExpression' => keys.map{|key| "attribute_not_exists(#{key})"}.join(' AND '))
      end

      ## input data
      io = (file and File.open(file)) || ((not $stdin.tty?) and $stdin)

      put_count = 0
      skip_count = 0
      io.each_line do |line|
        begin
          dynamodb_simple.put_item(params.merge('Item' => JSON.parse(line)))
          put_count += 1
        rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException #item key exists
          skip_count += 1
        end
      end

      ## return counts
      [put_count, skip_count].tap do |put, skip|
        puts "put #{put} items, skipped #{skip} items"
      end
    end

    desc 'batch_write NAME', 'batch write items to table NAME'
    def batch_write(name)
      items = (1..25).map do |n|
        {
          put_request: {
            item: {
              "store_id"     => "store#{n}",
              "object_id"    => "object#{n}",
              "object_value" => "value#{n}"
            }
          }
        }
      end
      p items
      r = dynamodb.batch_write_item(request_items: {name => items})
      p r
    end

    ## see lambda_events.rb for subcommands
    desc 'streams SUBCOMMANDS', 'subcommands for dynamodb streams'
    subcommand 'streams', Streams
  end
end