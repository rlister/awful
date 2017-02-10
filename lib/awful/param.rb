module Awful
  module Short
    def param(*args)
      Awful::Param.new.invoke(*args)
    end
  end

  class Param < Cli
    no_commands do
      def ssm
        @ssm ||= Aws::SSM::Client.new
      end
    end

    desc 'ls', 'list parameters'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def ls
      paginate(:parameters) do |token|
        ssm.describe_parameters(next_token: token)
      end.output do |params|
        if options[:long]
          print_table params.map { |p|
            [p.name, p.type, p.description, p.key_id, p.last_modified_date, p.last_modified_user]
          }
        else
          puts params.map(&:name)
        end
      end
    end

  end
end