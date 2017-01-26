module Awful
  module Short
    def apistages(*args)
      Awful::ApiGateway::Stages.new.invoke(*args)
    end
  end

  module ApiGateway

    class Stages < Cli
      desc 'ls REST_API_ID', 'list stages for given rest api'
      method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
      def ls(id, deployment = nil)
        api_gateway.get_stages(rest_api_id: id, deployment_id: deployment).item.output do |items|
          if options[:long]
            print_table items.map { |i|
              [i.stage_name, i.deployment_id, i.last_updated_date, i.description]
            }.sort
          else
            puts items.map(&:stage_name).sort
          end
        end
      end
    end

    class RestApi < Cli
      desc 'stages', 'stages subcommands'
      subcommand 'stages', Stages
    end

  end
end