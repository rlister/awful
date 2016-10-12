module Awful
  module Short
    def waf_ipset(*args)
      Awful::WAF::Ipset.new.invoke(*args)
    end
  end

  module WAF
    class Ipset < Base

      desc 'ls', 'list ipsets'
      method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
      def ls
        list_thing(:ip_sets).output do |ipsets|
          if options[:long]
            print_table ipsets.map { |i| [i.name, i.ip_set_id] }
          else
            puts ipsets.map(&:name)
          end
        end
      end

      desc 'get ID', 'get ipset'
      method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
      def get(id)
        waf.get_ip_set(ip_set_id: id).ip_set.ip_set_descriptors.output do |ipsets|
          if options[:long]
            print_table ipsets.map { |i| [i.value, i.type] }
          else
            puts ipsets.map(&:value)
          end
        end
      end

      desc 'update ID', 'update ipset with ips'
      method_option :type, type: :string, default: 'ipv4', desc: 'type of address, IPV4 or IPV6'
      method_option :delete, type: :boolean, default: false, desc: 'delete IPs'
      def update(id, *values)
        waf.update_ip_set(
          ip_set_id: id,
          change_token: change_token,
          updates: values.map do |value|
            {
              action: options[:delete] ? 'DELETE' : 'INSERT',
              ip_set_descriptor: {
                type: options[:type].upcase,
                value: value
              }
            }
          end
        )
      end

    end

    class Base < Cli
      desc 'ipset', 'ipset subcommands'
      subcommand 'ipset', Ipset
    end

  end
end