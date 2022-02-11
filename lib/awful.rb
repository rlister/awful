require 'awful/version'

require 'dotenv'
require 'aws-sdk'
require 'thor'
require 'yaml'
require 'erb'

## our implementation of tap for switchable output
class Object
  def output
    yield self unless $awful_quiet
    self
  end
end

module Awful
  class Cli < Thor
    class_option :env,   aliases: '-e', type: :string,  default: nil,   desc: 'Load environment variables from file'
    class_option :quiet, aliases: '-q', type: :boolean, default: false, desc: 'Quieten output'
    class_option :yes,                  type: :boolean, default: false, desc: 'Always answer yes to prompts'
    class_option :region,               type: :string,  default: nil,   desc: 'Set region; can use AWS_REGION instead'

    def initialize(args = [], local_options = {}, config = {})
      super
      $awful_quiet = options[:quiet]                           # turn off output
      ENV['AWS_REGION'] = options[:region] if options[:region] #cmdline override for region
    end

    no_commands do
      ## override thor yes? method to handle our yes option
      def yes?(statement, color = nil)
        options[:yes] ? say("#{statement} yes", color) : super(statement, color)
      end

      def ec2
        @ec2 ||= Aws::EC2::Client.new
      end

      def autoscaling
        @autoscaling ||= Aws::AutoScaling::Client.new
      end

      def elb
        @elb ||= Aws::ElasticLoadBalancing::Client.new
      end

      def rds
        @rds ||= Aws::RDS::Client.new
      end

      def datapipeline
        @datapipeline ||= Aws::DataPipeline::Client.new
      end

      ## to use dynamodb-local, set DYNAMO_ENDPOINT or DYNAMODB_ENDPOINT to e.g. http://localhost:8000
      def dynamodb
        options = {endpoint: ENV['DYNAMO_ENDPOINT'] || ENV['DYNAMODB_ENDPOINT']}.reject { |_,v| v.to_s.empty? }
        @dynamodb ||= Aws::DynamoDB::Client.new(options)
      end

      ## dynamodb client with parameter conversion turned off,
      ## for getting result as Aws::Plugins::Protocols::JsonRpc;
      ## see https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DataFormat.html;
      ## client method calls need simple attributes in requests also (strings not symbols, etc)
      def dynamodb_simple
        options = {
          simple_attributes: false,
          simple_json: true,
          endpoint: ENV['DYNAMO_ENDPOINT'] || ENV['DYNAMODB_ENDPOINT'],
        }.reject { |_,v| v.nil? }
        @dynamodb_simple ||= Aws::DynamoDB::Client.new(options)
      end

      def s3
        @s3 ||= Aws::S3::Client.new
      end

      def cf
        @cf ||= Aws::CloudFormation::Client.new
      end

      def lambda
        @lambda ||= Aws::Lambda::Client.new
      end

      def support
        @support ||= Aws::Support::Client.new
      end

      def cf
        @cf ||= Aws::CloudFormation::Client.new
      end

      def symbolize_keys(thing)
        if thing.is_a?(Hash)
          Hash[ thing.map { |k,v| [ k.to_sym, symbolize_keys(v) ] } ]
        elsif thing.respond_to?(:map)
          thing.map { |v| symbolize_keys(v) }
        else
          thing
        end
      end

      def stringify_keys(thing)
        if thing.is_a?(Hash)
          Hash[ thing.map { |k,v| [ k.to_s, stringify_keys(v) ] } ]
        elsif thing.respond_to?(:map)
          thing.map { |v| stringify_keys(v) }
        else
          thing
        end
      end

      ## returns contents of named file, or stdin if file = nil, or false if no stdin
      def file_or_stdin(file)
        (file and File.read(file)) || ((not $stdin.tty?) and $stdin.read)
      end

      ## merge options with config from erb-parsed yaml stdin or file
      def load_cfg(options = {}, file = nil)
        Dotenv.overload(options[:env]) if options[:env]
        src = (file and File.read(file)) || ((not $stdin.tty?) and $stdin.read)
        cfg = src ? YAML.load(::ERB.new(src).result(binding)) : {}
        symbolize_keys(cfg).merge(symbolize_keys(options.reject{ |_,v| v.nil? }))
      end

      ## return a copy of hash, but with only listed keys
      def only_keys_matching(hash, keylist)
        hash.select do |key,_|
          keylist.include?(key)
        end
      end

      def remove_empty_strings(hash)
        hash.reject do |_,value|
          value.respond_to?(:empty?) and value.empty?
        end
      end

      def tag_name(thing, default = nil)
        tn = thing.tags.find { |tag| tag.key == 'Name' }
        tn ? tn.value : default
      end

      ## return id for instance by name
      def find_instance(name)
        if name .nil?
          nil?
        elsif name.match(/^i-[\d[a-f]]{8,17}$/)
          name
        else
          ec2.describe_instances.map(&:reservations).flatten.map(&:instances).flatten.find do |instance|
            tag_name(instance) == name
          end.instance_id
        end
      end

      ## return id for subnet by name
      def find_subnet(name)
        if name.match(/^subnet-[\d[a-f]]{8}$/)
          name
        else
          ec2.describe_subnets.map(&:subnets).flatten.find do |subnet|
            tag_name(subnet) == name
          end.subnet_id
        end
      end

      ## return id for security group by name
      def find_sg(name)
        if name.match(/^sg-[\d[a-f]]{8}$/)
          name
        else
          ec2.describe_security_groups.map(&:security_groups).flatten.find do |sg|
            tag_name(sg) == name
          end.group_id
        end
      end

      ## universal paginator for aws-sdk calls
      def paginate(thing)
        token = nil
        things = []
        loop do
          resp = yield(token)
          things += resp.send(thing)
          ## some apis use marker, some use token
          token = resp.respond_to?(:next_marker) ? resp.next_marker : resp.next_token
          break if token.nil?
        end
        things
      end
    end

    desc 'version', 'print version'
    def version
      puts VERSION
      exit
    end

  end
end