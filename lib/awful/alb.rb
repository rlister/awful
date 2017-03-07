module Awful
  module Short
    def alb(*args)
      Awful::Alb.new.invoke(*args)
    end
  end

  class Alb < Cli
    COLORS = {
      active:       :green,
      provisioning: :yellow,
      failed:       :red,
      healthy:      :green,
      unhealthy:    :red,
      InService:    :green,
      OutOfService: :red,
    }

    no_commands do
      def color(string)
        set_color(string, COLORS.fetch(string.to_sym, :yellow))
      end

      def alb
        @alb ||= Aws::ElasticLoadBalancingV2::Client.new
      end

      def describe_load_balancers(*names)
        next_marker = nil
        albs = []
        loop do
          response = alb.describe_load_balancers(names: names, marker: next_marker)
          albs += response.load_balancers
          next_marker = response.next_marker
          break unless next_marker
        end
        albs
      end

      ## return ARN for named ALB
      def get_arn(name_or_arn)
        if name_or_arn.start_with?('arn:')
          name_or_arn           # it is already an arn
        else
          describe_load_balancers(name_or_arn).first.load_balancer_arn
        end
      end

      def get_tag(name, key)
        alb.describe_tags(resource_arns: [get_arn(name)]).tag_descriptions.first.tags.find do |tag|
          tag.key == key
        end.output do |tag|
          puts tag.value if tag
        end
      end

      def add_tag(name, key, value)
        alb.add_tags(resource_arns: [get_arn(name)], tags: [{key: key, value: value}])
      end

      def remove_tags(name, *keys)
        alb.remove_tags(resource_arns: [get_arn(name)], tag_keys: keys)
      end
    end

    desc 'ls [NAMES]', 'list application load-balancers'
    method_option :long,     aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    method_option :matching, aliases: '-m', type: :string,  default: nil,   desc: 'return matching ALB names'
    def ls(*names)
      describe_load_balancers(*names).tap do |albs|
        albs.select! { |a| a.load_balancer_name.match(options[:matching]) } if options[:matching]
      end.output do |list|
        if options[:long]
          print_table list.map { |a| [a.load_balancer_name, a.dns_name, color(a.state.code), a.vpc_id, a.created_time] }
        else
          puts list.map(&:load_balancer_name)
        end
      end
    end

    desc 'dump NAMES', 'dump ALB details'
    def dump(*names)
      describe_load_balancers(*names).output do |albs|
        albs.each do |alb|
          puts YAML.dump(stringify_keys(alb.to_hash))
        end
      end
    end

    desc 'listeners NAME', 'list listeners for ALB with NAME'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def listeners(name)
      alb.describe_listeners(load_balancer_arn: get_arn(name)).listeners.output do |listeners|
        if options[:long]
          print_table listeners.map { |l|
            [l.protocol, l.port, l.ssl_policy, l.certificates.join(','), l.listener_arn]
          }.sort
        else
          puts listeners.map(&:listener_arn)
        end
      end
    end

    desc 'targets NAME', 'list target groups for ALB with NAME or ARN'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def targets(name)
      alb.describe_target_groups(load_balancer_arn: get_arn(name)).target_groups.output do |target_groups|
        if options[:long]
          print_table target_groups.map { |t|
            [t.target_group_name, t.port, t.protocol, t.vpc_id]
          }
        else
          puts target_groups.map(&:target_group_name)
        end
      end
    end

    desc 'instances NAME', 'list instances and health for ALB with NAME or ARN'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def instances(name)
      alb.describe_target_groups(load_balancer_arn: get_arn(name)).target_groups.map do |tg|
        alb.describe_target_health(target_group_arn: tg.target_group_arn).target_health_descriptions
      end.flatten(1).output do |targets|
        if options[:long]
          print_table targets.map { |t|
            [t.target.id, t.target.port, color(t.target_health.state), t.target_health.reason, t.target_health.description]
          }
        else
          puts targets.map{ |t| t.target.id }
        end
      end
    end

    desc 'rules LISTENER', 'list rules for listener'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def rules(listener)
      alb.describe_rules(listener_arn: listener).rules.output do |rules|
        if options[:long]
          print_table rules.map { |r|
            [r.priority, r.rule_arn]
          }
        else
          puts rules.map(&:rule_arn)
        end
      end
    end

    desc 'tags NAMES', 'get tags for ALBs'
    def tags(*names)
      alb.describe_tags(resource_arns: names.map(&method(:get_arn))).tag_descriptions.output do |albs|
        albs.each do |alb|
          print_table alb.tags.map{ |t| [t.key, t.value] }
        end
      end
    end

    desc 'tag NAME KEY [VALUE]', 'get/set value of a single tag for given ALB'
    method_option :delete, type: :boolean, default: false, desc: 'delete tag'
    def tag(name, key, value = nil)
      if options[:delete]
        remove_tags(name, key)
      elsif value
        add_tag(name, key, value)
      else
        get_tag(name, key)
      end
    end

  end
end