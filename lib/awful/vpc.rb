module Awful

  class Vpc < Cli

    desc 'ls [PATTERN]', 'list vpcs [with any tags matching PATTERN]'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      fields = options[:long] ?
        ->(v) { [v.tags.map{ |t| t.value }.join(','), v.vpc_id, v.state, v.cidr_block] } :
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

  end

end
