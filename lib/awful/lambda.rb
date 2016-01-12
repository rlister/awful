require 'open-uri'
require 'tempfile'

module Awful
  class Lambda < Cli

    no_commands do
      ## return zip file contents, make it if necessary
      def zip_thing(thing)
        if File.directory?(thing)
          Dir.chdir(thing) do
            %x[zip -q -r - .]      # zip dir contents
          end
        elsif thing.match(/\.zip$/i)
          File.read(thing)         # raw zipfile contents
        elsif File.file?(thing)
          %x[zip -q -j - #{thing}] # zip a single file
        else
          nil
        end
      end
    end

    desc 'ls NAME', 'list lambda functions matching NAME pattern'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    method_option :arns, aliases: '-a', default: false, desc: 'List ARNs for functions'
    def ls(name = /./)
      lambda.list_functions.functions.select do |function|
        function.function_name.match(name)
      end.tap do |functions|
        if options[:long]
          print_table functions.map { |f| [f.function_name, f.description, f.last_modified] }.sort
        elsif options[:arns]
          puts functions.map(&:function_arn).sort
        else
          puts functions.map(&:function_name).sort
        end
      end
    end

    desc 'create', 'create a new lambda function'
    def create(name = nil)
      opt = load_cfg
      opt[:function_name] = name unless name.nil?
      opt[:code][:zip_file] = zip_thing(opt[:code][:zip_file])
      whitelist = %i[function_name runtime role handler description timeout memory_size code]
      lambda.create_function(only_keys_matching(opt, whitelist)).tap do |response|
        puts YAML.dump(stringify_keys(response.to_hash))
      end
    end

    desc 'update [NAME]', 'update lambda function config [and code]'
    method_option :zip_file, aliases: '-z', default: false, desc: 'Update code zip file (creates if necessary)'
    def update(name = nil)
      opt = load_cfg
      opt[:function_name] = name unless name.nil?

      ## update configuration
      whitelist = %i[function_name role handler description timeout memory_size]
      response = lambda.update_function_configuration(only_keys_matching(opt, whitelist)).to_hash

      ## update code
      opt[:code] = {zip_file: options[:zip_file]} if options[:zip_file]
      unless opt.fetch(:code, {}).empty?
        code = opt[:code].merge({function_name: opt[:function_name]})
        code[:zip_file] = zip_thing(code[:zip_file]) if code[:zip_file]
        r = lambda.update_function_code(code)
        response = response.merge(r.to_hash)
      end

      ## return combined response
      response.tap do |resp|
        puts YAML.dump(stringify_keys(resp))
      end
    end

    desc 'dump NAME', 'get configuration of lambda function NAME'
    def dump(name)
      lambda.get_function_configuration(function_name: name).tap do |h|
        puts YAML.dump(stringify_keys(h.to_hash))
      end
    end

    desc 'code NAME', 'get code for lambda function NAME'
    method_option :url, aliases: '-u', default: false, desc: 'Return just URL instead of downloading code'
    def code(name)
      url = lambda.get_function(function_name: name).code.location
      if options[:url]
        url
      else
        zipdata = open(url).read
        file = Tempfile.open(['awful', '.zip'])
        file.write(zipdata)
        file.close
        %x[unzip -p #{file.path}] # unzip all contents to stdout
      end.tap do |output|
        puts output
      end
    end

    desc 'delete NAME', 'delete lambda function NAME'
    def delete(name)
      if yes? "Really delete lambda function #{name}?", :yellow
        lambda.delete_function(function_name: name).tap do
          puts "deleted #{name}"
        end
      end
    end

    ## see lambda_events.rb for subcommands
    desc 'subcommand', 'described here'
    subcommand 'events', LambdaEvents
  end
end