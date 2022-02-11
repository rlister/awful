require 'yaml'

module Awful
  module Short
    def elasticache(*args)
      Awful::ElastiCache.new.invoke(*args)
    end
  end

  class ElastiCache < Cli
    COLORS = {
      available: :green,
      deleted:   :red
    }

    no_commands do
      def elasticache
        @elasticache ||= Aws::ElastiCache::Client.new
      end
    end

    desc 'ls [ID]', 'list clusters'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    def ls(id = nil)
      elasticache.describe_cache_clusters(cache_cluster_id: id).cache_clusters.tap do |clusters|
        if options[:long]
          print_table clusters.map { |c|
            [
              c.cache_cluster_id,
              c.engine,
              c.engine_version,
              c.num_cache_nodes,
              c.cache_node_type,
              c.preferred_availability_zone,
              color(c.cache_cluster_status),
              c.cache_cluster_create_time
            ]
          }
        else
          puts clusters.map(&:cache_cluster_id)
        end
      end
    end

    desc 'dump [ID]', 'get all details for given cluster'
    method_option :nodes, aliases: '-n', type: :boolean, default: false, desc: 'show node info'
    def dump(id = nil)
      elasticache.describe_cache_clusters(
        cache_cluster_id:     id,
        show_cache_node_info: options[:nodes]
      ).cache_clusters.tap do |clusters|
        clusters.each do |cluster|
          puts YAML.dump(stringify_keys(cluster.to_hash))
        end
      end
    end

    ## as documented in this abomination:
    ## https://s3.amazonaws.com/cloudformation-templates-us-east-1/ElastiCache_Redis.template
    desc 'endpoint ID', 'get endpoint for given cluster'
    def endpoint(id)
      elasticache.describe_cache_clusters(
        cache_cluster_id:     id,
        show_cache_node_info: true
      ).cache_clusters.first.cache_nodes.first.endpoint.tap do |ep|
        puts ep.address + ':' + ep.port.to_s
      end
    end
  end
end
