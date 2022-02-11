require 'aws-sdk-cloudformation'

module Awful
  module Short
    def changesets(*args)
      Awful::Changesets.new.invoke(*args)
    end
  end

  class Changesets < Thor
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
      add:                                 :green,
      modify:                              :yellow,
      remove:                              :red,
    }

    no_commands do
      def cf
        @cf ||= Aws::CloudFormation::Client.new
      end

      def color(string)
        set_color(string, COLORS.fetch(string.downcase.to_sym, :blue))
      end
    end

    ## if no task given , run this
    default_task :list

    desc 'list STACK_NAME [CHANGE_SET_NAME]', 'meta task to call ls or changes'
    def list(stack_name, change_set_name = nil)
      if change_set_name
        changes(stack_name, change_set_name)
      else
        ls(stack_name)
      end
    end

    desc 'ls STACK_NAME', 'list change sets for stack'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    def ls(stack_name)
      cf.list_change_sets(stack_name: stack_name).summaries.tap do |list|
        if options[:long]
          print_table list.map { |cs|
            [
              cs.change_set_name,
              color(cs.status),
              cs.creation_time
            ]
          }
        else
          puts list.map(&:change_set_name)
        end
      end
    end

    desc 'changes STACK_NAME CHANGE_SET_NAME', 'list changes for the change set'
    def changes(stack_name, change_set_name)
      cf.describe_change_set(stack_name: stack_name, change_set_name: change_set_name).tap do |set|
        print_table set.changes.map { |change|
          rc = change.resource_change
          [
            color(rc.action),
            rc.logical_resource_id,
            rc.physical_resource_id,
            rc.resource_type,
            rc.replacement
          ]
        }
      end
    end
  end

  ## add as a subcommand of `cf`
  class CloudFormation < Cli
    desc 'changesets', 'control changesets'
    subcommand 'changesets', Changesets
  end
end