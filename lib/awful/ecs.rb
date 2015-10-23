module Awful

  class Ecs < Cli

    COLORS = {
      ACTIVE:   :green,
      INACTIVE: :red,
    }

    no_commands do
      def ecs
        @ecs ||= Aws::ECS::Client.new
      end

      def color(string)
        set_color(string, COLORS.fetch(string.to_sym, :yellow))
      end
    end

    desc 'ls NAME', 'list ECS clusters'
    method_option :arns, aliases: '-a', default: false, desc: 'List just ARNs'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = '.')
      arns = ecs.list_clusters.cluster_arns.select do |arn|
        arn.split('/').last.match(/#{name}/i)
      end
      ecs.describe_clusters(clusters: arns).clusters.tap do |clusters|
        if options[:arns]
          puts arns
        elsif options[:long]
          print_table clusters.map { |c|
            [
              c.cluster_name,
              color(c.status),
              "instances:#{c.registered_container_instances_count}",
              "pending:#{c.pending_tasks_count}",
              "running:#{c.running_tasks_count}",
            ]
          }
        else
          puts clusters.map(&:cluster_name).sort
        end
      end
    end

    desc 'instances CLUSTER', 'list instances for CLUSTER'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def instances(cluster)
      arns = ecs.list_container_instances(cluster: cluster).container_instance_arns
      if options[:long]
        container_instances = ecs.describe_container_instances(cluster: cluster, container_instances: arns).container_instances
        ec2_instances = ec2.describe_instances(instance_ids: container_instances.map(&:ec2_instance_id)).map(&:reservations).flatten.map(&:instances).flatten
        print_table container_instances.each_with_index.map { |ins, i|
          [
            tag_name(ec2_instances[i]),
            ins.container_instance_arn.split('/').last,
            ins.ec2_instance_id,
            "agent:#{ins.agent_connected}",
            color(ins.status),
          ]
        }
      else
        puts arns
      end
    end
  end
end
