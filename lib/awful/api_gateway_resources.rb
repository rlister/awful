module Awful
  module Short
    def apiresources(*args)
      Awful::ApiGateway::Resources.new.invoke(*args)
    end
  end

  module ApiGateway

    class Resources < Cli
      desc 'ls REST_API_ID', 'list resources for given rest api'
      method_option :long, aliases: '-l', default: false, desc: 'Long listing'
      def ls(id)
        api_gateway.get_resources(rest_api_id: id).items.output do |items|
          if options[:long]
            print_table items.map { |i|
              methods = i.resource_methods ? i.resource_methods.keys.join(',') : ''
              [i.path, i.id, i.parent_id, methods]
            }.sort
          else
            puts items.map(&:path).sort
          end
        end
      end
    end

    class RestApi < Cli
      desc 'resources', 'resources subcommands'
      subcommand 'resources', Resources
    end

  end
end