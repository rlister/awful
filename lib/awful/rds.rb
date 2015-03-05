module Awful

  class Rds < Thor
    include Awful

    desc 'ls [NAME]', 'list DB instances matching NAME'
    method_option :long, aliases: '-l', default: false, desc: 'Long listing'
    def ls(name = /./)
      fields = options[:long] ?
        ->(d) { [d.db_instance_identifier, d.availability_zone, d.db_instance_class, d.db_instance_status, d.preferred_maintenance_window, d.storage_type, d.allocated_storage,
                 d.engine, d.engine_version] } :
        ->(d) { [d.db_instance_identifier] }

      rds.describe_db_instances.map(&:db_instances).flatten.select do |db|
        db.db_instance_identifier.match(name)
      end.map do |db|
        fields.call(db)
      end.tap do |list|
        print_table list
      end
    end

    desc 'dump NAME', 'dump DB instance matching NAME'
    def dump(name)
      rds.describe_db_instances.map(&:db_instances).flatten.find do |db|
        db.db_instance_identifier == name
      end.tap do |db|
        puts YAML.dump(stringify_keys(db.to_hash))
      end
    end

    desc 'dns NAME', 'show DNS name and port for DB instance NAME'
    def dns(name)
      rds.describe_db_instances.map(&:db_instances).flatten.find do |db|
        db.db_instance_identifier == name
      end.tap do |db|
        puts "#{db.endpoint.address}:#{db.endpoint.port}"
      end
    end

  end

end
