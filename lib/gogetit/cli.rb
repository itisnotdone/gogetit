require 'thor'
require 'gogetit'
require 'gogetit/util'

module Gogetit
  class CLI < Thor
    include Gogetit::Util
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
    method_option :chef, :type => :boolean, :desc => "Enable chef awareness."
    def create(type='lxd', name)
      case type
      when 'lxd'
        Gogetit.lxd.create(name)
      when 'libvirt'
        Gogetit.libvirt.create(name)
      else
        abort('Invalid argument entered.')
      end
      # post-tasks
      if options[:chef]
        knife_bootstrap(name, type, Gogetit.config)
        update_vault(Gogetit.config)
      end
      Gogetit.config[:default][:user] ||= ENV['USER']
      puts "ssh #{Gogetit.config[:default][:user]}@#{name}"
    end

    desc 'destroy NAME', 'Destroy either a container or KVM domain.'
    method_option :chef, :type => :boolean, :desc => "Enable chef awareness."
    def destroy(name)
      type = Gogetit.get_provider_of(name)
      if type
        case type
        when 'lxd'
          Gogetit.lxd.destroy(name)
        when 'libvirt'
          Gogetit.libvirt.destroy(name)
        else
          abort('Invalid argument entered.')
        end
      end
      # post-tasks
      if options[:chef]
        knife_remove(name) if options[:chef]
        update_vault(Gogetit.config)
      end
    end

    desc 'rebuild NAME', 'Destroy and create either a container or KVM domain again.'
    def rebuild(type=nil, name)
      invoke :destroy, [name]
      invoke :create, [type, name]
    end
  end
end
