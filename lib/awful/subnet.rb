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

    desc 'create NAME', 'create subnet'
    def create(name)
      opt = load_cfg
      whitelist = %i[vpc_id cidr_block availability_zone]
      opt = remove_empty_strings(opt)
      ec2.create_subnet(only_keys_matching(opt, whitelist)).tap do |response|
        id = response.map(&:subnet).map(&:subnet_id)
        ec2.create_tags(resources: Array(id), tags: opt[:tags]) if opt[:tags]
        puts id
      end
    end

    desc 'delete NAME', 'delete subnet with name or ID'
    def delete(name)
      id = find_subnet(name)
      if id and yes?("really delete subnet #{name} (#{id})?")
        ec2.delete_subnet(subnet_id: id)
      end
    end

  end

end
