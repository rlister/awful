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

  end

end
