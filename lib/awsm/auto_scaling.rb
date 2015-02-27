module Awsm

  class AutoScaling < Thor
    include Awsm

    desc 'ls [PATTERN]', 'list autoscaling groups with name matching PATTERN'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      fields = if options[:long]
                 ->(a) { [
                           a.auto_scaling_group_name,
                           a.launch_configuration_name,
                           "#{a.instances.length}/#{a.desired_capacity}",
                           "#{a.min_size}-#{a.max_size}",
                           a.availability_zones.sort.join(','),
                           a.created_time
                         ] }
               else
                 ->(a) { [ a.auto_scaling_group_name ] }
               end

      autoscaling.describe_auto_scaling_groups.map(&:auto_scaling_groups).flatten.select do |asg|
        asg.auto_scaling_group_name.match(name)
      end.map do |asg|
        fields.call(asg)
      end.tap do |list|
        print_table list
      end
    end

    desc 'delete NAME', 'delete autoscaling group'
    def delete(name)
      autoscaling.delete_auto_scaling_group(auto_scaling_group_name: name)
    end

    desc 'instances', 'list instance IDs for instances in groups matching NAME'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def instances(name)
      fields = options[:long] ? %i[instance_id auto_scaling_group_name availability_zone lifecycle_state health_status launch_configuration_name] : %i[instance_id]

      autoscaling.describe_auto_scaling_instances.map(&:auto_scaling_instances).flatten.select do |instance|
        instance.auto_scaling_group_name.match(name)
      end.map do |instance|
        fields.map { |field| instance.send(field) }
      end.tap do |list|
        print_table list
      end

    end

    desc 'ips NAME', 'list IPs for instances in groups matching NAME'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ips(name)
      fields = options[:long] ? %i[public_ip_address private_ip_address instance_id image_id instance_type launch_time] : %i[ public_ip_address ]

      instance_ids = autoscaling.describe_auto_scaling_instances.map(&:auto_scaling_instances).flatten.select do |instance|
        instance.auto_scaling_group_name.match(name)
      end.map(&:instance_id)

      ec2 = Aws::EC2::Client.new
      ec2.describe_instances(instance_ids: instance_ids).map(&:reservations).flatten.map(&:instances).flatten.map do |instance|
        fields.map { |field| instance.send(field) }
      end.tap do |list|
        print_table list
      end
    end

    desc 'dump NAME', 'dump existing autoscaling group as yaml'
    def dump(name)
      asg = autoscaling.describe_auto_scaling_groups(auto_scaling_group_names: Array(name)).map(&:auto_scaling_groups).flatten.first.to_hash
      puts YAML.dump(stringify_keys(asg))
    end

    desc 'create NAME', 'create a new auto-scaling group'
    def create(name)
      opt = load_cfg
      whitelist = %i[auto_scaling_group_name launch_configuration_name instance_id min_size max_size desired_capacity default_cooldown availability_zones
                     load_balancer_names health_check_type health_check_grace_period placement_group vpc_zone_identifier termination_policies tags ]

      opt[:auto_scaling_group_name] = name
      opt = remove_empty_strings(opt)
      opt = only_keys_matching(opt, whitelist)

      ## scrub aws-provided keys from tags
      opt[:tags] = opt.has_key?(:tags) ? opt[:tags].map { |tag| only_keys_matching(tag, %i[key value propagate_at_launch]) } : []

      autoscaling.create_auto_scaling_group(opt)
      autoscaling.create_or_update_tags(resource_id: name, resource_type: 'auto-scaling-group', tags: opt[:tags])
    end

    desc 'update NAME', 'update existing auto-scaling group'
    def update(name)
      opt = load_cfg
      whitelist = %i[auto_scaling_group_name launch_configuration_name min_size max_size desired_capacity default_cooldown availability_zones
                     health_check_type health_check_grace_period placement_group vpc_zone_identifier termination_policies ]

      ## cleanup the group options
      opt[:auto_scaling_group_name] = name
      opt = remove_empty_strings(opt)

      ## update the group
      autoscaling.update_auto_scaling_group(only_keys_matching(opt, whitelist))

      ## update any tags
      if opt[:tags]
        tags = opt[:tags].map { |tag| tag.merge(resource_id: name, resource_type: 'auto-scaling-group') }
        autoscaling.create_or_update_tags(tags: tags)
      end
    end

  end

end
