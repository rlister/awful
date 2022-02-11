module Awful
  module Short
    def config(*args)
      Awful::Config.new.invoke(*args)
    end
  end

  class Config < Cli
    COLORS = {
      ACTIVE:            :green,
      DELETING:          :red,
      DELETING_RESULTS:  :red,
      EVALUATING:        :yellow,
      COMPLIANT:         :green,
      NON_COMPLIANT:     :red,
      NOT_APPLICABLE:    :yellow,
      INSUFFICIENT_DATA: :yellow,
    }

    no_commands do
      def config
        @_config ||= Aws::ConfigService::Client.new
      end
    end

    desc 'recorders', 'show delivery recorders'
    def recorders
      config.describe_configuration_recorders.configuration_recorders.output do |list|
        ## there is likely only one, so dump it
        puts YAML.dump(list.map{ |recorder| stringify_keys(recorder.to_hash) })
      end
    end

    desc 'channels', 'list delivery channels'
    def channels
      config.describe_delivery_channels.delivery_channels.output do |list|
        ## there is likely only one, so dump it
        puts YAML.dump(list.map{ |channel| stringify_keys(channel.to_hash) })
      end
    end

    desc 'rules [NAMES]', 'list config rules'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def rules(*names)
      paginate(:config_rules) do |next_token|
        config.describe_config_rules(config_rule_names: names)
      end.output do |rules|
        if options[:long]
          print_table rules.map { |r|
            s = r.source
            [r.config_rule_name, r.config_rule_id, color(r.config_rule_state), r.maximum_execution_frequency, s.owner, s.source_identifier]
          }
        else
          puts rules.map(&:config_rule_name)
        end
      end
    end

    desc 'dump NAMES', 'get configuration for rules'
    def dump(*names)
      config.describe_config_rules(config_rule_names: names).config_rules.output do |list|
        puts YAML.dump(list.map{ |rule| stringify_keys(rule.to_hash) })
      end
    end

    desc 'compliance RULE', 'get compliance status for rule'
    def compliance(rule)
      paginate(:evaluation_results) do |next_token|
          config.get_compliance_details_by_config_rule(config_rule_name: rule, next_token: next_token)
      end.output do |results|
        print_table results.map { |r|
          q = r.evaluation_result_identifier.evaluation_result_qualifier
          [q.resource_type, q.resource_id, color(r.compliance_type), r.result_recorded_time]
        }
      end
    end

    desc 'evaluate NAMES', 'run on-demand evaluation for rules'
    def evaluate(*names)
      config.start_config_rules_evaluation(config_rule_names: names)
    end

  end
end
