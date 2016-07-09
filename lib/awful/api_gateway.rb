module Awful
  module Short
    def apigw(*args)
      Awful::ApiGateway.new.invoke(*args)
    end
  end

  class Cli < Thor
    no_commands do
      def api_gateway
        @api_gateway ||= Aws::APIGateway::Client.new
      end
    end
  end

  module ApiGateway
    class RestApi < Cli
      desc 'ls', 'list rest apis'
      method_option :long, aliases: '-l', default: false, desc: 'Long listing'
      def ls
        api_gateway.get_rest_apis.items.output do |items|
          if options[:long]
            print_table items.map { |i|
              [i.name, i.id, i.created_date, i.description]
            }.sort
          else
            puts items.map(&:name).sort
          end
        end
      end

      desc 'delete ID', 'delete rest api with ID'
      def delete(id)
        name = api_gateway.get_rest_api(rest_api_id: id).name
        if yes?("Really delete rest api #{id}: #{name}?", :yellow)
          api_gateway.delete_rest_api(rest_api_id: id)
        end
      end
    end
  end
end