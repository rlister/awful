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

  end

end
