module Awful
  module Short
    def lambda_events(*args)
      Awful::Events.new.invoke(*args)
    end
  end

  class Events < Cli
    COLORS = {
      OK:       :green,
      PROBLEM:  :red,
      Enabled:  :green,
      Disabled: :red
    }

    desc 'ls [FUNCTION_NAME]', 'list event source mappings'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    def ls(name = nil)
      lambda.list_event_source_mappings(function_name: name).event_source_mappings.tap do |sources|
        if options[:long]
          print_table sources.map { |s|
            [
              s.uuid,
              color(s.state),
              "Batch size: #{s.batch_size}",
              "Last result: #{color(s.last_processing_result.scan(/\w+/).first)}",
              s.last_modified
            ]
          }
        else
          puts sources.map(&:uuid)
        end
      end
    end

    desc 'dump UUID', 'get config details for given mapping'
    def dump(uuid)
      lambda.get_event_source_mapping(uuid: uuid).tap do |details|
        puts YAML.dump(stringify_keys(details.to_hash))
      end
    end

    desc 'create FUNCTION_NAME EVENT_SOURCE_ARN', 'identify a stream as an event source for a lambda function'
    method_option :enabled,           type: :boolean, default: true,           desc: 'Lambda should begin polling the event source'
    method_option :batch_size,        type: :numeric, default: 1,              desc: 'The largest number of records that lambda will retrieve'
    method_option :starting_position, type: :string,  default: 'TRIM_HORIZON', desc: 'Posn to start reading: TRIM_HORIZON, LATEST'
    def create(name, src)
      lambda.create_event_source_mapping(
        function_name: name,
        event_source_arn: src,
        enabled: options[:enabled],
        batch_size: options[:batch_size],
        starting_position: options[:starting_position]
      )
    end

    desc 'delete UUID', 'delete event source mapping with given id'
    def delete(uuid)
      if yes?("Really delete event source mapping #{uuid}?")
        lambda.delete_event_source_mapping(uuid: uuid)
      end
    end
  end
end
