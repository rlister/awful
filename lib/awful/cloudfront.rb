module Awful
  module Short
    def cloudfront(*args)
      Awful::CloudFront.new.invoke(*args)
    end
  end

  class CloudFront < Cli

    COLORS = {
      enabled:    :green,
      disabled:   :red,
      deployed:   :green,
      inprogress: :yellow,
    }

    no_commands do
      def cloudfront
        @cloudfront ||= Aws::CloudFront::Client.new
      end

      def color(string)
        set_color(string, COLORS.fetch(string.downcase.to_sym, :blue))
      end
    end

    desc 'ls', 'list distributions'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def ls
      marker = nil
      items = []
      loop do
        response = cloudfront.list_distributions(marker: marker).distribution_list
        items += response.items
        marker = response.next_marker
        break unless marker
      end

      items.output do |list|
        if options[:long]
          print_table list.map { |i|
            origins = i.origins.items.map(&:domain_name).join(',')
            state = i.enabled ? :Enabled : :Disabled
            [ i.id, i.domain_name, origins, color(i.status), color(state), i.last_modified_time ]
          }
        else
          puts list.map(&:id).sort
        end
      end
    end

    desc 'origins ID', 'list origins for distribution with ID'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def origins(id)
      cloudfront.get_distribution(id: id).distribution.distribution_config.origins.items.output do |list|
        if options[:long]
          print_table list.map { |o|
            c = o.custom_origin_config
            config = o.s3_origin_config ? [ 's3' ] : [ 'custom', c.origin_protocol_policy, c.http_port, c.https_port  ]
            [ o.id, o.domain_name, o.origin_path ] + config
          }
        else
          puts list.map(&:id).sort
        end
      end
    end
  end
end