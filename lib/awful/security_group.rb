module Awful

  class SecurityGroup < Thor
    include Awful

    desc 'ls [NAME]', 'list security groups [matching NAME]'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      fields = options[:long] ?
        ->(s) { [tag_name(s), s.group_id, s.group_name, s.vpc_id, s.description] } :
        ->(s) { [s.group_name] }

      ec2.describe_security_groups.map(&:security_groups).flatten.select do |sg|
        sg.group_name.match(name) or sg.group_id.match(name)
      end.map do |sg|
        fields.call(sg)
      end.tap do |list|
        print_table list
      end
    end

    desc 'dump NAME', 'dump security group with NAME as yaml'
    def dump(name)
      ec2.describe_security_groups.map(&:security_groups).flatten.find do |sg|
        sg.group_name == name
      end.tap do |sg|
        puts YAML.dump(stringify_keys(sg.to_hash))
      end
    end

  end

end
