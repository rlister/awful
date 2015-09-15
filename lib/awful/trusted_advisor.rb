module Awful

  class TrustedAdvisor < Cli

    desc 'ls', 'list trusted advisor checks'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = '.')
      support.describe_trusted_advisor_checks(language: 'en').checks.select do |check|
        check.name.match(/#{name}/i)
      end.tap do |checks|
        if options[:long]
          print_table(checks.map { |c| [c.name, c.id, c.category] }.sort)
        else
          puts checks.map(&:name).sort
        end
      end
    end

    desc 'check ID', 'describe check result for given ID'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    method_option :all,  aliases: '-a', default: false, desc: 'List all flagged resources'
    def check(id)
      support.describe_trusted_advisor_check_result(check_id: id).result.tap do |r|
        if options[:long]
          flagged = "#{r.resources_summary.resources_flagged}/#{r.resources_summary.resources_processed}"
          puts "#{r.check_id} #{r.status} #{flagged}"
        elsif options[:all]
          print_table r.flagged_resources.map { |f| f.metadata }.sort
        else
          puts r.status
        end
      end
    end

    desc 'summary NAME', 'check summaries matching name'
    def summary(name = '.')
      checks = support.describe_trusted_advisor_checks(language: 'en').checks.select do |check|
        check.name.match(/#{name}/i)
      end.each_with_object({}) do |check, hash|
        hash[check.id] = check
      end
      support.describe_trusted_advisor_check_summaries(check_ids: checks.keys).summaries.tap do |summaries|
        summaries.map do |s|
          check = checks[s.check_id]
          flagged = "#{s.resources_summary.resources_flagged}/#{s.resources_summary.resources_processed}"
          [check.name, s.check_id, s.status, flagged, s.timestamp]
        end.tap { |list| print_table list.sort }
      end
    end

  end

end
