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

    end

    class Base < Cli
      desc 'ipset', 'ipset subcommands'
      subcommand 'ipset', Ipset
    end

  end
end