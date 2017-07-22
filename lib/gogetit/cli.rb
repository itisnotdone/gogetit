require 'thor'
require 'gogetit'

module Gogetit
  class CLI < Thor
    package_name 'Gogetit'

    desc 'list', 'List containers and instances, running currently.'
    def list
      puts "Listing LXD containers on #{Gogetit.config[:lxd][:url]}.."
      system("lxc list #{Gogetit.config[:lxd][:name]}:")
      puts ''
      puts "Listing KVM domains on #{Gogetit.config[:libvirt][:url]}.."
      system("virsh -c #{Gogetit.config[:libvirt][:url]} list --all")
    end

    desc 'create (TYPE) NAME', 'Create either a container or KVM domain.'
    def create(type=nil, name)
      case type
      when 'lxd', nil
        Gogetit.lxd.create(name)
      when 'libvirt'
        Gogetit.libvirt.create(name)
      else
        puts 'Invalid argument entered'
      end
      Gogetit.config[:default][:user] ||= ENV['USER']
      puts "ssh #{Gogetit.config[:default][:user]}@#{name}"
    end

    desc 'destroy NAME', 'Destroy either a container or KVM domain.'
    def destroy(name)
      type = Gogetit.get_provider_of(name)
      if type
        case type
        when 'lxd', nil
          Gogetit.lxd.destroy(name)
        when 'libvirt'
          Gogetit.libvirt.destroy(name)
        end
      end
    end
  end
end
