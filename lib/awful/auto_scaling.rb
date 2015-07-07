module Awful

  class AutoScaling < Cli

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
      if yes? "Really delete auto-scaling group #{name}?", :yellow
        autoscaling.delete_auto_scaling_group(auto_scaling_group_name: name)
      end
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
      fields = options[:long] ?
        ->(i) { [ i.public_ip_address, i.private_ip_address, i.instance_id, i.image_id, i.instance_type, i.placement.availability_zone, i.state.name, i.launch_time ] } :
        ->(i) { [ i.public_ip_address ] }

      instance_ids = autoscaling.describe_auto_scaling_instances.map(&:auto_scaling_instances).flatten.select do |instance|
        instance.auto_scaling_group_name.match(name)
      end.map(&:instance_id)

      ec2 = Aws::EC2::Client.new
      ec2.describe_instances(instance_ids: instance_ids).map(&:reservations).flatten.map(&:instances).flatten.sort_by(&:launch_time).map do |instance|
        fields.call(instance)
      end.tap do |list|
        print_table list
      end
    end

    desc 'ssh NAME [ARGS]', 'ssh to an instance for this autoscaling group'
    method_option :all,    aliases: '-a', default: false, desc: 'ssh to all instances'
    method_option :number, aliases: '-n', default: 1,     desc: 'number of instances to ssh'
    def ssh(name, *args)
      ips = ips(name).flatten
      num = options[:all] ? ips.count : options[:number].to_i
      ips.last(num).each do |ip|
        system "ssh #{ip} #{Array(args).join(' ')}"
      end
    end

    desc 'dump NAME', 'dump existing autoscaling group as yaml'
    def dump(name)
      asg = autoscaling.describe_auto_scaling_groups(auto_scaling_group_names: Array(name)).map(&:auto_scaling_groups).flatten.first.to_hash
      puts YAML.dump(stringify_keys(asg))
    end

    desc 'create [FILE]', 'create a new auto-scaling group'
    method_option :auto_scaling_group_name,   aliases: '-n', default: nil, desc: 'Auto-scaling group name'
    method_option :launch_configuration_name, aliases: '-l', default: nil, desc: 'Launch config name'
    method_option :desired_capacity,          aliases: '-d', default: nil, desc: 'Set desired capacity'
    method_option :min_size,                  aliases: '-m', default: nil, desc: 'Set minimum capacity'
    method_option :max_size,                  aliases: '-M', default: nil, desc: 'Set maximum capacity'
    def create(file = nil)
      opt = load_cfg(options, file)
      whitelist = %i[auto_scaling_group_name launch_configuration_name instance_id min_size max_size desired_capacity default_cooldown availability_zones
                     load_balancer_names health_check_type health_check_grace_period placement_group vpc_zone_identifier termination_policies tags ]

      opt = remove_empty_strings(opt)
      opt = only_keys_matching(opt, whitelist)

      ## scrub aws-provided keys from tags
      opt[:tags] = opt.has_key?(:tags) ? opt[:tags].map { |tag| only_keys_matching(tag, %i[key value propagate_at_launch]) } : []

      autoscaling.create_auto_scaling_group(opt)
    end

    desc 'update NAME [FILE]', 'update existing auto-scaling group'
    method_option :desired_capacity,          aliases: '-d', default: nil, desc: 'Set desired capacity'
    method_option :min_size,                  aliases: '-m', default: nil, desc: 'Set minimum capacity'
    method_option :max_size,                  aliases: '-M', default: nil, desc: 'Set maximum capacity'
    method_option :launch_configuration_name, aliases: '-l', default: nil, desc: 'Launch config name'
    def update(name, file = nil)
      opt = load_cfg(options, file)

      whitelist = %i[auto_scaling_group_name launch_configuration_name min_size max_size desired_capacity default_cooldown availability_zones
                     health_check_type health_check_grace_period placement_group vpc_zone_identifier termination_policies ]

      ## cleanup the group options
      opt[:auto_scaling_group_name] = name
      opt = remove_empty_strings(opt)

      ## update the group
      autoscaling.update_auto_scaling_group(only_keys_matching(opt, whitelist))

      # ## update load_balancers if given
      # ## TODO: maybe delete instead if empty?
      # if opt[:load_balancer_names]
      #   autoscaling.attach_load_balancers(auto_scaling_group_name: name, load_balancer_names: opt[:load_balancer_names])
      # end

      ## update any tags
      if opt[:tags]
        tags = opt[:tags].map { |tag| tag.merge(resource_id: name, resource_type: 'auto-scaling-group') }
        autoscaling.create_or_update_tags(tags: tags)
      end
    end

    no_commands do

      ## return array of instances in auto-scaling group sorted by age
      def oldest(name)
        instance_ids = autoscaling.describe_auto_scaling_instances.map(&:auto_scaling_instances).flatten.select do |instance|
          instance.auto_scaling_group_name == name
        end.map(&:instance_id)
        if instance_ids.empty?
          []
        else
          ec2.describe_instances(instance_ids: instance_ids).map(&:reservations).flatten.map(&:instances).flatten.sort_by(&:launch_time)
        end
      end

      ## return array of instances in auto-scaling group, reverse sorted by age, newest first
      def newest(name)
        oldest(name).reverse
      end

    end

    desc 'terminate NAME [NUMBER]', 'terminate NUMBER instances in group NAME'
    method_option :decrement, aliases: '-d', default: false, type: :boolean, desc: 'Decrement desired capacity for each terminated instance'
    method_option :newest,    aliases: '-n', default: false, type: :boolean, desc: 'Delete newest instances instead of oldest'
    method_option :all,       aliases: '-a', default: false, type: :boolean, desc: 'Terminate all instances in group'
    def terminate(name, num = 1)
      ins = options[:newest] ? newest(name) : oldest(name)
      num = ins.length if options[:all] # all instances if requested

      if ins.empty?
        say 'No instances to terminate.', :green
      else
        ids = ins.first(num.to_i).map(&:instance_id)
        if yes? "Really terminate #{num} instances: #{ids.join(',')}?", :yellow
          ids.each do |id|
            autoscaling.terminate_instance_in_auto_scaling_group(instance_id: id, should_decrement_desired_capacity: options[:decrement] && true)
          end
        end
      end
    end

    desc 'stop NAME [NUMBER]', 'stop NUMBER instances in group NAME'
    method_option :newest, aliases: '-n', default: false, type: :boolean, desc: 'Stop newest instances instead of oldest'
    def stop(name, num = 1)
      ins = options[:newest] ? newest(name) : oldest(name)
      ins.first(num.to_i).map(&:instance_id).tap do |ids|
        if yes? "Really stop #{num} instances: #{ids.join(',')}?", :yellow
          ec2.stop_instances(instance_ids: ids)
        end
      end
    end

    desc 'processes', 'describe scaling process types for use with suspend/resume'
    def processes
      autoscaling.describe_scaling_process_types.processes.map(&:process_name).sort.tap do |procs|
        puts procs
      end
    end

    desc 'suspend NAME [PROCS]', 'suspend all [or listed] processes for auto-scaling group NAME'
    method_option :list, aliases: '-l', default: false, type: :boolean, desc: 'list currently suspended processes'
    def suspend(name, *procs)
      if options[:list]
        autoscaling.describe_auto_scaling_groups(auto_scaling_group_names: Array(name)).map(&:auto_scaling_groups).flatten.first.suspended_processes.tap do |list|
          print_table list.map{ |proc| [ proc.process_name, proc.suspension_reason] }
        end
      elsif procs.empty?
        autoscaling.suspend_processes(auto_scaling_group_name: name)
      else
        autoscaling.suspend_processes(auto_scaling_group_name: name, scaling_processes: procs)
      end
    end

    desc 'resume NAME [PROCS]', 'resume all [or listed] processes for auto-scaling group NAME'
    def resume(name, *procs)
      if procs.empty?
        autoscaling.resume_processes(auto_scaling_group_name: name)
      else
        autoscaling.resume_processes(auto_scaling_group_name: name, scaling_processes: procs)
      end
    end

    desc 'attach NAME INSTANCE_IDS', 'attach instances to auto-scaling group and increase desired capacity'
    def attach(name, *instance_ids)
      autoscaling.attach_instances(auto_scaling_group_name: name, instance_ids: instance_ids)
    end

    desc 'detach NAME INSTANCE_IDS', 'detach instances from auto-scaling group'
    method_option :decrement, aliases: '-d', default: false, type: :boolean, desc: 'should decrement desired capacity'
    def detach(name, *instance_ids)
      autoscaling.detach_instances(auto_scaling_group_name: name, instance_ids: instance_ids, should_decrement_desired_capacity: options[:decrement])
    end

  end

end
