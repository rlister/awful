module Awful

  class Ecs < Cli

    COLORS = {
      ACTIVE:   :green,
      INACTIVE: :red,
      true:     :green,
      false:    :red,
      RUNNING:  :green,
      STOPPED:  :red,
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

        ## get hash of tags for each instance id
        tags = ec2.describe_instances(instance_ids: container_instances.map(&:ec2_instance_id)).
               map(&:reservations).flatten.
               map(&:instances).flatten.
               each_with_object({}) do |i,h|
          h[i.instance_id] = tag_name(i, '--')
        end

        print_table container_instances.each_with_index.map { |ins, i|
          [
            tags[ins.ec2_instance_id],
            ins.container_instance_arn.split('/').last,
            ins.ec2_instance_id,
            "agent:#{color(ins.agent_connected.to_s)}",
            color(ins.status),
          ]
        }.sort
      else
        puts arns
      end
    end

    desc 'definitions [FAMILY_PREFIX]', 'task definitions [for FAMILY]'
    method_option :arns,     aliases: '-a', default: false, desc: 'show full ARNs for tasks definitions'
    method_option :inactive, aliases: '-i', default: false, desc: 'show INACTIVE instead of ACTIVE task definitions'
    def definitions(family = nil)
      params = {family_prefix: family, status: options[:inactive] ? 'INACTIVE' : 'ACTIVE'}.reject{|_,v| v.nil?}
      arns = ecs.list_task_definitions(params).task_definition_arns
      if options[:arns]
        arns
      else
        arns.map{|a| a.split('/').last}
      end.tap(&method(:puts))
    end

    desc 'deregister TASK_DEFINITION', 'mark a task definition as INACTIVE'
    def deregister(task)
      ecs.deregister_task_definition(task_definition: task)
    end

    desc 'dump TASK', 'describe details for TASK definition'
    method_option :json, aliases: '-j', default: false, desc: 'dump as json instead of yaml'
    def dump(task)
      ecs.describe_task_definition(task_definition: task).task_definition.to_h.tap do |hash|
        if options[:json]
          puts JSON.pretty_generate(hash)
        else
          puts YAML.dump(stringify_keys(hash))
        end
      end
    end

    desc 'tasks CLUSTER', 'list tasks for CLUSTER'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def tasks(cluster)
      arns = ecs.list_tasks(cluster: cluster).task_arns
      if options[:long]
        tasks = ecs.describe_tasks(cluster: cluster, tasks: arns).tasks
        print_table tasks.map { |task|
          [
            task.task_arn.split('/').last,
            task.task_definition_arn.split('/').last,
            task.container_instance_arn.split('/').last,
            "#{color(task.last_status)} (#{task.desired_status})",
            task.started_by,
          ]
        }
      else
        puts arns
      end
    end

  end
end
