module Awful
  module Short
    def s3(*args)
      Awful::S3.new.invoke(*args)
    end
  end

  class S3 < Cli
    no_commands do
      ## resource interface to S3 commands
      def s3_resource
        Aws::S3::Resource.new(client: s3)
      end

      def get_tags(bucket_name)
        s3.get_bucket_tagging(bucket: bucket_name).tag_set
      rescue Aws::S3::Errors::NoSuchTagSet # sdk throws this if no tags
        nil
      end
    end

    desc 'ls PATTERN', 'list buckets or objects'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = '.')
      if name.include?('/')
        bucket, prefix = name.split('/', 2)
        invoke 'objects', [bucket, prefix], options
      else
        invoke 'buckets', [name], options
      end
    end

    desc 'buckets [PATTERN]', 'list buckets'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def buckets(name = /./)
      s3.list_buckets.buckets.select do |bucket|
        bucket.name.match(/#{name}/)
      end.output do |list|
        if options[:long]
          print_table list.map { |b| [ b.name, b.creation_date ] }
        else
          puts list.map(&:name)
        end
      end
    end

    desc 'objects BUCKET [PATTERN]', 'list objects in bucket'
    def objects(bucket, prefix = nil)
      s3_resource.bucket(bucket).objects(prefix: prefix).map do |object|
        object.key
      end.output { |list| puts list }
    end

    desc 'exists? NAME', 'test if bucket exists'
    def exists?(bucket_name)
      begin
        s3.head_bucket(bucket: bucket_name) && true
      rescue Aws::S3::Errors::NotFound
        false
      end.output(&method(:puts))
    end

    desc 'empty? NAME', 'test if bucket is empty'
    def empty?(bucket_name)
      s3.list_objects(bucket: bucket_name, max_keys: 1).contents.empty?.output(&method(:puts))
    end

    desc 'tagged [NAME_PREFIX]', 'list buckets matching given tags'
    method_option :tags,     aliases: '-t', type: :array,  default: [],  desc: 'List of tag=value to filter'
    method_option :stack,    aliases: '-s', type: :string, default: nil, desc: 'Filter by stack name'
    method_option :resource, aliases: '-r', type: :string, default: nil, desc: 'Filter by stack resource logical id'
    def tagged(name = '.')
      conditions = options[:tags].map do |tag|
        key, value = tag.split('=')
        ->(set) { (set[0] == key) && (set[1] == value) }
      end
      if options[:stack]
        conditions << ->(set) { (set[0] == 'aws:cloudformation:stack-name') && (set[1] == options[:stack]) }
      end
      if options[:resource]
        conditions << ->(set) { (set[0] == 'aws:cloudformation:logical-id') && (set[1] == options[:resource]) }
      end

      ## get all buckets and check for a match with conditions
      s3.list_buckets.buckets.select do |b|
        b.name.match(/^#{name}/i)
      end.map do |bucket|
        tags = get_tags(bucket.name) or next
        tags.any? do |set|
          conditions.any? { |c| c.call(set) }
        end && bucket
      end.select{|b| b}.output do |buckets|
        puts buckets.map(&:name)
      end
    end

    ## deprecated in favour of get below
    desc 'cat BUCKET/OBJECT', 'stream s3 object to stdout'
    def cat(path)
      bucket, key = path.split('/', 2)
      s3.get_object(bucket: bucket, key: key) do |chunk|
        $stdout.write(chunk)
      end
    end

    ## new version of cat
    desc 'get BUCKET OBJECT [FILENAME]', 'get object from bucket'
    def get(bucket, key, filename = nil)
      if filename
        s3.get_object(bucket: bucket, key: key, response_target: filename)
      else
        s3.get_object(bucket: bucket, key: key).output do |response|
          puts response.body.read
        end
      end
    end

    ## deprecated in favour of put below
    desc 'upload FILE BUCKET/OBJECT', 'upload FILE to given object'
    def upload(file, s3path)
      bucket, key = s3path.split('/', 2)
      s3_resource.bucket(bucket).object(key).upload_file(file)
    end

    ## this is the new version of upload
    desc 'put BUCKET OBJECT [FILENAME]', 'put object in bucket from file/stdin/string'
    method_option :string, aliases: '-s', type: :string, default: nil, desc: 'send string instead of reading a file'
    method_option :kms,    aliases: '-k', type: :string, default: nil, desc: 'KMS key ID for encryption'
    def put(bucket, key, filename = nil)
      body = options.fetch('string', file_or_stdin(filename))
      s3.put_object(
        bucket: bucket,
        key: key,
        body: body,
        server_side_encryption: options[:kms] ? 'aws:kms' : nil,
        ssekms_key_id: options[:kms],
      )
    end

    desc 'remove_bucket NAME', 'delete a bucket, which must be empty'
    def remove_bucket(name)
      if yes? "Really delete bucket #{name}?", :yellow
        s3.delete_bucket(bucket: name)
      end
    end

    ## rb is an alias for remove_bucket
    map :rb => :remove_bucket

    no_commands do
      def clean_objects(bucket, marker = nil)
        ## get 100 objects at a time
        objects = s3.list_objects(bucket: bucket, marker: marker)
        return if objects.contents.empty?

        ## delete them all
        s3.delete_objects(
          bucket: bucket,
          delete: {
            objects: objects.contents.map { |obj| { key: obj.key } }
          }
        )

        ## recurse if there are more
        if objects.next_marker
          clean_objects(bucket, objects.next_marker)
        end
      end
    end

    desc 'clean NAME', 'remove all objects from bucket'
    def clean(name)
      if yes? "Really delete ALL objects in bucket #{name}?", :yellow
        clean_objects(name)
      end
    end

    desc 'delete BUCKET OBJECTS', 'delete objects from bucket'
    def delete(bucket, *objects)
      s3.delete_objects(
        bucket: bucket,
        delete: {
          objects: objects.map{ |k| {key: k} }
        }
      )
    end
  end
end