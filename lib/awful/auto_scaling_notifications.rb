module Awful

  class AutoScalingNotifications < Cli

    desc 'ls [NAMES]', 'describe notification configurations for named groups'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(*names)
      autoscaling.describe_notification_configurations(auto_scaling_group_names: names).notification_configurations.tap do |notifications|
        if options[:long]
          print_table notifications.map { |n| [n.auto_scaling_group_name, n.notification_type, n.topic_arn] }
        else
          puts notifications.map(&:notification_type)
        end
      end
    end

    desc 'types', 'describe auto-scaling notification types'
    def types
      autoscaling.describe_auto_scaling_notification_types.auto_scaling_notification_types.tap do |types|
        puts types
      end
    end

  end

end
