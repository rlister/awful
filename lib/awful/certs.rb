module Awful
  module Short
    def certs(*args)
      Awful::Certs.new.invoke(*args)
    end
  end

  class Certs < Cli
    no_commands do
      def iam
        @iam ||= Aws::IAM::Client.new
      end
    end

    desc 'ls [PATH_PREFIX]', 'list server certificates'
    method_option :long, aliases: '-l', default: false, desc: 'long listing'
    method_option :arns, aliases: '-a', default: false, desc: 'list ARNs'
    def ls(path = nil)
      marker = nil
      certs = []
      loop do
        response = iam.list_server_certificates(path_prefix: path, marker: marker)
        certs += response.server_certificate_metadata_list
        marker = response.marker
        break unless response.is_truncated
      end
      certs.output do |list|
        if options[:long]
          print_table list.map { |c|
            [
              c.server_certificate_name,
              c.path,
              c.server_certificate_id,
              c.upload_date,
              c.expiration,
            ]
          }.sort
        elsif options[:arns]
          puts certs.map(&:arn)
        else
          puts certs.map(&:server_certificate_name).sort
        end
      end
    end

    no_commands do
      def read_file(name)
        name.nil? ? nil : File.read(name)
      end
    end

    desc 'upload NAME', 'upload server certificate'
    method_option :path,  aliases: '-p', type: :string, default: nil, desc: 'path, e.g. /cloudfront/ for cf certs'
    method_option :body,  aliases: '-b', type: :string, default: nil, desc: 'file containing body of certificate'
    method_option :key,   aliases: '-k', type: :string, default: nil, desc: 'file containing private key'
    method_option :chain, aliases: '-c', type: :string, default: nil, desc: 'file containing cert chain'
    def upload(name)
      iam.upload_server_certificate(
        server_certificate_name: name,
        path:                    options[:path],
        certificate_body:        read_file(options[:body]),
        private_key:             read_file(options[:key]),
        certificate_chain:       read_file(options[:chain]),
      ).output do |cert|
        puts cert.server_certificate_metadata.arn
      end
    end

    desc 'dump NAME', 'get details for server certificate'
    method_option :body,  aliases: '-b', type: :string, default: nil, desc: 'output contains cert body'
    method_option :chain, aliases: '-c', type: :string, default: nil, desc: 'output contains cert chain'
    def dump(name)
      iam.get_server_certificate(server_certificate_name: name).server_certificate.output do |cert|
        if options[:body]
          puts cert.certificate_body
        elsif options[:chain]
          puts cert.certificate_chain
        else
          puts YAML.dump(stringify_keys(cert.server_certificate_metadata.to_h))
        end
      end
    end

    desc 'delete NAME', 'delete server certificate'
    def delete(name)
      if yes? "Really delete server certificate #{name}?", :yellow
        iam.delete_server_certificate(server_certificate_name: name)
      end
    end
  end

end