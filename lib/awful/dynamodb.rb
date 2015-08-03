module Awful

  class DynamoDB < Cli

    desc 'ls [PATTERN]', 'list dynamodb tables [matching PATTERN]'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      tables = dynamodb.list_tables.table_names.select do |table|
        table.match(name)
      end

      if options[:long]
        tables.map do |table|
          dynamodb.describe_table(table_name: table).table
        end.tap do |list|
          print_table list.map { |t| [ t.table_name, t.table_status, t.item_count, t.table_size_bytes, t.creation_date_time ] }
        end
      else
        tables.tap { |t| puts t }
      end
    end

    desc 'dump NAME', 'dump table with name'
    def dump(name)
      dynamodb.describe_table(table_name: name).table.tap do |table|
        puts YAML.dump(stringify_keys(table.to_hash))
      end
    end

    desc 'scan NAME', 'scan table with NAME'
    def scan(name, start_key = nil)
      r = dynamodb.scan(table_name: name, exclusive_start_key: start_key) #.items.tap{ |x| p x.count }.tap do |table|
      puts r.items.map { |item| JSON.generate(item) }.join("\n")
      if r.last_evaluated_key # recurse if more data to get
        scan(name, r.last_evaluated_key)
      end
    end
  end

end
