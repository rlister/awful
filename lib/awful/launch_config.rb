require 'base64'

module Awful

  class LaunchConfig < Thor
    include Awful

    desc 'ls [PATTERN]', 'list launch configs with name matching PATTERN'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      fields = options[:long] ? %i[launch_configuration_name image_id instance_type created_time] : %i[launch_configuration_name]
      autoscaling.describe_launch_configurations.map(&:launch_configurations).flatten.select do |lc|
        lc.launch_configuration_name.match(name)
      end.map do |lc|
        fields.map { |field| lc.send(field) }
      end.tap do |list|
        print_table list
      end
    end

    desc 'delete NAME', 'delete launch configuration'
    def delete(name)
      autoscaling.delete_launch_configuration(launch_configuration_name: name)
    end

    desc 'dump NAME', 'dump existing launch_configuration as yaml'
    def dump(name)
      lc = autoscaling.describe_launch_configurations(launch_configuration_names: Array(name)).map(&:launch_configurations).flatten.first.to_hash
      lc[:user_data] = Base64.decode64(lc[:user_data])
      puts YAML.dump(stringify_keys(lc))
    end

    desc 'create [NAME]', 'create a new launch configuration'
    def create(name)
      opt = load_cfg
      whitelist = %i[launch_configuration_name image_id key_name security_groups classic_link_vpc_id classic_link_vpc_security_groups user_data
                     instance_id instance_type kernel_id ramdisk_id block_device_mappings instance_monitoring spot_price iam_instance_profile
                     ebs_optimized associate_public_ip_address placement_tenancy]
      opt[:launch_configuration_name] = "#{name}-#{Time.now.utc.strftime('%Y%m%d%H%M%S')}"
      opt[:user_data] = Base64.encode64(opt[:user_data]) # encode user data
      opt = remove_empty_strings(opt)
      opt = only_keys_matching(opt, whitelist)
      autoscaling.create_launch_configuration(opt)
      puts opt[:launch_configuration_name]
    end

  end

end
