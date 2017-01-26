require 'json'

module Awful
  class IAM < Cli

    no_commands do
      def iam
        @iam ||= Aws::IAM::Client.new
      end
    end

    desc 'users', 'list users'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    method_option :mfa,  aliases: '-m', type: :boolean, default: false, desc: 'Show MFA status'
    def users
      iam.list_users.users.output do |users|
        if options[:long]
          print_table users.map { |u| [u.user_name, u.user_id, u.create_date, u.password_last_used] }
        elsif options[:mfa]
          mfa = iam.list_virtual_mfa_devices.virtual_mfa_devices.each_with_object({}) do |m,h|
            next unless m.user
            h[m.user.user_name] = m.enable_date
          end
          print_table users.map { |u| [u.user_name, mfa.fetch(u.user_name, '-')] }
        else
          puts users.map(&:user_name)
        end
      end
    end

    desc 'mfa', 'list MFA devices'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    def mfa
      iam.list_virtual_mfa_devices.virtual_mfa_devices.output do |devices|
        if options[:long]
          print_table devices.map { |d|
            user_name = d.user ? d.user.user_name : '-'
            [user_name, d.serial_number, d.enable_date]
          }
        else
          puts devices.map(&:serial_number)
        end
      end
    end

    desc 'roles [NAME]', 'list IAM roles [matching NAME]'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    method_option :arns, aliases: '-a', type: :boolean, default: false, desc: 'Show ARNs instead of names'
    def roles(name = /./)
      iam.list_roles.roles.select do |role|
        role.role_name.match(name)
      end.output do |roles|
        name_method = options[:arns] ? :arn : :role_name
        if options[:long]
          print_table roles.map { |r|
            [
              r.send(name_method),
              r.role_id,
              r.create_date,
              options[:arns] ? r.arn : nil
            ]
          }
        else
          puts roles.map(&name_method)
        end
      end
    end

    desc 'policy {role,group,user} NAME', 'List or show policy(s) for {role,group,user} NAME'
    method_option :pretty, aliases: '-p', type: :boolean, default: false, desc: 'Pretty-print policy document'
    def policy(type, name, policy = nil)

      ## first matching role, group or user
      thing_name = iam.send("list_#{type}s").send("#{type}s").find do |thing|
        thing.send("#{type}_name").match(name)
      end.send("#{type}_name")

      ## policies for this role, group or user
      policies = iam.send("list_#{type}_policies", "#{type}_name".to_sym => thing_name).policy_names

      if policy.nil?            # just list policies
        policies.output(&method(:puts))
      else                      #  get policy document
        policy_name = policies.find { |p| p.match(/#{policy}/i) }
        doc = iam.send("get_#{type}_policy", "#{type}_name".to_sym => thing_name, policy_name: policy_name).policy_document
        URI.unescape(doc).output do |str|
          if options[:pretty]
            puts JSON.pretty_generate(JSON.parse(str))
          else
            puts str
          end
        end
      end
    end

  end

end