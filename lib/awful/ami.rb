module Awful
  module Short
    def ami(*args)
      Awful::Ami.new.invoke(*args)
    end
  end

  class Ami < Cli
    class_option :owners,  aliases: '-o', type: :array, default: %w[self], desc: 'List images with this owner'
    class_option :filters, aliases: '-f', type: :array, default: [],       desc: 'Filter using name=value, eg tag:Foo=bar, multiples are ANDed'

    COLORS = {
      available: :green,
      pending:   :yellow,
      failed:    :red,
    }

    no_commands do
      def images(*image_ids)
        params = {
          image_ids: Array(image_ids),
          owners:  options[:owners],
          filters: options[:filters].map do |tag|
            k, v = tag.split('=')
            {name: k, values: v.split(',')}
          end
        }.reject { |k,v| v.empty? }

        ec2.describe_images(params).images
      end
    end

    desc 'ls [IDS]', 'list AMIs'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    def ls(*ids)
      images(*ids).output do |list|
        if options[:long]
          print_table list.map { |i|
            [ i.name, i.image_id, i.root_device_type, color(i.state), i.creation_date, i.tags.map{ |t| "#{t.key}=#{t.value}" }.sort.join(',') ]
          }.sort
        else
          puts list.map(&:name).sort
        end
      end
    end

    desc 'delete ID', 'delete AMI'
    def delete(id)
      ami = images(id).first
      if yes? "Really deregister image #{ami.name} (#{ami.image_id})?", :yellow
        ec2.deregister_image(image_id: ami.image_id)
      end
    end

    desc 'dump IDS', 'describe images'
    def dump(*ids)
      images(*ids).output do |images|
        images.each do |image|
          puts YAML.dump(stringify_keys(image.to_hash))
        end
      end
    end

    desc 'tags ID [TAGS]', 'get tags for AMI, or set multiple tags as key:value'
    def tags(id, *tags)
      if tags.empty?
        images(id).first.tags.output do |tags|
          print_table tags.map { |t| [t.key, t.value] }
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
      images.select do |image|
        image.name.match(name)
      end.sort_by(&:creation_date).last(options[:count]).map do |image|
        image.image_id
      end.output do |list|
        puts list
      end
    end
  end
end
