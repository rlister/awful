require 'yaml'
require 'aws-sdk-acm'

module Awful
  class Acm < Cli
    COLORS = {
      ISSUED: :green,
      EXPIRED: :red,
      REVOKED: :red,
      FAILED: :red,
      in_use: :green,
      not_in_use: :red,
    }

    no_commands do
      def acm
        @_acm ||= Aws::ACM::Client.new
      end

      ## return array of certs matching domain name or arn
      def find_certs(string = /./)
        acm.list_certificates().map(&:certificate_summary_list).flatten.select do |c|
          (c.domain_name.match(string)) || (c.certificate_arn.match(string))
        end
      end
    end

    desc 'ls', 'list certs'
    method_option :long,       aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    method_option :not_issued, aliases: '-u', type: :boolean, default: false, desc: 'certs not issued'
    def ls
      statuses = options[:not_issued] ? %w[ PENDING_VALIDATION INACTIVE EXPIRED VALIDATION_TIMED_OUT REVOKED FAILED ] : []
      certs = acm.list_certificates(certificate_statuses: statuses).map(&:certificate_summary_list).flatten
      if options[:long]
        print_table certs.map { |c|
          [ c.domain_name, c.certificate_arn.split('/').last ]
        }.sort
      else
        puts certs.map(&:domain_name).sort
      end
    end

    desc 'get NAME', 'get details for matching certs'
    def get(name = nil)
      print_table find_certs(name).map { |cert|
        c = acm.describe_certificate(certificate_arn: cert.certificate_arn).certificate
        use = c.in_use_by.empty? ? 'not_in_use' : 'in_use'
        arn = c.certificate_arn.split('/').last
        created = c&.created_at&.strftime('%Y-%m-%d')
        expires = c&.not_after&.strftime('%Y-%m-%d')
        [ c.domain_name, arn, color(c.status), color(use), created, expires ]
      }
    end

    desc 'dump NAME', 'show cert details'
    def dump(name)
      find_certs(name).each do |c|
        acm.describe_certificate(certificate_arn: c.certificate_arn).certificate.output do |cert|
          puts YAML.dump(stringify_keys(cert.to_hash))
        end
      end
    end

    desc 'delete CERT', 'delete certificate by domain or arn'
    def delete(string)
      find_certs(string).each do |c|
        if yes?("Delete #{c.certificate_arn}?", :yellow)
          acm.delete_certificate(certificate_arn: c.certificate_arn)
        end
      end
    end

  end
end
