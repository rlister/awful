module Awful
  module Short
    def elb(*args)
      Awful::Elb.new.invoke(*args)
    end
  end

  class Elb < Cli
    COLORS = {
      InService:    :green,
      OutOfService: :red,
    }

    no_commands do
      ## cannot search ELBs by tag, so just name here
      def all_matching_elbs(name)
        elb.describe_load_balancers.map(&:load_balancer_descriptions).flatten.select do |elb|
          elb.load_balancer_name.match(name)
        end
      end

      ## get array of instance_id hashes in form expected by get methods
      def instance_ids(*ids)
        ids.map do |id|
          {instance_id: id}
        end
      end
    end

    desc 'ls [NAME]', 'list load-balancers matching NAME'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    def ls(name = /./)
      all_matching_elbs(name).output do |elbs|
        if options[:long]
          print_table elbs.map { |e|
            [e.load_balancer_name, e.instances.length, e.availability_zones.join(','), e.dns_name]
          }.sort
        else
          puts elbs.map(&:load_balancer_name).sort
        end
      end
    end

    desc 'instances NAME', 'list instances and states for elb NAME'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    def instances(name)
      instances = all_matching_elbs(name).map do |e|
        elb.describe_instance_health(load_balancer_name: e.load_balancer_name).map(&:instance_states)
      end.flatten

      if instances.empty?
        instances.output { puts 'no instances' }
      else
        instances_by_id = instances.inject({}) { |hash,instance| hash[instance.instance_id] = instance; hash }
        if options[:long]
          ec2.describe_instances(instance_ids: instances_by_id.keys).map(&:reservations).flatten.map(&:instances).flatten.map do |instance|
            health = instances_by_id[instance.instance_id]
            instance_name = tag_name(instance) || '-'
            [ instance.instance_id, instance_name, instance.public_ip_address, color(health.state), health.reason_code, health.description ]
          end.output { |list| print_table list }
        else
          instances_by_id.keys.output { |list| puts list }
        end
      end
    end

    desc 'dump NAME', 'dump VPC with id or tag NAME as yaml'
    def dump(name)
      all_matching_elbs(name).map(&:to_hash).output do |elbs|
        elbs.each do |elb|
          puts YAML.dump(stringify_keys(elb))
        end
      end
    end

    desc 'tags NAMES', 'dump tags for ELBs'
    def tags(*names)
      elb.describe_tags(load_balancer_names: names).tag_descriptions.output do |tags|
        tags.each do |tag|
          puts YAML.dump(stringify_keys(tag.to_hash))
        end
      end
    end

    desc 'tag NAME TAG', 'get value of a single tag for given ELB'
    def tag(name, key)
      elb.describe_tags(load_balancer_names: [name]).tag_descriptions.first.tags.find do |tag|
        tag.key == key
      end.output do |tag|
        puts tag.value
      end
    end

    desc 'dns NAME', 'get DNS names for load-balancers matching NAME'
    def dns(name)
      all_matching_elbs(name).map(&:dns_name).output do |dns_names|
        puts dns_names
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
      elb.create_load_balancer(opt).map(&:dns_name).flatten.output { |dns| puts dns }
      health_check(name) if opt[:health_check]
    end

    desc 'health_check NAME', 'set health-check'
    method_option :target,              aliases: '-t', type: :string,  default: nil, desc: 'Health check target'
    method_option :interval,            aliases: '-i', type: :numeric, default: nil, desc: 'Check interval'
    method_option :timeout,             aliases: '-o', type: :numeric, default: nil, desc: 'Check timeout'
    method_option :unhealthy_threshold, aliases: '-u', type: :numeric, default: nil, desc: 'Unhealthy threshold'
    method_option :healthy_threshold,   aliases: '-h', type: :numeric, default: nil, desc: 'Healthy threshold'
    def health_check(name)
      opt = load_cfg.merge(options.reject(&:nil?))
      hc = elb.configure_health_check(load_balancer_name: name, health_check: opt[:health_check])
      hc.map(&:health_check).flatten.first.output do |h|
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
    def register(name, *instances)
      elb.register_instances_with_load_balancer(load_balancer_name: name, instances: instance_ids(*instances))
    end

    desc 'deregister INSTANCES', 'deregister listed instance IDs from ELB'
    def deregister(name, *instances)
      elb.deregister_instances_from_load_balancer(load_balancer_name: name, instances: instance_ids(*instances))
    end

    desc 'state [INSTANCE_IDS]', 'show health state for all instances, or listed instance ids'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    def state(name, *instances)
      elb.describe_instance_health(load_balancer_name: name, instances: instance_ids(*instances)).instance_states.output do |list|
        if options[:long]
          print_table list.map { |i| [ i.instance_id, color(i.state), i.reason_code, i.description ] }
        else
          puts list.map(&:state)
        end
      end
    end
  end
end
