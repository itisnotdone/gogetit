require 'thor'
require 'gogetit'
require 'gogetit/util'

module Gogetit
  class CLI < Thor
    include Gogetit::Util
    package_name 'Gogetit'

    desc 'list', 'List containers and instances, running currently.'
    def list
      puts "Listing LXD containers on #{Gogetit.config[:lxd][:nodes][0][:url]}.."
      system("lxc list #{Gogetit.config[:lxd][:nodes][0][:name]}:")
      puts ''
      puts "Listing KVM domains on #{Gogetit.config[:libvirt][:nodes][0][:url]}.."
      system("virsh -c #{Gogetit.config[:libvirt][:nodes][0][:url]} list --all")
    end

    desc 'create NAME', 'Create either a container or KVM domain.'
    method_option :provider, :aliases => '-p', :type => :string, \
      :default => 'lxd', :desc => 'A provider such as lxd and libvirt'
    method_option :alias, :aliases => '-a', :type => :string, \
      :default => '', :desc => 'An alias name for a lxd image'
    method_option :chef, :aliases => '-c', :type => :boolean, \
      :default => false, :desc => 'Chef awareness'
    method_option :vlans, :aliases => '-v', :type => :array, \
      :desc => 'A list of VLAN IDs to connect to'
    method_option :ipaddresses, :aliases => '-i', :type => :array, \
      :desc => 'A list of static IPs to assign'
    method_option :"no-maas", :type => :boolean, \
      :desc => 'Without MAAS awareness'
    method_option :"file", :aliases => '-f', :type => :string, \
      :desc => 'File location'
    def create(name)
      abort("'vlans' and 'ipaddresses' can not be set together.") \
        if options['vlans'] and options['ipaddresses']

      abort("when 'no-maas', the network configuration have to be set by 'file'.") \
        if options['no-maas'] and (options['vlans'] or options['ipaddresses'])

      abort("'no-maas' and 'file' have to be set together.") \
        if options['no-maas'] ^ !!options['file']

      case options['provider']
      when 'lxd'
        Gogetit.lxd.create(name, options.to_hash)
      when 'libvirt'
        Gogetit.libvirt.create(name, options.to_hash)
      else
        abort('Invalid argument entered.')
      end

      # post-tasks
      if options['chef']
        knife_bootstrap(name, options[:provider], Gogetit.config, Gogetit.logger)
        update_databags(Gogetit.config, Gogetit.logger)
      end
    end

    desc 'destroy NAME', 'Destroy either a container or KVM domain.'
    method_option :chef, :type => :boolean, :desc => "Enable chef awareness."
    def destroy(name)
      # Let Gogetit recognize the provider.
      provider = Gogetit.get_provider_of(name)
      if provider
        case provider
        when 'lxd'
          Gogetit.lxd.destroy(name)
        when 'libvirt'
          Gogetit.libvirt.destroy(name)
        else
          abort('Invalid argument entered.')
        end
      end
      # post-tasks
      if options['chef']
        knife_remove(name, Gogetit.logger) if options[:chef]
        update_databags(Gogetit.config, Gogetit.logger)
      end
    end

    # This feature is broken and might be deprecated in the future.
    # desc 'rebuild NAME', 'Destroy and create either a container or KVM domain again.'
    # def rebuild(type=nil, name)
    #   invoke :destroy, [name]
    #   invoke :create, [type, name]
    # end
  end
end
