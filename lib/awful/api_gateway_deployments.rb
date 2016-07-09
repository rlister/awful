module Awful
  module Short
    def deployments(*args)
      Awful::ApiGateway::Deployments.new.invoke(*args)
    end
  end

  module ApiGateway

    class Deployments < Cli
      desc 'ls REST_API_ID', 'list deployments for given rest api'
      method_option :long, aliases: '-l', default: false, desc: 'Long listing'
      def ls(id)
        api_gateway.get_deployments(rest_api_id: id).items.output do |items|
          if options[:long]
            print_table items.sort_by(&:created_date).map { |i|
              [i.id, i.created_date, i.description]
            }
          else
            puts items.map(&:id)
          end
        end
      end

      desc 'create REST_API_ID STAGE', 'create deployment for rest api and stage'
      method_option :description, aliases: '-d', type: :string, default: nil, desc: 'description of deployment'
      def create(id, stage)
        api_gateway.create_deployment(
          rest_api_id: id,
          stage_name: stage,
          description: options[:description]
        ).output do |response|
          puts response.id
        end
      end
    end

    class RestApi < Cli
      desc 'deployments', 'deployments subcommands'
      subcommand 'deployments', Deployments
    end
  end

end