module Awful
  class Vpc < Cli
    COLORS = {
      active: :green,
      available: :green,
      deleted: :red,
      expired: :red,
      failed: :red,
      rejected: :red,
    }

    desc 'ls [PATTERN]', 'list vpcs [with any tags matching PATTERN]'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    def ls(name = /./)
      fields = options[:long] ?
        ->(v) { [tag_name(v), v.vpc_id, v.state, v.cidr_block] } :
        ->(v) { [v.vpc_id] }
      ec2.describe_vpcs.map(&:vpcs).flatten.select do |vpc|
        vpc.tags.any? { |tag| tag.value.match(name) }
      end.map do |vpc|
        fields.call(vpc)
      end.tap do |list|
        print_table list
      end
    end

    desc 'dump NAME', 'dump VPC with id or tag NAME as yaml'
    def dump(name)
      ec2.describe_vpcs.map(&:vpcs).flatten.find do |vpc|
        vpc.vpc_id == name or vpc.tags.any? { |tag| tag.value == name }
      end.tap do |vpc|
        puts YAML.dump(stringify_keys(vpc.to_hash))
      end
    end

    desc 'delete VPC', 'delete vpc'
    def delete(vpc_id)
      if yes?("Really delete vpc #{vpc_id}?", :yellow)
        p ec2.delete_vpc(vpc_id: vpc_id)
      end
    rescue Aws::EC2::Errors::DependencyViolation => e
      error(e.message)
    rescue Aws::EC2::Errors::InvalidVpcIDNotFound => e
      error(e.message)
    end

    desc 'peers', 'list vpc peers'
    def peers
      ec2.describe_vpc_peering_connections.map(&:vpc_peering_connections).flatten.map do |p|
        [
          tag_name(p, '-'), p.vpc_peering_connection_id, color(p.status.code),
          p.requester_vpc_info.vpc_id, p.accepter_vpc_info.vpc_id,
          p.requester_vpc_info.cidr_block, p.accepter_vpc_info.cidr_block,
        ]
      end.tap do |list|
        print_table list.sort
      end
    end

  end
end
