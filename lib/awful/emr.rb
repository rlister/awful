module Awful
  module Short
    def emr(*args)
      Awful::EMR.new.invoke(*args)
    end
  end

  class EMR < Cli
    COLORS = {
      RUNNING: :green,
      TERMINATING: :red,
      TERMINATED: :red,
      TERMINATED_WITH_ERRORS: :red,
    }

    no_commands do
      def emr
        @emr ||= Aws::EMR::Client.new
      end
    end

    desc 'ls', 'list clusters'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    method_option :states, aliases: '-s', type: :array, default: [], desc: 'limit to clusters with given states'
    def ls
      emr.list_clusters(cluster_states: options[:states].map(&:upcase)).clusters.output do |clusters|
        if options[:long]
          print_table clusters.map { |c|
            [c.name, c.id, color(c.status.state), c.status.timeline.creation_date_time, "#{c.normalized_instance_hours}h"]
          }
        else
          puts clusters.map(&:name)
        end
      end
    end

    desc 'dump ID', 'describe cluster with ID'
    def dump(id)
      emr.describe_cluster(cluster_id: id).cluster.output do |cluster|
        puts YAML.dump(stringify_keys(cluster.to_hash))
      end
    end

    desc 'instances', 'list instances for cluster'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    method_option :group, aliases: '-g', type: :array, default: [], desc: 'instance group types: MASTER, CORE, TASK'
    def instances(id)
      emr.list_instances(cluster_id: id, instance_group_types: options[:group].map(&:upcase)).instances.output do |instances|
        if options[:long]
          print_table instances.map { |i|
            [i.ec2_instance_id, i.instance_group_id, color(i.status.state), i.instance_type, i.public_ip_address, i.private_ip_address, i.status.timeline.creation_date_time]
          }
        else
          puts instances.map(&:ec2_instance_id)
        end
      end
    end

  end
end
