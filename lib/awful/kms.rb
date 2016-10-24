module Awful
  module Short
    def kms(*args)
      Awful::Kms.new.invoke(*args)
    end
  end

  class Kms < Cli
    COLORS = {
      enabled:  :green,
      disabled: :red,
    }

    no_commands do
      def kms
        @_kms ||= Aws::KMS::Client.new
      end

      def color(string)
        set_color(string, COLORS.fetch(string.to_sym, :yellow))
      end

      def paginate(thing)
        next_marker = nil
        things = []
        loop do
          response = yield(next_marker)
          things += response.send(thing)
          next_marker = response.next_marker
          break unless next_marker
        end
        things
      end

      def aliases_hash
        @_aliases_hash ||= paginate(:aliases) do |marker|
          kms.list_aliases(marker: marker)
        end.each_with_object({}) do |a, h|
          h[a.target_key_id] = a.alias_name.gsub(/^alias\//, '')
        end
      end
    end

    desc 'ls', 'list keys'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def ls
      paginate(:keys) do |marker|
        kms.list_keys(marker: marker)
      end.output do |keys|
        if options[:long]
          print_table keys.map { |k|
            key = kms.describe_key(key_id: k.key_id).key_metadata
            [ aliases_hash.fetch(k.key_id, '-'), k.key_id, color(key.enabled ? 'enabled' : 'disabled'), key.creation_date ]
          }.sort
        else
          puts keys.map(&:key_id)
        end
      end
    end

  end
end