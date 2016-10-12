module Awful
  module Short
    def waf_acl(*args)
      Awful::WAF::Acl.new.invoke(*args)
    end
  end

  module WAF
    class Acl < Base

      desc 'ls', 'list web_acls'
      method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
      method_option :limit,               type: :numeric, default: 50,    desc: 'limit of acls to request'
      def ls
        list_thing(:web_acls).output do |list|
          if options[:long]
            print_table list.map { |a| [a.name, a.web_acl_id] }
          else
            puts list.map(&:name)
          end
        end
      end

    end

    class Base < Cli
      desc 'acl', 'acl subcommands'
      subcommand 'acl', Acl
    end

  end
end