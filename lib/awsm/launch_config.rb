require 'base64'

module Awsm

  class LaunchConfig < Thor
    include Awsm

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

      ## cleanup empty and irrelevant fields
      opt.delete_if { |_,v| v.respond_to?(:empty?) and v.empty? }
      opt[:launch_configuration_name] = "#{name}-#{Time.now.utc.strftime('%Y%m%d%H%M%S')}"
      opt.delete(:created_time)
      opt.delete(:launch_configuration_arn)

      ## encode user data
      opt[:user_data] = Base64.encode64(opt[:user_data])

      autoscaling.create_launch_configuration(opt)
    end

  end

end

Awsm::LaunchConfig.start(ARGV)
