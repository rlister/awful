module Awful
  module Short
    def apimethods(*args)
      Awful::ApiGateway::Methods.new.invoke(*args)
    end
  end

  module ApiGateway

    class Methods < Cli
      desc 'dump REST_API_ID', 'list methods for given rest api and resource'
      method_option :method, aliases: '-m', default: 'GET', desc: 'HTTP method to get'
      def dump(id, resource)
        api_gateway.get_method(rest_api_id: id, resource_id: resource, http_method: options[:method]).output do |response|
          puts YAML.dump(stringify_keys(response.to_hash))
        end
      end

    end

    class RestApi < Cli
      desc 'methods', 'methods subcommands'
      subcommand 'methods', Methods
    end

  end
end