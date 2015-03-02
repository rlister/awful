module Awsm

  class Ec2 < Thor
    include Awsm

    desc 'ls [PATTERN]', 'list EC2 instances [with id or tags matching PATTERN]'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      fields = options[:long] ?
        ->(i) { [ tag_name(i) || '-', i.instance_id, i.instance_type, i.virtualization_type, i.placement.availability_zone, i.state.name,
                  i.security_groups.map(&:group_name).join(','), i.private_ip_address, i.public_ip_address ] } :
        ->(i) { [ tag_name(i) || i.instance_id ] }

      ec2.describe_instances.map(&:reservations).flatten.map(&:instances).flatten.select do |instance|
        instance.instance_id.match(name) or instance.tags.any? { |tag| tag.value.match(name) }
      end.map do |instance|
        fields.call(instance)
      end.tap do |list|
        print_table list.sort
      end
    end

    desc 'dump NAME', 'dump EC2 instance with id or tag NAME as yaml'
    def dump(name)
      ec2.describe_instances.map(&:reservations).flatten.map(&:instances).flatten.find do |instance|
        instance.instance_id == name or tag_name(instance) == name
      end.tap do |instance|
        puts YAML.dump(stringify_keys(instance.to_hash))
      end
    end

    desc 'create NAME', 'run new EC2 instance'
    def create(name)
      opt = load_cfg
      whitelist = %i[image_id min_count max_count key_name security_group_ids user_data instance_type kernel_id
                     ramdisk_id  monitoring subnet_id disable_api_termination instance_initiated_shutdown_behavior
                     additional_info iam_instance_profile ebs_optimized]

      opt[:min_count] ||= 1
      opt[:max_count] ||= 1
      opt[:monitoring] = {enabled: opt.fetch(:monitoring, {}).fetch(:state, '') == 'enabled'}

      ## TODO: block_device_mappings
      ## TODO: network_interfaces
      ## TODO: placement

      opt[:security_group_ids] = opt.fetch(:security_groups, []).map { |sg| sg[:group_id] }
      opt = remove_empty_strings(opt)

      ec2.run_instances(only_keys_matching(opt, whitelist)).tap do |response|
        response.instances.map(&:instance_id).tap do |ids|
          ec2.create_tags(resources: ids, tags: opt[:tags]) # tag instances
          puts ids # report new instance ids
        end
      end
    end

    desc 'allocate', 'allocate a new elastic IP address'
    def allocate
      ec2.allocate_address(domain: 'vpc').map do |eip|
        puts eip.allocation_id, eip.public_ip
      end
    end

    desc 'associate NAME IP', 'associate a public ip with an instance'
    def associate(name, eip)
      ec2.associate_address(instance_id: find_instance(name), allocation_id: eip).map(&:association_id).tap do |id|
        puts id
      end
    end

    desc 'addresses', 'list elastic IP addresses'
    def addresses
      ec2.describe_addresses.map(&:addresses).flatten.map do |ip|
        [ ip.allocation_id, ip.public_ip, ip.instance_id, ip.domain ]
      end.tap do |list|
        print_table list
      end
    end

    desc 'delete NAME', 'terminate a running instance'
    def delete(name)
      id =
        if name.match(/^i-[\d[a-f]]{8}$/)
          name
        else
          ec2.describe_instances.map(&:reservations).flatten.map(&:instances).flatten.find do |instance|
            tag_name(instance) == name
          end.instance_id
        end
      if yes? "Really terminate instance #{name} (#{id})?", :yellow
        ec2.terminate_instances(instance_ids: Array(id))
      end
    end

  end

end
