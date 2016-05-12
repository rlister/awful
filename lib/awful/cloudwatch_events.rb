module Awful
  module Short
    def cwevents(*args)
      Awful::CloudWatchEvents.new.invoke(*args)
    end
  end

  class CloudWatchEvents < Cli
    COLORS = {
      ENABLED:  :green,
      DISABLED: :yellow,
    }

    no_commands do
      def events
        @events ||= Aws::CloudWatchEvents::Client.new
      end

      def color(string)
        set_color(string, COLORS.fetch(string.to_sym, :yellow))
      end
    end

    desc 'ls [PREFIX]', 'list events'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(prefix = nil)
      next_token = nil
      rules = []
      loop do
        response = events.list_rules(name_prefix: prefix, next_token: next_token)
        rules = rules + response.rules
        next_token = response.next_token
        break if next_token.nil?
      end

      rules.tap do |list|
        if options[:long]
          print_table list.map { |r|
            [
              r.name,
              color(r.state),
              r.schedule_expression,
              r.description,
            ]
          }
        else
          puts list.map(&:name)
        end
      end
    end

    desc 'dump NAME', 'describe named rule'
    def dump(name)
      events.describe_rule(name: name).tap do |rule|
        puts YAML.dump(stringify_keys(rule.to_hash))
      end
    end

    desc 'targets NAME', 'list targets for named rule'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def targets(name)
      next_token = nil
      targets = []
      loop do
        response = events.list_targets_by_rule(rule: name)
        targets = targets + response.targets
        next_token = response.next_token
        break if next_token.nil?
      end
      targets.tap do |list|
        if options[:long]
          print_table list.map { |t| [t.id, t.arn, t.input, t.input_path] }
        else
          puts list.map(&:arn)
        end
      end
    end

  end
end