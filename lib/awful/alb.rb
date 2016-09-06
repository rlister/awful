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

  end
end