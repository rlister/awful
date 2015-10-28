module Awful

  class SecurityGroup < Cli

    desc 'ls [NAME]', 'list security groups [matching NAME]'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      fields = options[:long] ?
        ->(s) { [tag_name(s), s.group_id, s.group_name[0..50], s.vpc_id, s.description] } :
        ->(s) { [s.group_name] }

      ec2.describe_security_groups.map(&:security_groups).flatten.select do |sg|
        sg.group_name.match(name) or sg.group_id.match(name)
      end.map do |sg|
        fields.call(sg)
      end.tap do |list|
        print_table list
      end
    end

    no_commands do

      ## return first SG that matches name to id, group_name, or Name tag
      def first_matching_sg(name)
        field = name.match(/^sg-[\d[a-f]]{8}$/) ? :group_id : :group_name
        ec2.describe_security_groups.map(&:security_groups).flatten.find do |sg|
          sg.send(field).match(name) or (tag_name(sg)||'').match(name)
        end
      end

    end

    desc 'dump NAME', 'dump security group with NAME [or ID] as yaml'
    def dump(name)
      first_matching_sg(name).tap do |sg|
        puts YAML.dump(stringify_keys(sg.to_hash))
      end
    end

    desc 'inbound NAME', 'show inbound rules for named security group'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def inbound(name)
      first_matching_sg(name).ip_permissions.tap do |perms|
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
