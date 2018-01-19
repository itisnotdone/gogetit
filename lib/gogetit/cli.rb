require 'thor'
require 'gogetit'
require 'gogetit/util'

module Gogetit

  @@result = nil

  def self.set_result(x)
    @@result = x
  end

  def self.get_result
    @@result
  end

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
      :desc => 'An alias name for a lxd image'
    method_option :distro, :aliases => '-d', :type => :string, \
      :desc => 'A distro name with its series for libvirt provider'
    method_option :chef, :aliases => '-c', :type => :boolean, \
      :default => false, :desc => 'Chef awareness'
    method_option :vlans, :aliases => '-v', :type => :array, \
      :desc => 'A list of VLAN IDs to connect to'
    method_option :ipaddresses, :aliases => '-i', :type => :array, \
      :desc => 'A list of static IPs to assign'
    method_option :"no-maas", :type => :boolean, \
      :desc => 'Without MAAS awareness(only for LXD provider)'
    method_option :"file", :aliases => '-f', :type => :string, \
      :desc => 'File location(only for LXD provider)'
    def create(name)
      abort("'vlans' and 'ipaddresses' can not be set together.") \
        if options['vlans'] and options['ipaddresses']

      abort("when 'no-maas', the network configuration have to be set by 'file'.") \
        if options['no-maas'] and (options['vlans'] or options['ipaddresses'])

      abort("'no-maas' and 'file' have to be set together.") \
        if options['no-maas'] ^ !!options['file']

      abort("'distro' has to be set with libvirt provider.") \
        if options['distro'] and options['provider'] == 'lxd'

      abort("'alias' has to be set with lxd provider.") \
        if options['alias'] and options['provider'] == 'libvirt'

      case options['provider']
      when 'lxd'
        result = Gogetit.lxd.create(name, options.to_hash)
        Gogetit.set_result(result)
      when 'libvirt'
        result = Gogetit.libvirt.create(name, options.to_hash)
        Gogetit.set_result(result)
      else
        abort('Invalid argument entered.')
      end

      # post-tasks
      if options['chef']
        knife_bootstrap(name, options[:provider], Gogetit.config, Gogetit.logger)
        update_databags(Gogetit.config, Gogetit.logger)
      end
    end

    desc 'destroy NAME', 'Destroy either a container or KVM instance.'
    method_option :chef, :type => :boolean, :desc => "Enable chef awareness."
    def destroy(name)
      # Let Gogetit recognize the provider.
      provider = Gogetit.get_provider_of(name)
      if provider
        case provider
        when 'lxd'
          result = Gogetit.lxd.destroy(name)
          Gogetit.set_result(result)
        when 'libvirt'
          result = Gogetit.libvirt.destroy(name)
          Gogetit.set_result(result)
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

    desc 'deploy NAME', 'Deploy a node existing in MAAS.'
    method_option :distro, :aliases => '-d', :type => :string, \
      :desc => 'A distro name with its series for libvirt provider'
    method_option :chef, :aliases => '-c', :type => :boolean, \
      :default => false, :desc => 'Chef awareness'
    def deploy(name)
      Gogetit.set_result(Gogetit.libvirt.deploy(name, options.to_hash))

      # post-tasks
      if options['chef']
        knife_bootstrap(name, options[:provider], Gogetit.config, Gogetit.logger)
        update_databags(Gogetit.config, Gogetit.logger)
      end
    end

    desc 'release NAME', 'Release a node in MAAS'
    method_option :chef, :type => :boolean, :desc => "Enable chef awareness."
    def release(name)
      result = Gogetit.libvirt.release(name)
      Gogetit.set_result(result)

      # post-tasks
      if options['chef']
        knife_remove(name, Gogetit.logger) if options[:chef]
        update_databags(Gogetit.config, Gogetit.logger)
      end
    end

    desc 'rebuild NAME', 'Destroy(or release) and create(or deploy)'\
    ' either a container or a node(machine) in MAAS again.'
    method_option :chef, :aliases => '-c', :type => :boolean, \
      :default => false, :desc => 'Chef awareness'
    def rebuild(name)
      # Let Gogetit recognize the provider.
      provider = Gogetit.get_provider_of(name)
      if provider
        case provider
        when 'lxd'
          1.upto(100) { print '_' }; puts
          puts "Destroying #{name}.."
          invoke :destroy, [name]
          alias_name = YAML.load(
            Gogetit.get_result[:info][:config][:"user.user-data"]
          )['source_image_alias']
          1.upto(100) { print '_' }; puts
          puts "Creating #{name}.."
          invoke :create, [name], :alias => alias_name
        when 'libvirt'
          invoke :release, [name]
          distro_name = Gogetit.get_result[:info][:machine]['distro_series']
          invoke :deploy, [name], :distro => distro_name
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
  end
end
