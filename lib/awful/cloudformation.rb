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

  end
end
