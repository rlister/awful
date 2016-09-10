require 'json'

module Awful
  module Short
    def ecs(*args)
      Awful::Ecs.new.invoke(*args)
    end
  end

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
      ecs.describe_clusters(clusters: arns).clusters.output do |clusters|
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

    desc 'create NAME', 'create a new cluster'
    def create(name)
      ecs.create_cluster(cluster_name: name).cluster.output do |cluster|
        puts YAML.dump(stringify_keys(cluster.to_h))
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
      end.output(&method(:puts))
    end

    desc 'families', 'list task definition families'
    def families(prefix = nil)
      next_token = nil
      families = []
      loop do
        response = ecs.list_task_definition_families(family_prefix: prefix, next_token: next_token)
        families += response.families
        next_token = response.next_token
        break unless next_token
      end
      families.output(&method(:puts))
    end

    desc 'register TASKDEF_FAMILY', 'new task definition from the given family, copying current most recent'
    def register(family)
      taskdef = ecs.describe_task_definition(task_definition: family).task_definition # get current newest
      ecs.register_task_definition(
        family: family,
        container_definitions: taskdef.container_definitions,
        volumes: taskdef.volumes
      ).task_definition.output do |td|
        puts td.task_definition_arn
      end
    end

    desc 'deregister TASK_DEFINITION', 'mark a task definition as INACTIVE'
    def deregister(task)
      ecs.deregister_task_definition(task_definition: task)
    end

    desc 'dump TASK', 'describe details for TASK definition'
    method_option :json, aliases: '-j', default: false, desc: 'dump as json instead of yaml'
    def dump(task)
      ecs.describe_task_definition(task_definition: task).task_definition.to_h.output do |hash|
        if options[:json]
          puts JSON.pretty_generate(hash)
        else
          puts YAML.dump(stringify_keys(hash))
        end
      end
    end

    desc 'tasks CLUSTER', 'list tasks for CLUSTER'
    method_option :long,   aliases: '-l', default: false,     desc: 'Long listing'
    method_option :status, aliases: '-s', default: 'running', desc: 'choose status to show: running/pending/stopped'
    def tasks(cluster)
      status = %w[running pending stopped].find{ |s| s.match(/^#{options[:status]}/i) }
      arns = ecs.list_tasks(cluster: cluster, desired_status: status.upcase).task_arns
      if arns.empty?
        []
      elsif options[:long]
        ecs.describe_tasks(cluster: cluster, tasks: arns).tasks.output do |tasks|
          print_table tasks.map { |task|
            [
              task.task_arn.split('/').last,
              task.task_definition_arn.split('/').last,
              task.container_instance_arn.split('/').last,
              "#{color(task.last_status)} (#{task.desired_status})",
              task.started_by,
            ]
          }
        end
      else
        arns.output(&method(:puts))
      end
    end

    desc 'status CLUSTER TASKS', 'describe status for one or more task IDs/ARNs'
    def status(cluster, *tasks)
      ecs.describe_tasks(cluster: cluster, tasks: tasks).tasks.output do |responses|
        responses.each do |response|
          puts YAML.dump(stringify_keys(response.to_h))
        end
      end
    end

    desc 'services CLUSTER', 'list services for a cluster'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def services(cluster)
      arns = ecs.list_services(cluster: cluster).service_arns
      if options[:long]
        print_table ecs.describe_services(cluster: cluster, services: arns).services.map { |svc|
          [
            svc.service_name,
            color(svc.status),
            svc.task_definition.split('/').last,
            "#{svc.running_count}/#{svc.desired_count}",
          ]
        }
      else
        arns.output(&method(:puts))
      end
    end

    desc 'update', 'update a service'
    method_option :desired_count,   aliases: '-d', type: :numeric, default: nil, desc: 'desired number of tasks'
    method_option :task_definition, aliases: '-t', type: :string,  default: nil, desc: 'task def as family:revision'
    def update(cluster, service)
      params = {
        cluster:         cluster,
        service:         service,
        desired_count:   options[:desired_count],
        task_definition: options[:task_definition],
      }.reject { |k,v| v.nil? }

      ecs.update_service(params).service.output do |response|
        puts YAML.dump(stringify_keys(response.to_h))
      end
    end

    desc 'events', 'list events for given CLUSTER and SERVICE'
    def events(cluster, service)
      ecs.describe_services(cluster: cluster, services: [service]).services.first.events.output do |events|
        print_table events.map { |e| [e.created_at, e.id, e.message] }
      end
    end

    desc 'run_task CLUSTER TASK_DEFINITION', 'run a task on given cluster'
    method_option :command, aliases: '-c', default: nil, desc: 'override container command as name:cmd,arg1,arg2'
    def run_task(cluster, task)
      container_overrides = {}
      if options[:command]
        name, command = options[:command].split(':', 2)
        container_overrides.merge!(name: name, command: command.split(','))
      end

      params = {
        cluster: cluster,
        task_definition: task,
        overrides: container_overrides.empty? ? {} : {container_overrides: [container_overrides]}
      }

      ecs.run_task(params).output do |response|
        puts YAML.dump(stringify_keys(response.to_h))
      end
    end

    desc 'stop_task CLUSTER TASK_ID', 'stop a running task'
    def stop_task(cluster, id)
      ecs.stop_task(cluster: cluster, task: id).task.output do |response|
        puts YAML.dump(stringify_keys(response.to_h))
      end
    end
  end
end