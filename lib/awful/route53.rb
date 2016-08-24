module Awful
  module Short
    def r53(*args)
      Awful::Route53.new.invoke(*args)
    end
  end

  class Route53 < Cli
    no_commands do
      def route53
        @route53 ||= Aws::Route53::Client.new
      end

      ## extract domain part of dns name
      def get_domain(name)
        name.split('.').last(2).join('.')
      end

      ## get hosted zone id from domain name
      def get_zone_by_name(name)
        if name.match(/^Z[A-Z0-9]{13}$/) # id is 14 char upcase string starting with Z
          name
        else
          matches = route53.list_hosted_zones.hosted_zones.select do |zone|
            zone.name.match(name)
          end
          case matches.size
          when 0
            say "no hosted zones matching #{name}", :red
            exit
          when 1
            matches.first.id
          else
            say "ambiguous hosted zone, matches: #{matches.map(&:name).join(', ')}", :yellow
            exit
          end
        end
      end

      ## return dns name and hosted zone id
      def get_elb_dns(name)
        desc = elb.describe_load_balancers(load_balancer_names: [name]).load_balancer_descriptions[0]
        ['dualstack.' + desc.dns_name, desc.canonical_hosted_zone_name_id]
      end
    end

    desc 'ls [NAME]', 'list hosted zones'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      route53.list_hosted_zones.hosted_zones.select do |zone|
        zone.name.match(name)
      end.tap do |list|
        if options[:long]
          print_table list.map { |z| [z.name, z.id, z.resource_record_set_count, z.config.comment] }
        else
          puts list.map(&:name)
        end
      end
    end

    desc 'records ZONE', 'list records for given ZONE'
    method_option :long,      aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    method_option :type,      aliases: '-t', type: :array,   default: nil,   desc: 'List of record types to match'
    method_option :name,      aliases: '-n', type: :array,   default: nil,   desc: 'List of names to match'
    method_option :max_items, aliases: '-m', type: :numeric, default: nil,   desc: 'Max number of records to check'
    def records(zone)
      ## match on given record types
      include_type = options[:type] ? ->(type) { options[:type].include?(type) } : ->(_) { true }

      ## match on given record names
      names = options.fetch('name', []).map { |name| name.gsub(/([^\.])$/, '\1.') } # append . to names if missing
      include_name = options[:name] ? ->(name) { names.include?(name) } : ->(_) { true }

      route53.list_resource_record_sets(
        hosted_zone_id: get_zone_by_name(zone),
        max_items:      options[:max_items]
      ).resource_record_sets.select do |rrset|
        include_type.call(rrset.type) and include_name.call(rrset.name)
      end.tap do |records|
        if options[:long]
          print_table records.map { |r|
            dns_name = r.alias_target.nil? ? [] : ['ALIAS ' + r.alias_target.dns_name]
            values = r.resource_records.map(&:value)
            [r.name, r.type, (dns_name + values).join(', ')]
          }
        else
          puts records.map(&:name)
        end
      end
    end

    desc 'dump NAME', 'get a record set details'
    method_option :max_items, aliases: '-m', type: :numeric, default: 1,   desc: 'Max items to show, starting with given name+type'
    method_option :type,      aliases: '-t', type: :string,  default: nil, desc: 'DNS type to begin the listing of records'
    def dump(name)
      zone = name.split('.').last(2).join('.')
      params = {
        hosted_zone_id:    get_zone_by_name(zone),
        start_record_name: name,
        start_record_type: options[:type],
        max_items:         options[:max_items]
      }
      route53.list_resource_record_sets(params).resource_record_sets.tap do |records|
        records.each do |record|
          puts YAML.dump(stringify_keys(record.to_hash))
        end
      end
    end

    # desc 'update NAME', 'change a record set'
    # # method_option :type,  aliases: '-t', type: :string,  default: 'A', desc: 'Type of record: SOA, A, TXT, NS, CNAME, MX, PTR, SRV, SPF, AAAA'
    # # method_option :alias, aliases: '-a', type: :boolean, default: false, desc: 'Create an ALIAS record'
    # def update(name, target)
    # end

    ## create/update alias to ELB record; later add S3, CF, Beanstalk, rrsets
    desc 'alias NAME', 'upsert an alias to an AWS resource given by name'
    method_option :resource,       aliases: '-r', type: :string,  default: 'elb', desc: 'Type of target resource, for now just `elb`'
    method_option :type,           aliases: '-t', type: :string,  default: 'A',   desc: 'Type of record: A, SOA, TXT, NS, CNAME, MX, PTR, SRV, SPF, AAAA'
    method_option :weight,         aliases: '-w', type: :numeric, default: nil,   desc: 'weight of record (requires set_identifier)'
    method_option :set_identifier, aliases: '-s', type: :string,  default: nil,   desc: 'weighted record set unique identifier'
    def alias(name, target)
      dns_name, hosted_zone_id = send("get_#{options[:resource]}_dns", target)
      params = {
        hosted_zone_id: get_zone_by_name(get_domain(name)),
        change_batch: {
          changes: [
            {
              action: 'UPSERT',
              resource_record_set: {
                name:           name,
                type:           options[:type],
                set_identifier: options[:set_identifier],
                weight:         options[:weight],
                alias_target: {
                  hosted_zone_id:         hosted_zone_id,
                  dns_name:               dns_name,
                  evaluate_target_health: false
                }
              }
            }
          ]
        }
      }
      route53.change_resource_record_sets(params).tap do |response|
        puts YAML.dump(stringify_keys(response.change_info.to_hash))
      end
    end

    desc 'cname NAME TARGET', 'upsert a CNAME record'
    method_option :ttl, aliases: '-t', type: :numeric, default: 300, desc: 'TTL for record'
    def cname(name, target)
      params = {
        hosted_zone_id: get_zone_by_name(get_domain(name)),
        change_batch: {
          changes: [
            {
              action: 'UPSERT',
              resource_record_set: {
                name: name,
                type: 'CNAME',
                resource_records: [
                  {
                    value: target
                  }
                ],
                ttl: options[:ttl]
              }
            }
          ]
        }
      }
      route53.change_resource_record_sets(params).tap do |response|
        puts YAML.dump(stringify_keys(response.change_info.to_hash))
      end
    end

    desc 'change ID', 'get change batch request'
    def change(id)
      route53.get_change(id: id).change_info.tap do |info|
        puts YAML.dump(stringify_keys(info.to_hash))
      end
    end
  end
end