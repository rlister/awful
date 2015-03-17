module Awful

  class RouteTable < Thor
    include Awful

    desc 'ls [PATTERN]', 'list routes'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = nil)
      fields = options[:long] ?
        ->(r) { [ tag_name(r), r.route_table_id, r.vpc_id ] } :
        ->(r) { [ tag_name(r) || r.route_table_id ] }

      ec2.describe_route_tables.map(&:route_tables).flatten.select do |route|
        name.nil? or route.tags.any? { |tag| tag.value.match(name) }
      end.map do |route|
        fields.call(route)
      end.tap do |list|
        print_table list
      end
    end

    desc 'dump NAME', 'dump route with id or tag NAME as yaml'
    def dump(name)
      ec2.describe_route_tables.map(&:route_tables).flatten.find do |route|
        route.route_table_id == name or route.tags.any? { |tag| tag.value == name }
      end.tap do |route|
        puts YAML.dump(stringify_keys(route.to_hash))
      end
    end

  end

end
