module Awful

  class SecurityGroup < Cli

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

    desc 'inbound NAME', 'show inbound rules for named security group'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def inbound(name)
      ec2.describe_security_groups.map(&:security_groups).flatten.find do |sg|
        sg.group_name == name
      end.ip_permissions.tap do |perms|
        sources = ->(perm) { perm.ip_ranges.map(&:cidr_ip) + perm.user_id_group_pairs.map(&:group_id) }
        if options[:long]
          perms.map do |p|
            sources.call(p).map do |s|
              [p.ip_protocol, p.from_port, p.to_port, s]
            end
          end.flatten(1).tap { |list| print_table list }
        else
          puts perms.map { |p| sources.call(p) }.flatten
        end
      end
    end

  end

end
