require 'base64'

module Awful

  class LaunchConfig < Cli

    desc 'ls [NAMES]', 'list launch configurations'
    method_option :long,  aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    method_option :match, aliases: '-m', type: :string,  default: nil,   desc: 'filter by matching name'
    def ls(*names)
      paginate(:launch_configurations) do |token|
        autoscaling.describe_launch_configurations(launch_configuration_names: names, next_token: token)
      end.tap do |lcs|
        lcs.select! { |lc| lc.launch_configuration_name.match(options[:match]) } if options[:match]
      end.output do |lcs|
        if options[:long]
          print_table lcs.map { |lc|
            [lc.launch_configuration_name, lc.image_id, lc.instance_type, lc.created_time]
          }
        else
          puts lcs.map(&:launch_configuration_name)
        end
      end
    end

    desc 'delete NAME', 'delete launch configuration'
    def delete(name)
      autoscaling.delete_launch_configuration(launch_configuration_name: name)
    end

    desc 'clean NAME [NUM]', 'delete oldest NUM launch configs matching NAME'
    def clean(name, num = 1)
      autoscaling.describe_launch_configurations.map(&:launch_configurations).flatten.select do |lc|
        lc.launch_configuration_name.match(name)
      end.sort_by(&:created_time).first(num.to_i).map(&:launch_configuration_name).tap do |names|
        puts names
        if yes? 'delete these launch configs?', :yellow
          names.each do |n|
            autoscaling.delete_launch_configuration(launch_configuration_name: n)
          end
        end
      end
    end

    desc 'dump NAME', 'dump existing launch_configuration as yaml'
    method_option :match, aliases: '-m', type: :string, default: nil, desc: 'filter by matching name'
    def dump(*names)
      paginate(:launch_configurations) do |token|
        autoscaling.describe_launch_configurations(launch_configuration_names: names, next_token: token)
      end.tap do |lcs|
        lcs.select! { |lc| lc.launch_configuration_name.match(options[:match]) } if options[:match]
      end.output do |lcs|
        lcs.each do |lc|
          lc[:user_data] = Base64.decode64(lc[:user_data])
          puts YAML.dump(stringify_keys(lc.to_hash))
        end
      end
    end

    desc 'latest', 'latest'
    def latest(name)
      autoscaling.describe_launch_configurations.map(&:launch_configurations).flatten.select do |lc|
        lc.launch_configuration_name.match(/^#{name}/)
      end.sort_by(&:created_time).last.launch_configuration_name.tap do |latest|
        puts latest
      end
    end

    desc 'create NAME [FILE]', 'create a new launch configuration'
    method_option :timestamp,                 aliases: '-t', type: :boolean, default: false, desc: 'Add timestamp to launch config name'
    method_option :launch_configuration_name, aliases: '-n', type: :string,  default: nil,   desc: 'launch configuration name'
    method_option :image_id,                  aliases: '-i', type: :string,  default: nil,   desc: 'image ID (AMI to use)'
    def create(file = nil)
      opt = load_cfg(options, file)

      whitelist = %i[launch_configuration_name image_id key_name security_groups classic_link_vpc_id classic_link_vpc_security_groups user_data
                     instance_id instance_type kernel_id ramdisk_id block_device_mappings instance_monitoring spot_price iam_instance_profile
                     ebs_optimized associate_public_ip_address placement_tenancy]

      if options[:timestamp]
        opt[:launch_configuration_name] += "-#{Time.now.utc.strftime('%Y%m%d%H%M%S')}"
      end

      opt[:user_data] = Base64.encode64(opt[:user_data]) # encode user data
      opt = remove_empty_strings(opt)
      opt = only_keys_matching(opt, whitelist)
      autoscaling.create_launch_configuration(opt)
      opt[:launch_configuration_name].tap do |name|
        puts name
      end
    end

  end

end
