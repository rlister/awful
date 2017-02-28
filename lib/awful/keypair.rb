module Awful
  module Short
    def keypair(*args)
      Awful::Keypair.new.invoke(*args)
    end
  end

  class Keypair < Cli
    desc 'ls [NAMES]', 'describe key pairs'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def ls(*names)
      names = nil if names.empty?
      ec2.describe_key_pairs(key_names: names).key_pairs.output do |kp|
        if options[:long]
          print_table kp.map{ |k| [k.key_name, k.key_fingerprint] }
        else
          puts kp.map(&:key_name)
        end
      end
    end

    desc 'create NAME', 'create key pair'
    def create(name)
      ec2.create_key_pair(key_name: name.to_s).output do |k|
        puts k.key_material
      end
    end

    desc 'import NAME', 'import public key for your own key pair from stdin or file'
    method_option :file, aliases: '-f', type: :string, default: nil, desc: 'file to load public key'
    def import(name)
      key = file_or_stdin(options[:file])
      ec2.import_key_pair(key_name: name, public_key_material: key)
    end

    desc 'delete NAME', 'delete key pair'
    def delete(name)
      if yes?("Really delete key pair #{name}?", :yellow)
        ec2.delete_key_pair(key_name: name)
      end
    end

  end
end