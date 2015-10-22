module Awful

  class S3 < Cli

    no_commands do

      ## resource interface to S3 commands
      def s3_resource
        Aws::S3::Resource.new(client: s3)
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
      end.tap do |list|
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
      end.tap { |list| puts list }
    end

    desc 'cat BUCKET/OBJECT', 'stream s3 object to stdout'
    def cat(path)
      bucket, key = path.split('/', 2)
      s3.get_object(bucket: bucket, key: key) do |chunk|
        $stdout.write(chunk)
      end
    end

    desc 'upload FILE BUCKET/OBJECT', 'upload FILE to given object'
    def upload(file, s3path)
      bucket, key = s3path.split('/', 2)
      s3_resource.bucket(bucket).object(key).upload_file(file)
    end

  end

end
