module Awful
  module Short
    def cf(*args)
      Awful::CloudFormation.new.invoke(*args)
    end
  end

  class CloudFormation < Cli

    COLORS = {
      create_in_progress:                  :yellow,
      delete_in_progress:                  :yellow,
      update_in_progress:                  :yellow,
      update_complete_cleanup_in_progress: :yellow,
      create_failed:                       :red,
      delete_failed:                       :red,
      update_failed:                       :red,
      create_complete:                     :green,
      delete_complete:                     :green,
      update_complete:                     :green,
      delete_skipped:                      :yellow,
      rollback_in_progress:                :red,
      rollback_complete:                   :red,
    }

    no_commands do
      def cf
        @cf ||= Aws::CloudFormation::Client.new
      end

      def color(string)
        set_color(string, COLORS.fetch(string.downcase.to_sym, :blue))
      end

      ## get list of stacks
      def stack_summaries(next_token = nil)
        response = cf.list_stacks(next_token: next_token)
        summaries = response.stack_summaries
        if response.next_token # recurse to get more data
          summaries += stack_summaries(response.next_token)
        else
          summaries
        end
      end
    end

    desc 'ls [PATTERN]', 'list cloudformation stacks matching PATTERN'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    method_option :all,  aliases: '-a', type: :boolean, default: false, desc: 'Show all, including stacks in DELETE_COMPLETE'
    def ls(name = /./)
      stacks = stack_summaries

      ## skip deleted stacks unless -a given
      unless options[:all]
        stacks = stacks.select { |stack| stack.stack_status != 'DELETE_COMPLETE' }
      end

      ## match on given arg
      stacks.select do |stack|
        stack.stack_name.match(name)
      end.output do |list|
        if options[:long]
          print_table list.map { |s|
            [
              s.stack_name,
              s.creation_time,
              color(s.stack_status),
              s.template_description,
            ]
          }.sort
        else
          puts list.map(&:stack_name).sort
        end
      end
    end

    desc 'exists NAME', 'check if stack exists'
    def exists(name)
      begin
        cf.describe_stacks(stack_name: name)
        true
      rescue Aws::CloudFormation::Errors::ValidationError
        false
      end.output(&method(:puts))
    end

    desc 'dump NAME', 'describe stack named NAME'
    def dump(name)
      cf.describe_stacks(stack_name: name).stacks.output do |stacks|
        stacks.each do |stack|
          puts YAML.dump(stringify_keys(stack.to_hash))
        end
      end
    end

    desc 'parameters NAME', 'return stack parameters as a hash'
    def parameters(name)
      cf.describe_stacks(stack_name: name).stacks.first.parameters.each_with_object({}) do |p, h|
        h[p.parameter_key] = p.parameter_value
      end.output do |hash|
        print_table hash.sort
      end
    end

    desc 'outputs NAME [KEY]', 'get stack outputs as a ruby hash, or individual value'
    def outputs(name, key = nil)
      output_hash = cf.describe_stacks(stack_name: name).stacks.first.outputs.each_with_object({}) do |o, hash|
        hash[o.output_key] = o.output_value
      end

      if key
        output_hash[key.to_s].output(&method(:puts))
      else
        output_hash.output do |hash|
          print_table hash.sort
        end
      end
    end

    desc 'status NAME', 'get stack status'
    def status(name)
      cf.describe_stacks(stack_name: name).stacks.first.stack_status.output(&method(:puts))
    end

    desc 'template NAME', 'get template for stack named NAME'
    def template(name)
      cf.get_template(stack_name: name).template_body.output do |template|
        puts template
      end
    end

    desc 'validate FILE', 'validate given template in FILE or stdin'
    def validate(file = nil)
      begin
        cf.validate_template(template_body: file_or_stdin(file)).output do |response|
          puts YAML.dump(stringify_keys(response.to_hash))
        end
      rescue Aws::CloudFormation::Errors::ValidationError => e
        e.output { |err| puts err.message }
      end
    end

    desc 'create NAME', 'create stack with name NAME'
    def create(name, file = nil)
      cf.create_stack(stack_name: name, template_body: file_or_stdin(file)).output do |response|
        puts response.stack_id
      end
    end

    desc 'update NAME', 'update stack with name NAME'
    def update(name, file = nil)
      begin
        cf.update_stack(stack_name: name, template_body: file_or_stdin(file)).output do |response|
          puts response.stack_id
        end
      rescue Aws::CloudFormation::Errors::ValidationError => e
        e.output { |err| puts err.message }
      end
    end

    ## note this forces a full stack update and requires permissions to do so
    desc 'tag NAME KEY:VALUE ...', 'update stack tags with one or more key:value pairs'
    def tag(name, *tags)
      params = {
        stack_name:            name,
        use_previous_template: true,
        capabilities:          ['CAPABILITY_IAM'],
        tags: tags.map do |t|
          key, value = t.split(/[:=]/)
          {key: key, value: value}
        end
      }
      cf.update_stack(params).output do |response|
        puts response.stack_id
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
      cf.describe_stack_events(stack_name: name).stack_events.output do |events|
        print_table events.map { |e| [e.timestamp, color(e.resource_status), e.resource_type, e.logical_resource_id, e.resource_status_reason] }
      end
    end

    desc 'resources NAME', 'list resources for stack with name NAME'
    method_option :long,  aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    method_option :type,  aliases: '-t', type: :array,   default: nil,   desc: 'Filter by given resource types, e.g. AWS::IAM::Role'
    method_option :match, aliases: '-m', type: :string,  default: nil,   desc: 'Filter by case-insensitive regex matching type of resource'
    def resources(name)
      resources = cf.list_stack_resources(stack_name: name).stack_resource_summaries

      if options[:type]
        resources.select! do |resource|
          options[:type].include?(resource.resource_type)
        end
      end

      if options[:match]
        resources.select! do |resource|
          Regexp.new(options[:match], Regexp::IGNORECASE).match(resource.resource_type)
        end
      end

      resources.output do |resources|
        if options[:long]
          print_table resources.map { |r| [r.logical_resource_id, r.physical_resource_id, r.resource_type, color(r.resource_status), r.resource_status_reason] }
        else
          puts resources.map(&:logical_resource_id)
        end
      end
    end

    desc 'id NAME RESOURCE', 'get physical_resource_id from a logical_resource_id RESOURCE for stack with NAME'
    method_option :all, aliases: '-a', type: :boolean, default: false, desc: 'Return all details about resource as YAML'
    def id(name, resource)
      detail = cf.describe_stack_resource(stack_name: name, logical_resource_id: resource).stack_resource_detail
      if options[:all]
        detail.output do |d|
          puts YAML.dump(stringify_keys(d.to_hash))
        end
      else
        detail.physical_resource_id.output do |id|
          puts id
        end
      end
    end

    desc 'policy NAME [JSON]', 'get policy for stack NAME, or set from JSON file or stdin'
    method_option :json, aliases: '-j', type: :string, default: nil, desc: 'Inline policy as json string'
    def policy(name, file = nil)
      policy = options[:json].nil? ? file_or_stdin(file) : options[:json]
      if policy
        cf.set_stack_policy(stack_name: name, stack_policy_body: policy)
      else
        cf.get_stack_policy(stack_name: name).stack_policy_body.output(&method(:puts))
      end
    end

    desc 'limits', 'describe cloudformation account limits'
    def limits
      cf.describe_account_limits.account_limits.output do |limits|
        print_table limits.map { |l| [l.name, l.value] }
      end
    end

    ## this is almost entirely useless in practice
    desc 'cost', 'describe cost for given stack'
    def cost(name)
      template = cf.get_template(stack_name: name).template_body
      parameters = cf.describe_stacks(stack_name: name).stacks.first.parameters.map do |p|
        {
          parameter_key:      p.parameter_key,
          parameter_value:    p.parameter_value,
          use_previous_value: true, # use param values from actual stack
        }
      end
      puts cf.estimate_template_cost(template_body: template, parameters: parameters).url
    end
  end
end