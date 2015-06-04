module Awful

  class Ami < Cli
    class_option :owners, aliases: '-o', default: 'self', desc: 'List images with this owner'

    no_commands do
      def images(options)
        ec2.describe_images(owners: options[:owners].split(',')).map(&:images).flatten
      end
    end

    desc 'ls [PATTERN]', 'list AMIs'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      fields = options[:long] ?
        ->(i) { [ i.name, i.image_id, i.root_device_type, i.state, i.creation_date, i.tags.map{ |t| "#{t.key}=#{t.value}" }.sort.join(',') ] } :
        ->(i) { [ i.image_id ] }

      images(options).select do |image|
        image.name.match(name)
      end.map do |image|
        fields.call(image)
      end.tap do |list|
        print_table list.sort
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

  end

end
