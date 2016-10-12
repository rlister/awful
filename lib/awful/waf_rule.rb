module Awful
  module Short
    def waf_rule(*args)
      Awful::WAF::Rule.new.invoke(*args)
    end
  end

  module WAF
    class Rule < Base

      desc 'ls', 'list rules'
      method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
      def ls
        list_thing(:rules).output do |rules|
          if options[:long]
            print_table rules.map { |r| [r.name, r.rule_id] }
          else
            puts rules.map(&:name)
          end
        end
      end

    end

    class Base < Cli
      desc 'rule', 'rule subcommands'
      subcommand 'rule', Rule
    end

  end
end