require 'yaml'

module Awful
  module Short
    def acm(*args)
      Awful::Acm.new.invoke(*args)
    end
  end

  class Acm < Cli
    no_commands do
      def acm
        @_acm ||= Aws::ACM::Client.new
      end

      def find_cert(n)
        paginate(:certificate_summary_list) do |next_token|
          acm.list_certificates(next_token: next_token)
        end.find do |cert|
          (n == cert.domain_name) || (n == cert.certificate_arn)
        end
      end
    end

    desc 'ls', 'stuff'
    method_option :long,     aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    method_option :arn,      aliases: '-a', type: :boolean, default: false, desc: 'list ARNs for certs'
    method_option :statuses, aliases: '-s', type: :array,   default: [],    desc: 'pending_validation,issued,inactive,expired,validation_timed_out,revoked,failed'
    def ls
      paginate(:certificate_summary_list) do |next_token|
        acm.list_certificates(
          certificate_statuses: options[:statuses].map(&:upcase),
          next_token: next_token
        )
      end.output do |certs|
        if options[:long]
          print_table certs.map { |cert|
            c = acm.describe_certificate(certificate_arn: cert.certificate_arn).certificate
            [c.domain_name, c.subject_alternative_names.join(','), c.status, c.type, (c.in_use_by.empty? ? 'in use' : 'not in use')]
          }
        elsif options[:arn]
          print_table certs.map { |c| [c.domain_name, c.certificate_arn] }
        else
          puts certs.map(&:domain_name)
        end
      end
    end

    desc 'dump CERT', 'get cert details by ARN or domain name'
    def dump(n)
      acm.describe_certificate(certificate_arn: find_cert(n).certificate_arn).certificate.output do |cert|
        puts YAML.dump(stringify_keys(cert.to_hash))
      end
    end

    desc 'delete CERT', 'delete certificate from ACM'
    def delete(n)
      acm.delete_certificate(certificate_arn: find_cert(n).certificate_arn)
    end

  end
end