module Awful

  class CloudFormation < Cli

    no_commands do
      def cf
        @cf ||= Aws::CloudFormation::Client.new
      end
    end

    desc 'ls [PATTERN]', 'list cloudformation stacks matching PATTERN'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    method_option :all,  aliases: '-a', default: false, desc: 'Show all, including stacks in DELETE_COMPLETE'
    def ls(name = /./)
      stacks = cf.list_stacks.stack_summaries.select do |stack|
        stack.stack_name.match(name)
      end

      ## skip deleted stacks unless -a given
      unless options[:all]
        stacks = stacks.select { |stack| stack.stack_status != 'DELETE_COMPLETE' }
      end

      stacks.tap do |stacks|
        if options[:long]
          print_table stacks.map { |s| [s.stack_name, s.creation_time, s.stack_status, s.template_description] }
        else
          puts stacks.map(&:stack_name)
        end
      end
    end

    desc 'dump NAME', 'describe stack named NAME'
    def dump(name)
      cf.describe_stacks(stack_name: name).stacks.tap do |stacks|
        stacks.each do |stack|
          puts YAML.dump(stringify_keys(stack.to_hash))
        end
      end
    end

    desc 'template NAME', 'get template for stack named NAME'
    def template(name)
      cf.get_template(stack_name: name).template_body.tap do |template|
        puts template
      end
    end

    desc 'validate FILE', 'validate given template in FILE or stdin'
    def validate(file = nil)
      begin
        cf.validate_template(template_body: file_or_stdin(file)).tap do |response|
          puts YAML.dump(stringify_keys(response.to_hash))
        end
      rescue Aws::CloudFormation::Errors::ValidationError => e
        e.tap { |err| puts err.message }
      end
    end

    desc 'create NAME', 'create stack with name NAME'
    def create(name, file = nil)
      cf.create_stack(stack_name: name, template_body: file_or_stdin(file)).tap do |response|
        puts response.stack_id
      end
    end

    desc 'update NAME', 'update stack with name NAME'
    def update(name, file = nil)
      begin
        cf.update_stack(stack_name: name, template_body: file_or_stdin(file)).tap do |response|
          puts response.stack_id
        end
      rescue Aws::CloudFormation::Errors::ValidationError => e
        e.tap { |err| puts err.message }
      end
    end

    desc 'delete NAME', 'deletes stack with name NAME'
    def delete(name)
      if yes? "Really delete stack #{name}?", :yellow
        cf.delete_stack(stack_name: name)
      end
    end

    desc 'events NAME', 'show events for stack with name NAME'
    def events(name)
      cf.describe_stack_events(stack_name: name).stack_events.tap do |events|
        print_table events.map { |e| [e.timestamp, e.resource_status, e.resource_type, e.logical_resource_id, e.resource_status_reason] }
      end
    end

    desc 'resources NAME', 'list resources for stack with name NAME'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def resources(name)
      cf.list_stack_resources(stack_name: name).stack_resource_summaries.tap do |resources|
        if options[:long]
          print_table resources.map { |r| [r.logical_resource_id, r.physical_resource_id, r.resource_type, r.resource_status, r.resource_status_reason] }
        else
          puts resources.map(&:logical_resource_id)
        end
      end
    end

    desc 'id NAME RESOURCE', 'get physical_resource_id from a logical_resource_id RESOURCE for stack with NAME'
    method_option :all, aliases: '-a', default: false, desc: 'Return all details about resource as YAML'
    def id(name, resource)
      detail = cf.describe_stack_resource(stack_name: name, logical_resource_id: resource).stack_resource_detail
      if options[:all]
        detail.tap do |d|
          puts YAML.dump(stringify_keys(d.to_hash))
        end
      else
        detail.physical_resource_id.tap do |id|
          puts id
        end
      end
    end

    desc 'limits', 'describe cloudformation account limits'
    def limits
      cf.describe_account_limits.account_limits.tap do |limits|
        print_table limits.map { |l| [l.name, l.value] }
      end
    end
  end
end
