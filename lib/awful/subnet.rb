module Awful

  class Subnet < Thor
    include Awful

    desc 'ls [PATTERN]', 'list subnets [with any tags matching PATTERN]'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      fields = options[:long] ?
        ->(s) { [s.tags.map{ |t| t.value }.join(','), s.subnet_id, s.state, s.cidr_block, s.available_ip_address_count, s.availability_zone] } :
        ->(s) { [s.subnet_id] }
      ec2.describe_subnets.map(&:subnets).flatten.select do |subnet|
        subnet.tags.any? { |tag| tag.value.match(name) }
      end.map do |subnet|
        fields.call(subnet)
      end.tap do |list|
        print_table list.sort
      end
    end

    desc 'dump NAME', 'dump subnet with id or tag NAME as yaml'
    def dump(name)
      ec2.describe_subnets.map(&:subnets).flatten.find do |subnet|
        subnet.subnet_id == name or subnet.tags.any? { |tag| tag.value == name }
      end.tap do |subnet|
        puts YAML.dump(stringify_keys(subnet.to_hash))
      end
    end

  end

end
