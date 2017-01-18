module Awful
  module Short
    def eip(*args)
      Awful::Eip.new.invoke(*args)
    end
  end

  class Eip < Cli
    no_commands do

      ## get an EIP by id or public ip
      def find_eip(thing)
        ec2.describe_addresses.addresses.find do |eip|
          (thing == eip.public_ip) || (thing == eip.allocation_id) || (thing == eip.association_id)
        end
      end
    end

    desc 'ls', 'list elastic IPs'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def ls
      ec2.describe_addresses.addresses.output do |eips|
        if options[:long]
          print_table eips.map { |i|
            [i.public_ip, i.allocation_id, i.instance_id, i.private_ip_address, i.domain, i.association_id, i.network_interface_id, i.network_interface_owner_id]
          }.sort
        else
          puts eips.map(&:public_ip).sort
        end
      end
    end

    desc 'allocate', 'acquire an elastic IP'
    method_option :domain, aliases: '-d', type: :string, default: 'vpc', desc: 'domain: vpc or standard (ec2 classic)'
    def allocate
      ec2.allocate_address(domain: options[:domain]).output do |eip|
        puts eip.public_ip
      end
    end

    desc 'release ID', 'release elastic IP back to pool'
    def release(id)
      find_eip(id).tap do |eip|
        unless eip.nil?
          if eip.domain == 'vpc'
            ec2.release_address(allocation_id: eip.allocation_id)
          else
            ec2.release_address(public_ip: eip.public_ip)
          end
        end
      end
    end

    desc 'associate ID INSTANCE', 'associate EIP with an instance'
    def associate(id, instance)
      ec2.associate_address(
        allocation_id: find_eip(id).allocation_id,
        instance_id: instance
      ).association_id.output(&method(:puts))
    end

    desc 'disassociate ID', 'disassociate EIP from current instance association'
    def disassociate(id)
      ec2.disassociate_address(association_id: find_eip(id).association_id)
    end
  end
end