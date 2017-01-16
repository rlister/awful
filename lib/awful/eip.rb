module Awful
  module Short
    def eip(*args)
      Awful::Eip.new.invoke(*args)
    end
  end

  class Eip < Cli
    desc 'ls', 'list elastic IPs'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'long listing'
    def ls
      ec2.describe_addresses.addresses.output do |eips|
        if options[:long]
          print_table eips.map { |i|
            [i.public_ip, i.allocation_id, i.instance_id, i.private_ip_address, i.domain, i.network_interface_id, i.network_interface_owner_id]
          }
        else
          puts eips.map(&:public_ip).sort
        end
      end
    end
  end
end