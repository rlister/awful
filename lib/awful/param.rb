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
            [p.name, p.type, p.description, p.key_id, p.last_modified_date, p.last_modified_user.split('/').last]
          }
        else
          puts params.map(&:name)
        end
      end
    end

    desc 'get NAMES', 'get parameter values'
    method_option :long,   aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    method_option :decrypt, aliases: '-d', type: :boolean, default: false, desc: 'decrypt values for SecureString types'
    def get(*names)
      names.each_slice(10).map do |batch| # API allows only 10 at a time
        ssm.get_parameters(names: batch, with_decryption: options[:decrypt]).parameters
      end.flatten.output do |params|
        if options[:long]
          print_table params.map { |p|
            [p.name, p.value]
          }
        else
          puts params.map(&:value)
        end
      end
    end

    desc 'history NAME', 'get parameter history'
    method_option :long,   aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def history(name)
      paginate(:parameters) do |token|
        ssm.get_parameter_history(
          name: name,
          with_decryption: options[:decrypt],
          next_token: token,
        )
      end.output do |params|
        if options[:long]
          print_table params.map { |p|
            [p.name, p.value, p.last_modified_date, p.last_modified_user]
          }
        else
          puts params.map(&:value)
        end
      end
    end

    desc 'put NAME VALUE', 'put parameter into the store'
    method_option :description, aliases: '-d', type: :string,  default: nil,      desc: 'description for params'
    method_option :type,        aliases: '-t', type: :string,  default: 'String', desc: 'String, StringList, SecureString'
    method_option :key_id,      aliases: '-k', type: :string,  default: nil,      desc: 'KMS key for SecureString params'
    method_option :overwrite,   aliases: '-o', type: :boolean, default: false,    desc: 'overwrite existing params'
    def put(name, value)
      ssm.put_parameter(
        name:        name,
        value:       value,
        description: options[:description],
        type:        options[:type],
        key_id:      options[:key_id],
        overwrite:   options[:overwrite],
      )
    end

    desc 'delete NAME', 'delete parameter from the store'
    method_option :yes, aliases: '-y', type: :boolean, default: false, desc: 'delete without query'
    def delete(name)
      if options[:yes] || yes?("Really delete parameter #{name}?", :yellow)
        ssm.delete_parameter(name: name)
      end
    end

  end
end