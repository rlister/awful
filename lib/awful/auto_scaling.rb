module Awful
  module Short
    def asg(*args)
      Awful::AutoScaling.new.invoke(*args)
    end
  end

  class AutoScaling < Cli
    COLORS = {
      ## lifecycle states
      Pending:     :yellow,
      InService:   :green,
      Terminating: :red,
      ## health statuses
      Healthy:     :green,
      Unhealthy:   :red,
      ## activity status
      Successful:   :green,
      Failed:      :red,
      Cancelled:   :red,
      ## instance state
      running:    :green,
      stopped:    :yellow,
      terminated: :red,
    }

    no_commands do
      def color(string)
        set_color(string, COLORS.fetch(string.to_sym, :yellow))
      end

      def all_matching_asgs(name)
        autoscaling.describe_auto_scaling_groups.map(&:auto_scaling_groups).flatten.select do |asg|
          asg.auto_scaling_group_name.match(name) or tag_name(asg, '').match(name)
        end
      end
    end

    desc 'ls [PATTERN]', 'list autoscaling groups with name matching PATTERN'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      all_matching_asgs(name).tap do |asgs|
        if options[:long]
          print_table asgs.map { |a|
            [
              tag_name(a, '-')[0,40],
              a.auto_scaling_group_name[0,40],
              a.launch_configuration_name[0,40],
              "#{a.instances.length}/#{a.desired_capacity}",
              "#{a.min_size}-#{a.max_size}",
              a.availability_zones.map{ |az| az[-1,1] }.sort.join(','),
              a.created_time
            ]
          }
        else
          puts asgs.map(&:auto_scaling_group_name)
        end
      end
    end

    desc 'delete NAME', 'delete autoscaling group'
    def delete(name)
      if yes? "Really delete auto-scaling group #{name}?", :yellow
        autoscaling.delete_auto_scaling_group(auto_scaling_group_name: name)
      end
    end

    desc 'instances', 'list instances for instances in groups matching NAME'
    method_option :long,                 aliases: '-l', default: false, desc: 'Long listing'
    method_option :launch_configuration, aliases: '-L', default: false, desc: 'Get instance launch_configs'
    def instances(name)
      all_matching_asgs(name).map(&:instances).flatten.tap do |instances|
        if options[:long]
          print_table instances.map { |i|
            [
              i.instance_id,
              i.availability_zone,
              color(i.lifecycle_state),
              color(i.health_status),
              i.launch_configuration_name,
            ]
          }
        else
          puts instances.map(&:instance_id)
        end
      end
    end

    desc 'ips NAME', 'list IPs for instances in groups matching NAME'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ips(name)
      ## get instance IDs for matching ASGs
      ids = all_matching_asgs(name).map(&:instances).flatten.map(&:instance_id)

      ## get instance details for these IDs
      ec2.describe_instances(instance_ids: ids).map(&:reservations).flatten.map(&:instances).flatten.sort_by(&:launch_time).tap do |instances|
        if options[:long]
          print_table instances.map { |i|
            [ i.public_ip_address, i.private_ip_address, i.instance_id, i.image_id, i.instance_type, i.placement.availability_zone, color(i.state.name), i.launch_time ]
          }
        else
          puts instances.map(&:public_ip_address)
        end
      end

    end

    desc 'ssh NAME [ARGS]', 'ssh to an instance for this autoscaling group'
    method_option :all,        aliases: '-a', default: false, desc: 'ssh to all instances'
    method_option :number,     aliases: '-n', default: 1,     desc: 'number of instances to ssh'
    method_option :login_name, aliases: '-l', default: nil,   desc: 'login name to pass to ssh'
    def ssh(name, *args)
      ips = ips(name).map(&:public_ip_address)
      num = options[:all] ? ips.count : options[:number].to_i
      login_name = options[:login_name] ? "-l #{options[:login_name]}" : ''
      ips.last(num).each do |ip|
        system "ssh #{login_name} #{ip} #{Array(args).join(' ')}"
      end
    end

    desc 'dump NAME', 'dump existing autoscaling group as yaml'
    def dump(name)
      all_matching_asgs(name).map(&:to_hash).tap do |asgs|
        asgs.each do |asg|
          puts YAML.dump(stringify_keys(asg)) unless options[:quiet]
        end
      end
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

      ## allow matching by group name or name tag, but ensure we get only one
      asgs = all_matching_asgs(name)
      if asgs.length < 1
        warn "no match for #{name}"
        return
      elsif asgs.length > 1
        warn "ambiguous match for #{name}:", asgs.map(&:auto_scaling_group_name)
        return
      end

      ## cleanup the group options
      opt[:auto_scaling_group_name] = asgs.first.auto_scaling_group_name
      opt = remove_empty_strings(opt)

      ## update the group
      whitelist = %i[auto_scaling_group_name launch_configuration_name min_size max_size desired_capacity default_cooldown availability_zones
                     health_check_type health_check_grace_period placement_group vpc_zone_identifier termination_policies ]
      autoscaling.update_auto_scaling_group(only_keys_matching(opt, whitelist))

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
            puts "Terminating instance: #{id}"
            autoscaling.terminate_instance_in_auto_scaling_group(instance_id: id, should_decrement_desired_capacity: options[:decrement] && true)
          end
        else
          puts 'Nothing terminated'
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

    desc 'launch_configuration NAMES', 'get launch configs for given ASGs'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def launch_configuration(*names)
      autoscaling.describe_auto_scaling_groups(auto_scaling_group_names: names).map(&:auto_scaling_groups).flatten.each_with_object({}) do |asg, h|
        h[asg.auto_scaling_group_name] = asg.launch_configuration_name
      end.tap do |hash|
        if options[:long]
          print_table hash
        else
          puts hash.values
        end
      end
    end

    desc 'old_instances ASGS', 'Deal with instances that are not on their ASG current launch config'
    method_option :long,       aliases: '-l', default: false, desc: 'Long listing'
    method_option :groups,     aliases: '-g', default: false, desc: 'Just list names of ASGs with outdated instances'
    method_option :detach,     aliases: '-D', default: false, desc: 'Detach old instances from this ASG'
    method_option :decrement,  aliases: '-d', default: false, desc: 'should decrement desired capacity when detaching instances from ASG'
    method_option :deregister, aliases: '-E', default: false, desc: 'Deregister old instances from ELB for this ASG'
    method_option :terminate,  aliases: '-t', default: false, desc: 'Terminate old instances'
    def old_instances(*names)
      asgs = autoscaling.describe_auto_scaling_groups(auto_scaling_group_names: names).map(&:auto_scaling_groups).flatten

      ## get hash of old instances by ASG name
      olds = asgs.each_with_object({}) do |asg, hash|
        outdated = asg.instances.select do |instance|
          instance.launch_configuration_name != asg.launch_configuration_name
        end
        hash[asg.auto_scaling_group_name] = outdated unless outdated.empty?
      end

      if olds.empty?
        # noop
      elsif options[:detach]
        autoscaling.detach_instances(auto_scaling_group_name: name, instance_ids: olds.values.flatten.map(&:instance_id), should_decrement_desired_capacity: options[:decrement])
      elsif options[:deregister]
        asgs.select do |asg|
          olds.has_key?(asg.auto_scaling_group_name)
        end.each do |asg|
          instance_ids = olds[asg.auto_scaling_group_name].flatten.map(&:instance_id)
          asg.load_balancer_names.each do |elb_name|
            say "Deregistering #{instance_ids.join(',')} from ELB #{elb_name}", :yellow
            elb.deregister_instances_from_load_balancer(load_balancer_name: elb_name, instances: instance_ids.map { |id| {instance_id: id} })
          end
        end
      elsif options[:terminate]
        olds.values.flatten.map do |instance|
          autoscaling.terminate_instance_in_auto_scaling_group(instance_id: instance.instance_id, should_decrement_desired_capacity: options[:decrement] && true)
          instance.instance_id
        end.tap { |ids| say("Terminated: #{ids.join(',')}", :yellow) }
      elsif options[:groups]
        puts olds.keys
      elsif options[:long]
        print_table olds.map { |asg, ins| ins.map { |i| [i.instance_id, asg, i.launch_configuration_name] }.flatten }
      else
        puts olds.values.flatten.map(&:instance_id)
      end

      olds
    end

    desc 'activities ASG', 'describe recent scaling activities for group ASG'
    method_option :long,  aliases: '-l', default: false, desc: 'Long listing'
    method_option :cause, aliases: '-c', default: false, desc: 'Long listing with cause of activity'
    def activities(name)
      autoscaling.describe_scaling_activities(auto_scaling_group_name: name).activities.tap do |activities|
        if options[:long]
          print_table activities.map { |a| [color(a.status_code), a.description, a.start_time, a.end_time] }
        elsif options[:cause]
          print_table activities.map { |a| [color(a.status_code), a.description, a.start_time, a.end_time, "\n#{a.cause}\n\n"] }
        else
          puts activities.map(&:activity_id)
        end
      end
    end

    desc 'enter_standby ASG INSTANCES', 'put instance(s) in standby mode'
    method_option :decrement, type: :boolean, default: true, desc: 'should decrement desired capacity'
    def enter_standby(name, *instances)
      autoscaling.enter_standby(
        auto_scaling_group_name: name,
        instance_ids: instances,
        should_decrement_desired_capacity: options[:decrement]
      )
    end

    desc 'exit_standby ASG INSTANCES', 'remove instance(s) from standby mode'
    def exit_standby(name, *instances)
      autoscaling.exit_standby(auto_scaling_group_name: name, instance_ids: instances)
    end
  end
end