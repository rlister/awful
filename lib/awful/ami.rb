module Awful

  class Ami < Cli
    class_option :owners, aliases: '-o', default: 'self', desc: 'List images with this owner'

    COLORS = {
      available: :green,
      pending:   :yellow,
      failed:    :red,
    }

    no_commands do
      def images(options)
        ec2.describe_images(owners: options[:owners].split(',')).map(&:images).flatten
      end

      def color(string)
        set_color(string, COLORS.fetch(string.to_sym, :yellow))
      end
    end

    desc 'ls [PATTERN]', 'list AMIs'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      images(options).select do |image|
        image.name.match(name)
      end.tap do |list|
        if options[:long]
          print_table list.map { |i|
            [ i.name, i.image_id, i.root_device_type, color(i.state), i.creation_date, i.tags.map{ |t| "#{t.key}=#{t.value}" }.sort.join(',') ]
          }.sort
        else
          puts list.map(&:name).sort
        end
      end
    end

    desc 'delete NAME', 'delete AMI'
    def delete(id)
      images(options).find do |image|
        image.image_id.match(id)
      end.tap do |ami|
        if yes? "Really deregister image #{ami.name} (#{ami.image_id})?", :yellow
          ec2.deregister_image(image_id: ami.image_id)
        end
      end
    end

    desc 'tags ID [KEY=VALUE]', 'tag an image, or print tags'
    def tags(id, tag = nil)
      ami = images(options).find do |image|
        image.image_id.match(id)
      end
      if tag
        key, value = tag.split('=')
        ec2.create_tags(resources: [ami.image_id],  tags: [{key: key, value: value}])
      else
        puts ami.tags.map { |t| "#{t[:key]}=#{t[:value]}" }
      end
    end

    # desc 'copy ID REGION', 'copy image from given REGION to current region'
    # def copy(id, region)
    #   current_region = ENV['AWS_REGION']
    #   ENV['AWS_REGION'] = region
    #   images(options).find do |image|
    #     image.image_id.match(id)
    #   end.tap do |ami|
    #     ENV['AWS_REGION'] = current_region
    #     ec2.copy_image(source_image_id: ami.image_id, source_region: region, name: ami.name, description: ami.description)
    #   end
    # end

    desc 'last NAME', 'get last AMI matching NAME'
    def last(name, n = 1)
      images(options).select do |image|
        image.name.match(name)
      end.sort_by { |i| i.creation_date }.last(n.to_i).map do |image|
        image.image_id
      end.tap do |list|
        puts list
      end
    end

  end

end
