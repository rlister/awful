require 'aws-sdk-iam'
require 'json'

module Awful
  class IAM < Cli
    COLORS = {
      Active:   :green,
      Inactive: :red,
    }

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

    desc 'keys', 'list access keys'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    method_option :user, aliases: '-u', type: :string,  default: nil,   desc: 'show different user'
    method_option :delete,              type: :string,  default: nil,   desc: 'delete named key'
    def keys
      if options[:delete]
        if yes?("Really delete key #{options[:delete]}?", :yellow)
          iam.delete_access_key(access_key_id: options[:delete])
        end
        return
      end

      ## list keys
      iam.list_access_keys(user_name: options[:user]).access_key_metadata.output do |keys|
        if options[:long]
          print_table keys.map{ |k|
            [k.user_name, k.access_key_id, k.create_date, color(k.status)]
          }
        else
          puts keys.map(&:access_key_id)
        end
      end
    end

    desc 'old', 'report on old access keys'
    method_option :days, aliases: '-d', type: :numeric, default: 90,    desc: 'age in days to treat as old'
    method_option :all,  aliases: '-a', type: :boolean, default: false, desc: 'list all users'
    def old
      iam.list_users.users.map do |u|
        iam.list_access_keys(user_name: u.user_name).access_key_metadata.map do |k|
          age = ((Time.now - k.create_date)/(60*60*24)).to_i
          too_old = age > options[:days]
          if options[:all] || too_old
            [k.user_name, k.create_date, set_color("#{age} days", too_old ? :red : :green)]
          else
            nil
          end
        end
      end.flatten(1).reject(&:nil?).output do |list|
        print_table list
      end
    end

    desc 'rotate', 'rotate access key for user'
    method_option :user, aliases: '-u', type: :string,  default: nil,   desc: 'show different user'
    def rotate
      key = iam.create_access_key(user_name: options[:user]).access_key
      puts(
        "Your new credentials:",
        "AWS_ACCESS_KEY_ID=#{key.access_key_id}",
        "AWS_SECRET_ACCESS_KEY=#{key.secret_access_key}",
      )
    rescue Aws::IAM::Errors::LimitExceeded
      warn 'You have two access keys: please delete one and run this command again.'
    end

  end

end
