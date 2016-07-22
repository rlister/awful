module Awful
  module Short
    def ami(*args)
      Awful::Ami.new.invoke(*args)
    end
  end

  class Ami < Cli
    class_option :owners,  aliases: '-o', type: :string, default: 'self', desc: 'List images with this owner'
    class_option :filters, aliases: '-f', type: :array,  default: [],     desc: 'Filter using name=value, eg tag:Foo=bar, multiples are ANDed'

    COLORS = {
      available: :green,
      pending:   :yellow,
      failed:    :red,
    }

    no_commands do
      def images(options)
        params = {
          owners:  options[:owners].split(','),
          filters: options[:filters].map do |tag|
            k, v = tag.split('=')
            {name: k, values: v.split(',')}
          end
        }.reject { |k,v| v.empty? }
        ec2.describe_images(params).map(&:images).flatten
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
      end.output do |list|
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
      end.output do |ami|
        if yes? "Really deregister image #{ami.name} (#{ami.image_id})?", :yellow
          ec2.deregister_image(image_id: ami.image_id)
        end
      end
    end

    desc 'dump IDS', 'describe images'
    def dump(*ids)
      ec2.describe_images(image_ids: ids).images.output do |images|
        images.each do |image|
          puts YAML.dump(stringify_keys(image.to_hash))
        end
      end
    end

    desc 'tags ID [TAGS]', 'get tags for AMI, or set multiple tags as key:value'
    def tags(id, *tags)
      if tags.empty?
        ec2.describe_images(image_ids: [id]).images.first.tags.output do |list|
          print_table list.map { |t| [t.key, t.value] }
        end
      else
        ec2.create_tags(
          resources: [id],
          tags: tags.map do |t|
            key, value = t.split(/[:=]/)
            {key: key, value: value}
          end
        )
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

    desc 'last NAME', 'get ids of last (by creation date) AMIs [matching NAME]'
    method_option :count, aliases: '-n', type: :numeric, default: 1, desc: 'Return N results'
    def last(name = /./)
      images(options).select do |image|
        image.name.match(name)
      end.sort_by(&:creation_date).last(options[:count]).map do |image|
        image.image_id
      end.output do |list|
        puts list
      end
    end
  end
end