require 'base64'

module Awful
  module Short
    def kms(*args)
      Awful::Kms.new.invoke(*args)
    end
  end

  class Kms < Cli
    COLORS = {
      Enabled:         :green,
      PendingDeletion: :red,
    }

    no_commands do
      def kms
        @_kms ||= Aws::KMS::Client.new
      end

      def color(string)
        set_color(string, COLORS.fetch(string.to_sym, :yellow))
      end

      def aliases
        paginate(:aliases) do |marker|
          kms.list_aliases(marker: marker)
        end
      end

      def aliases_hash
        @_aliases_hash ||= aliases.each_with_object({}) do |a, h|
          h[a.target_key_id] = a.alias_name.gsub(/^alias\//, '')
        end
      end

      ## return target id for alias
      def alias_by_name(name)
        aliases.find do |a|
          a.alias_name == "alias/#{name}"
        end.target_key_id
      end

      def is_uuid?(id)
        id.match(/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i)
      end

      def id_or_alias(id)
        is_uuid?(id) ? id : alias_by_name(id)
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
            [ aliases_hash.fetch(k.key_id, '-'), k.key_id, color(key.key_state), key.creation_date ]
          }.sort
        else
          puts keys.map(&:key_id)
        end
      end
    end

    desc 'get ID', 'describe KMS key with ID'
    def get(id)
      kms.describe_key(key_id: id_or_alias(id)).key_metadata.output do |key|
        puts YAML.dump(stringify_keys(key.to_hash))
      end
    end

    desc 'policy ID', 'get key policy'
    method_option :name, aliases: '-n', type: :string, default: :default, desc: 'policy name'
    def policy(id)
      kms.get_key_policy(key_id: id_or_alias(id), policy_name: options[:name]).policy.output do |policy|
        puts policy
      end
    end

    desc 'encrypt ID', 'encrypt data using KMS key'
    def encrypt(id, data)
      blob = kms.encrypt(key_id: id, plaintext: data).ciphertext_blob
      puts Base64.encode64(blob)
    end

    desc 'decrypt', 'decrypt'
    def decrypt(data)
      key = Base64.decode64(data)
      puts kms.decrypt(ciphertext_blob: key)
    end

    desc 'tag KEY=VALUE ...', 'add one or more tags to key'
    def tag(id, *tags)
      kms.tag_resource(
          key_id: id_or_alias(id),
          tags: tags.map do |tag|
            k,v = tag.split(/[:=]/)
            {tag_key: k, tag_value: v}
          end
        )
    end

    desc 'tags', 'list tags for key'
    def tags(id)
      paginate(:tags) do |marker|
        kms.list_resource_tags(
          key_id: id_or_alias(id),
          next_marker: marker,
        )
      end.output do |tags|
        print_table tags.map(&:to_a)
      end
    end

  end
end