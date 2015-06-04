module Awful

  class Ami < Cli

    desc 'ls [PATTERN]', 'list AMIs'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    method_option :owners, aliases: '-o', default: 'self', desc: 'List images with this owner'
    def ls(name = /./)
      fields = options[:long] ?
        ->(i) { [ i.name, i.image_id, i.root_device_type, i.state, i.creation_date, i.tags.map{ |t| "#{t.key}=#{t.value}" }.sort.join(',') ] } :
        ->(i) { [ i.image_id ] }

      ec2.describe_images(owners: options[:owners].split(',')).map(&:images).flatten.select do |image|
        image.name.match(name)
      end.map do |image|
        fields.call(image)
      end.tap do |list|
        print_table list.sort
      end
    end

  end

end
