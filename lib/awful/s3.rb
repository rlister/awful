module Awful

  class S3 < Cli

    desc 'list_buckets [PATTERN]', 'list buckets'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def list_buckets(name = /./)
      s3.list_buckets.buckets.select do |bucket|
        bucket.name.match(name)
      end.tap do |list|
        if options[:long]
          print_table list.map { |b| [ b.name, b.creation_date ] }
        else
          puts list.map(&:name)
        end
      end
    end

    desc 'list_objects BUCKET [PATTERN]', 'list objects in bucket'
    def list_objects(bucket, prefix = nil)
      # s3.list_objects(bucket: bucket, prefix: prefix, delimiter: '').contents.map(&:key).tap do |list|
      #   puts list
      # end
      Aws::S3::Resource.new(client: s3).bucket(bucket).objects(delimiter: '', prefix: prefix).map do |object|
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

  end

end
