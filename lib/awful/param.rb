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

    desc 'ls [NAMES]', 'list parameters'
    method_option :long,   aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    method_option :type,   aliases: '-t', type: :array,   default: nil,   desc: 'filter types: String, StringList, SecureString'
    method_option :key_id, aliases: '-k', type: :array,   default: nil,   desc: 'filter key IDs'
    def ls(*names)
      filters = []
      filters += [{key: 'Name',  values: names}]            unless names.empty?
      filters += [{key: 'Type',  values: options[:type]}]   if options[:type]
      filters += [{key: 'KeyId', values: options[:key_id]}] if options[:key_id]
      paginate(:parameters) do |token|
        ssm.describe_parameters(filters: filters, next_token: token)
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