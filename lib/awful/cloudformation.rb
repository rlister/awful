require 'aws-sdk-cloudformation'

module Awful
  module Short
    def cf(*args)
      Awful::CloudFormation.new.invoke(*args)
    end
  end

  class CloudFormation < Cli

    COLORS = {
      CREATE_COMPLETE:      :green,
      CREATE_FAILED:        :red,
      DELETE_COMPLETE:      :green,
      DELETE_FAILED:        :red,
      IMPORT_COMPLETE:      :green,
      ROLLBACK_COMPLETE:    :red,
      ROLLBACK_FAILED:      :red,
      ROLLBACK_IN_PROGRESS: :red,
      UPDATE_COMPLETE:      :green,
      UPDATE_FAILED:        :red,
    }

    ## stack statuses that are not DELETE_COMPLETE
    STATUSES = %i[
      CREATE_IN_PROGRESS CREATE_FAILED CREATE_COMPLETE
      ROLLBACK_IN_PROGRESS ROLLBACK_FAILED ROLLBACK_COMPLETE
      DELETE_IN_PROGRESS DELETE_FAILED
      IMPORT_IN_PROGRESS IMPORT_COMPLETE IMPORT_ROLLBACK_IN_PROGRESS IMPORT_ROLLBACK_FAILED IMPORT_ROLLBACK_COMPLETE
      UPDATE_IN_PROGRESS UPDATE_COMPLETE_CLEANUP_IN_PROGRESS UPDATE_COMPLETE
      UPDATE_ROLLBACK_IN_PROGRESS UPDATE_ROLLBACK_FAILED UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS UPDATE_ROLLBACK_COMPLETE
      REVIEW_IN_PROGRESS
    ]

    desc 'ls [PATTERN]', 'list cloudformation stacks matching PATTERN'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def ls(name = nil)
      paginate(:stack_summaries) do |next_token|
        cf.list_stacks(stack_status_filter: STATUSES, next_token: next_token)
      end.tap do |stacks|
        stacks.select! { |s| s.stack_name.match(name) } if name
      end.output do |list|
        if options[:long]
          print_table list.map { |s|
            [s.stack_name, s.creation_time, color(s.stack_status), s.template_description]
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
    method_option :number, aliases: '-n', type: :numeric, default: nil, desc: 'return n most recent events'
    def events(name)
      events = cf.describe_stack_events(stack_name: name).stack_events
      events = events.first(options[:number]) if options[:number]
      events.reverse.output do |events|
        print_table events.map { |e|
          [e.timestamp, color(e.resource_status), e.resource_type, e.logical_resource_id, e.resource_status_reason]
        }
      end
    end

    desc 'resources NAME', 'list resources for stack with name NAME'
    method_option :long,  aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    method_option :type,  aliases: '-t', type: :array,   default: nil,   desc: 'Filter by given resource types, e.g. AWS::IAM::Role'
    method_option :match, aliases: '-m', type: :string,  default: nil,   desc: 'Filter by case-insensitive regex matching type of resource'
    method_option :truncate,             type: :boolean, default: true,  desc: 'truncate long lines'
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
          print_table(
            resources.map { |r|
              [
                r.logical_resource_id,
                r.resource_type,
                color(r.resource_status),
                r.physical_resource_id,
              ]
            },
            truncate: options[:truncate]
          )
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

    desc 'sets', 'list stack sets'
    method_option :long,   aliases: '-l', type: :boolean, default: false,    desc: 'long listing'
    method_option :status, aliases: '-s', type: :string,  default: 'ACTIVE', desc: 'ACTIVE or DELETED'
    def sets
      paginate(:summaries) do |next_token|
        cf.list_stack_sets(status: options[:status].upcase, next_token: next_token)
      end.output do |sets|
        if options[:long]
          print_table sets.map { |s|
            [s.stack_set_name, s.stack_set_id, color(s.status), s.description]
          }
        else
          puts sets.map(&:stack_set_name)
        end
      end
    end

  end
end
