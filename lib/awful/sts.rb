module Awful
  module Short
    def sts(*args)
      Awful::Sts.new.invoke(*args)
    end
  end

  class Sts < Cli
    no_commands do
      def sts
        @sts ||= Aws::STS::Client.new
      end
    end

    desc 'assume_role ARN NAME', 'Return credentials for given role'
    method_option :duration_seconds, aliases: '-d', type: :numeric, default: nil, desc: 'Duration of session in sec'
    method_option :policy,           aliases: '-p', type: :string,  default: nil, desc: 'Access policy as JSON string'
    def assume_role(arn, name)
      opts = only_keys_matching(symbolize_keys(options), %i[duration_seconds policy])
      params = { role_arn: arn, role_session_name: name }.merge(opts)
      sts.assume_role(params).tap do |session|
        puts YAML.dump(stringify_keys(session.to_hash))
      end
    end
  end
end