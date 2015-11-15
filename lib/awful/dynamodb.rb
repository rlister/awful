module Awful

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
    method_option :read_capacity_units,  aliases: '-r', type: :numeric, default: nil, desc: 'Read capacity units'
    method_option :write_capacity_units, aliases: '-w', type: :numeric, default: nil, desc: 'Write capacity units'
    def throughput(name)
      provisioned = dynamodb.describe_table(table_name: name).table.provisioned_throughput.to_h
      provisioned.merge!(symbolize_keys(options))
      if options.empty?         # just print current throughput
        provisioned.tap do |p|
          puts YAML.dump(stringify_keys(p))
        end
      else                      # update from options
        dynamodb.update_table(table_name: name, provisioned_throughput: only_keys_matching(provisioned, %i[read_capacity_units write_capacity_units]))
      end
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

    end

    desc 'copy SRC DEST', 'copy data from table region/SRC to table region/DEST'
    method_option :dots, aliases: '-d', default: false, desc: 'Show dots for put_item progress'
    def copy(src, dst)
      src_table, src_region = src.split('/').reverse # parse region/table into [table, region]
      dst_table, dst_region = dst.split('/').reverse

      ## clients are potentially for different regions
      src_client = Aws::DynamoDB::Client.new({region: src_region}.reject{|_,v| v.nil?})
      dst_client = Aws::DynamoDB::Client.new({region: dst_region}.reject{|_,v| v.nil?})

      ## lame progress indicator
      dots = options[:dots] ? ->{print '.'} : ->{}

      ## recursive closure to scan some items from src and put to dest;
      ## would be more studly as an anonymous y-combinator, but we should write readable code instead
      scan_and_put = ->(myself, key) {
        r = src_client.scan(table_name: src_table, exclusive_start_key: key, return_consumed_capacity: 'INDEXES')
        print "[#{Time.now}] Scanned #{r.count} items; last evaluated key: #{r.last_evaluated_key}"
        r.items.each do |item|
          dst_client.put_item(table_name: dst_table, item: item)
          dots.call #progress
        end
        print "\n"

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
    def put_items(name, file = nil)
      io = (file and File.open(file)) || ((not $stdin.tty?) and $stdin)
      count = 0
      io.each_line do |line|
        dynamodb_simple.put_item('TableName' => name, 'Item' => JSON.parse(line))
        count += 1
      end
      count.tap { |c| puts "put #{c} items" }
    end

  end

end
