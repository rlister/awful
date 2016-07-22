module Awful
  module Short
    def sg(*args)
      Awful::SecurityGroup.new.invoke(*args)
    end
  end

  class SecurityGroup < Cli

    desc 'ls [IDs]', 'list security groups'
    method_option :long,     aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    method_option :ingress,  aliases: '-i', type: :boolean, default: false, desc: 'list ingress permissions'
    method_option :egress,   aliases: '-o', type: :boolean, default: false, desc: 'list egress permissions'
    method_option :tags,     aliases: '-t', type: :array,   default: [],    desc: 'List of tags to filter, as key=value'
    method_option :stack,    aliases: '-s', type: :string,  default: nil,   desc: 'Filter by given stack'
    method_option :resource, aliases: '-r', type: :string,  default: nil,   desc: 'Filter by given stack resource logical id'
    def ls(*ids)
      ## filter by tags
      filters = []
      options[:tags].each do |tag|
        key, value = tag.split('=')
        filters << {name: "tag:#{key}", values: [value]}
      end
      filters << {name: 'tag:aws:cloudformation:stack-name', values: [options[:stack]]}    if options[:stack]
      filters << {name: 'tag:aws:cloudformation:logical-id', values: [options[:resource]]} if options[:resource]
      filters = nil if filters.empty? # sdk does not like empty arrays as args

      ec2.describe_security_groups(group_ids: ids, filters: filters).security_groups.output do |groups|
        if options[:long]
          print_table groups.map { |g|
            [ g.group_name, g.group_id, g.vpc_id, g.description ]
          }.sort
        elsif options[:ingress]
          print_table groups.map { |g|
            [ g.group_name, g.group_id, g.ip_permissions.map { |p| "#{p.ip_protocol}:#{p.from_port}-#{p.to_port}" }.join(',') ]
          }.sort
        elsif options[:egress]
          print_table groups.map { |g|
            [ g.group_name, g.group_id, g.ip_permissions_egress.map { |p| "#{p.ip_protocol}:#{p.from_port}-#{p.to_port}" }.join(',') ]
          }.sort
        else
          puts groups.map(&:group_name).sort
        end
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
      first_matching_sg(name).output do |sg|
        puts YAML.dump(stringify_keys(sg.to_hash))
      end
    end

    desc 'inbound NAME', 'show inbound rules for named security group'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def inbound(name)
      first_matching_sg(name).ip_permissions.output do |perms|
        sources = ->(perm) { perm.ip_ranges.map(&:cidr_ip) + perm.user_id_group_pairs.map(&:group_id) }
        if options[:long]
          perms.map do |p|
            sources.call(p).map do |s|
              [p.ip_protocol, p.from_port, p.to_port, s]
            end
          end.flatten(1).output { |list| print_table list }
        else
          puts perms.map { |p| sources.call(p) }.flatten
        end
      end
    end

    desc 'revoke ID [IP_PERMISSIONS]', 'revoke rules from security group'
    method_option :source_security_group_name,     type: :string, default: nil, desc: 'ip permission'
    method_option :source_security_group_owner_id, type: :string, default: nil, desc: 'ip permission'
    method_option :ip_protocol,                    type: :string, default: nil, desc: 'ip permission'
    method_option :from_port,                      type: :string, default: nil, desc: 'ip permission'
    method_option :to_port,                        type: :string, default: nil, desc: 'ip permission'
    method_option :cidr_ip,                        type: :string, default: nil, desc: 'ip permission'
    def revoke(id, *ip_permissions)
      ## invoked from code, process ip_permissions objects as args
      perms = ip_permissions.map do |p|
        p.to_hash.tap do |h|
          h.each do |k,v|
            h[k] = nil if (v.respond_to?(:empty?) && v.empty?) # no empty arrays, e.g. user_group_id_pairs, prefix_list_ids
          end
        end
      end

      perms = nil if perms.empty?

      ## can set these on command-line
      params = %i[source_security_group_name source_security_group_owner_id ip_protocol from_port to_port cidr_ip].each_with_object({}) do |k,h|
        h[k] = options[k]
      end

      ec2.revoke_security_group_ingress(params.merge(group_id: id, ip_permissions: perms))
    end

  end
end