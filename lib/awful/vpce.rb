module Awful

  class Vpce < Cli
    COLORS = {
      available: :green,
      pending:   :yellow,
      deleting:  :red,
      deleted:   :green,
    }

    no_commands do
      def color(string)
        set_color(string, COLORS.fetch(string.to_sym, :yellow))
      end
    end

    desc 'ls [IDs]', 'list VPC endpoints'
    method_option :long,    aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    method_option :vpc,     aliases: '-v', type: :array,   default: [],    desc: 'VPC IDs to filter'
    method_option :service, aliases: '-s', type: :array,   default: [],    desc: 'services to filter'
    method_option :state,                  type: :array,   default: [],    desc: 'state: pending | available | deleting | deleted'
    def ls(*ids)
      filters = [
        { name: 'vpc-endpoint-id',    values: ids },
        { name: 'vpc-id',             values: options[:vpc] },
        { name: 'service-name',       values: options[:service].map { |s| "com.amazonaws.#{ENV['AWS_REGION']}.#{s.downcase}" } },
        { name: 'vpc-endpoint-state', values: options[:state] },
      ].reject { |f| f[:values].empty? }
      filters = nil if filters.empty?

      ec2.describe_vpc_endpoints(filters: filters).vpc_endpoints.output do |endpoints|
        if options[:long]
          print_table endpoints.map { |e|
            [e.vpc_endpoint_id, e.vpc_id, e.service_name, color(e.state), e.creation_timestamp]
          }
        else
          puts endpoints.map(&:vpc_endpoint_id)
        end
      end
    end

    desc 'dump IDs', 'dump VPC endpoints with ids'
    def dump(*ids)
      ec2.describe_vpc_endpoints(
        filters: [{name: 'vpc-endpoint-id', values: ids}]
      ).vpc_endpoints.output do |endpoints|
        puts YAML.dump(endpoints.map{ |e| stringify_keys(e.to_hash) })
      end
    end

  end
end