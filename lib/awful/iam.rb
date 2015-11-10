module Awful

  class IAM < Cli

    no_commands do
      def iam
        @iam ||= Aws::IAM::Client.new
      end
    end

    desc 'certificates [NAME]', 'list server certificates [matching NAME]'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def certificates(name = /./)
      iam.list_server_certificates.server_certificate_metadata_list.select do |cert|
        cert.server_certificate_name.match(name)
      end.tap do |certs|
        if options[:long]
          print_table certs.map { |c|
            [
              c.server_certificate_name,
              c.server_certificate_id,
              c.arn,
              c.upload_date,
              c.expiration,
            ]
          }.sort
        else
          puts certs.map(&:server_certificate_name).sort
        end
      end
    end

    desc 'roles [NAME]', 'list IAM roles [matching NAME]'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    method_option :arns, aliases: '-a', default: false, desc: 'Show ARNs instead of names'
    def roles(name = /./)
      iam.list_roles.roles.select do |role|
        role.role_name.match(name)
      end.tap do |roles|
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
    method_option :pretty, aliases: '-p', default: false, desc: 'Pretty-print policy document'
    def policy(type, name, policy = nil)

      ## first matching role, group or user
      thing_name = iam.send("list_#{type}s").send("#{type}s").find do |thing|
        thing.send("#{type}_name").match(name)
      end.send("#{type}_name")

      ## policies for this role, group or user
      policies = iam.send("list_#{type}_policies", "#{type}_name".to_sym => thing_name).policy_names

      if policy.nil?            # just list policies
        policies.tap(&method(:puts))
      else                      #  get policy document
        policy_name = policies.find { |p| p.match(/#{policy}/i) }
        doc = iam.send("get_#{type}_policy", "#{type}_name".to_sym => thing_name, policy_name: policy_name).policy_document
        URI.unescape(doc).tap do |str|
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