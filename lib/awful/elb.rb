module Awful

  class Elb < Cli

    desc 'ls [PATTERN]', 'list vpcs [with any tags matching PATTERN]'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      fields = options[:long] ?
        ->(e) { [e.load_balancer_name, e.instances.length, e.availability_zones.join(','), e.dns_name] } :
        ->(e) { [e.load_balancer_name] }

      elb.describe_load_balancers.map(&:load_balancer_descriptions).flatten.select do |elb|
        elb.load_balancer_name.match(name)
      end.map do |elb|
        fields.call(elb)
      end.tap do |list|
        print_table list
      end
    end

    desc 'instances NAME', 'list instances and states for elb NAME'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def instances(name)
      instances = elb.describe_instance_health(load_balancer_name: name).map(&:instance_states).flatten
      if instances.empty?
        instances.tap { puts 'no instances' }
      else
        instances_by_id = instances.inject({}) { |hash,instance| hash[instance.instance_id] = instance; hash }
        if options[:long]
          ec2.describe_instances(instance_ids: instances_by_id.keys).map(&:reservations).flatten.map(&:instances).flatten.map do |instance|
            health = instances_by_id[instance.instance_id]
            [ instance.instance_id, instance.tags.map(&:value).sort.join(','), instance.public_ip_address, health.state, health.reason_code, health.description ]
          end.tap do |list|
            print_table list
          end
        else
          instances_by_id.keys.tap { |list| puts list }
        end
      end
    end

    desc 'dump NAME', 'dump VPC with id or tag NAME as yaml'
    def dump(name)
      lb = elb.describe_load_balancers(load_balancer_names: Array(name)).map(&:load_balancer_descriptions).flatten.first.to_hash
      puts YAML.dump(stringify_keys(lb))
    end

    desc 'dns NAME', 'get DNS name for load-balancers matching NAME'
    def dns(name)
      elb.describe_load_balancers.map(&:load_balancer_descriptions).flatten.select do |elb|
        elb.load_balancer_name.match(name)
      end.map(&:dns_name).tap do |dns|
        puts dns
      end
    end

    desc 'create NAME', 'create new load-balancer'
    def create(name)
      whitelist = %i[load_balancer_name listeners availability_zones subnets security_groups scheme tags]
      opt = load_cfg
      opt[:load_balancer_name] = name
      opt[:listeners] = opt.fetch(:listener_descriptions, []).map { |l| l[:listener] }
      opt.delete(:availability_zones) unless opt.fetch(:subnets, []).empty?
      opt = remove_empty_strings(opt)
      opt = only_keys_matching(opt, whitelist)
      elb.create_load_balancer(opt).map(&:dns_name).flatten.tap { |dns| puts dns }
      health_check(name) if opt[:health_check]
    end

    desc 'health_check NAME', 'set health-check'
    method_option :target,              aliases: '-t', default: nil, desc: 'Health check target'
    method_option :interval,            aliases: '-i', default: nil, desc: 'Check interval'
    method_option :timeout,             aliases: '-o', default: nil, desc: 'Check timeout'
    method_option :unhealthy_threshold, aliases: '-u', default: nil, desc: 'Unhealthy threshold'
    method_option :healthy_threshold,   aliases: '-h', default: nil, desc: 'Healthy threshold'
    def health_check(name)
      opt = load_cfg.merge(options.reject(&:nil?))
      hc = elb.configure_health_check(load_balancer_name: name, health_check: opt[:health_check])
      hc.map(&:health_check).flatten.first.tap do |h|
        print_table h.to_hash
      end
    end

    desc 'delete NAME', 'delete load-balancer'
    def delete(name)
      if yes? "really delete ELB #{name}?", :yellow
        elb.delete_load_balancer(load_balancer_name: name)
      end
    end

    desc 'register INSTANCES', 'register listed instance IDs with ELB'
    def register(name, *instance_ids)
      elb.register_instances_with_load_balancer(load_balancer_name: name, instances: instance_ids.map{ |id| {instance_id: id} })
    end

    desc 'deregister INSTANCES', 'deregister listed instance IDs from ELB'
    def deregister(name, *instance_ids)
      elb.deregister_instances_from_load_balancer(load_balancer_name: name, instances: instance_ids.map{ |id| {instance_id: id} })
    end

    desc 'state [INSTANCE_IDS]', 'show health state for all instances, or listed instance ids'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def state(name, *instance_ids)
      elb.describe_instance_health(load_balancer_name: name, instances: instance_ids.map { |id| {instance_id: id} }).instance_states.tap do |instances|
        if options[:long]
          print_table instances.map { |i| [ i.instance_id, i.state, i.reason_code, i.description ] }
        else
          puts instances.map { |i| i.state }
        end
      end
    end
  end

end
