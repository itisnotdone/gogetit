require 'hyperkit'
require 'gogetit/util'
require 'yaml'

module Gogetit
  class GogetLXD
    include Gogetit::Util

    attr_reader :config, :logger, :conn, :maas

    def initialize(conf, maas, logger)
      @config = conf
      @conn = Hyperkit::Client.new(
          api_endpoint: config[:lxd][:url],
          verify_ssl: false
        )
      @maas = maas
      @logger = logger
    end

    def list
      logger.info("Calling <#{__method__.to_s}>")
      conn.containers
    end

    def container_exists?(name)
      logger.info("Calling <#{__method__.to_s}>")
      list.each do |c|
        return true if c == name
      end
      false
    end

    def get_state(name)
      conn.container(name)[:status]
    end

    def wait_until_state(name, state)
      logger.info("Calling <#{__method__.to_s}> for being #{state}..")
      until get_state(name) == state
        sleep 3
      end
    end

    def generate_args(args, options)
      logger.info("Calling <#{__method__.to_s}>")
      args[:devices] = {}

      ifaces = check_ip_available(options['ipaddresses'], maas, logger)
      abort("There is no dns server specified for the gateway network.") \
        unless ifaces[0]['dns_servers'][0]
      abort("There is no gateway specified for the gateway network.") \
        unless ifaces[0]['gateway_ip']
      args[:ifaces] = ifaces
      args[:config][:'user.network-config'] = {
        'version' => 1,
        'config' => [
          {
            'type' => 'nameserver',
            'address' => ifaces[0]['dns_servers'][0]
          }
        ]
      }

      ifaces.each_with_index do |iface,index|
        if index == 0
          iface_conf = {
            'type' => 'physical',
            'name' => "eth#{index}",
            'subnets' => [
              {
                'type' => 'static',
                'ipv4' => true,
                'address' => iface['ip'] + '/' + iface['cidr'].split('/')[1],
                'gateway' => iface['gateway_ip'],
                'mtu' => iface['vlan']['mtu'],
                'control' => 'auto'
              }
            ]
          }
        elsif index > 0
          if ifaces[0]['vlan']['name'] != 'untagged'
            iface_conf = {
              'type' => 'physical',
              'name' => "eth#{index}",
              'subnets' => [
                {
                  'type' => 'static',
                  'ipv4' => true,
                  'address' => iface['ip'] + '/' + iface['cidr'].split('/')[1],
                  'mtu' => iface['vlan']['mtu'],
                  'control' => 'auto'
                }
              ]
            }
          elsif ifaces[0]['vlan']['name'] == 'untagged'
            iface_conf = {
              'type' => 'vlan',
              'name' => "eth0.#{iface['vlan']['vid'].to_s}",
              'vlan_id' => iface['vlan']['vid'].to_s,
              'vlan_link' => 'eth0',
              'subnets' => [
                {
                  'type' => 'static',
                  'ipv4' => true,
                  'address' => iface['ip'] + '/' + iface['cidr'].split('/')[1],
                  'mtu' => iface['vlan']['mtu'],
                  'control' => 'auto'
                }
              ]
            }
          end
        end

        args[:config][:'user.network-config']['config'].push(iface_conf)
      end

      args[:config][:"user.network-config"] = \
        YAML.dump(args[:config][:"user.network-config"])[4..-1]

      # To configure devices
      ifaces.each_with_index do |iface,index|
        if index == 0
          if iface['vlan']['name'] == 'untagged' # or vid == 0
            args[:devices][:"eth#{index}"] = {
              mtu: iface['vlan']['mtu'].to_s,   #This must be string
              name: "eth#{index}",
              nictype: 'bridged',
              parent: config[:default][:native_bridge],
              type: 'nic'
            }
          elsif iface['vlan']['name'] != 'untagged' # or vid != 0
            args[:devices][:"eth#{index}"] = {
              mtu: iface['vlan']['mtu'].to_s,   #This must be string
              name: "eth#{index}",
              nictype: 'bridged',
              parent: config[:default][:native_bridge] + "-" + iface['vlan']['vid'].to_s,
              type: 'nic'
            }
          end
        # When ifaces[0]['vlan']['name'] == 'untagged' and index > 0,
        # it does not need to generate more devices 
        # since it will configure the IPs with tagged VLANs.
        elsif ifaces[0]['vlan']['name'] != 'untagged'
          args[:devices][:"eth#{index}"] = {
            mtu: iface['vlan']['mtu'].to_s,   #This must be string
            name: "eth#{index}",
            nictype: 'bridged',
            parent: config[:default][:native_bridge] + "-" + iface['vlan']['vid'].to_s,
            type: 'nic'
          }
        end
      end

      return args
    end

    def generate_common_args
      logger.info("Calling <#{__method__.to_s}>")
      args = {}
      sshkeys = maas.get_sshkeys
      pkg_repos = maas.get_package_repos

      args[:config] = {
        'user.user-data': { 'ssh_authorized_keys' => [] }
      }

      sshkeys.each do |key|
        args[:config][:'user.user-data']['ssh_authorized_keys'].push(key['key'])
      end

      pkg_repos.each do |repo|
        if repo['name'] == 'main_archive'
          args[:config][:'user.user-data']['apt_mirror'] = repo['url']
        end
      end

      args[:config][:"user.user-data"] = \
        YAML.dump(args[:config][:"user.user-data"])[4..-1]
      return args
    end

    def create(name, options = {})
      logger.info("Calling <#{__method__.to_s}>")
      abort("Container or Hostname #{name} already exists!") \
        if container_exists?(name) or maas.domain_name_exists?(name)

      args = generate_common_args

      if options['ipaddresses']
        args = generate_args(args, options)
      elsif options[:vlans]
        #check_vlan_available(options[:vlans])
      else
        abort("native_bridge #{config[:default][:native_bridge]} does not exist.") \
           unless conn.networks.include? config[:default][:native_bridge]

        native_bridge_mtu = nil
        # It assumes you only use one fabric as of now,
        # since there might be more fabrics with each untagged vlans on them,
        # which might make finding exact mtu fail as following process.
        default_fabric = 'fabric-0'

        maas.get_subnets.each do |subnet|
          if subnet['vlan']['name'] == 'untagged' and subnet['vlan']['fabric'] == default_fabric
            native_bridge_mtu = subnet['vlan']['mtu']
            break
          end
        end

        args[:devices] = {}
        args[:devices][:"eth0"] = {
          mtu: native_bridge_mtu.to_s,   #This must be string
          name: 'eth0',
          nictype: 'bridged',
          parent: config[:default][:native_bridge],
          type: 'nic'
        }
      end

      args[:alias] ||= config[:lxd][:default_alias]
      args[:sync] ||= true

      conn.create_container(name, args)
      container = conn.container(name)

      container.devices = args[:devices].merge!(container.devices.to_hash)
      conn.update_container(name, container)
      # Fetch container object again
      container = conn.container(name)

      if options['vlans'] or options['ipaddresses']
        # Generate params to reserve IPs
        args[:ifaces].each_with_index do |iface,index|
          if index == 0
            params = {
              'subnet' => iface['cidr'],
              'ip' => iface['ip'],
              'hostname' => name,
              'mac' => container[:expanded_config][:"volatile.eth#{index}.hwaddr"]
            }
          elsif index > 0
            # if dot, '.', is used as a conjunction instead of '-',
            # it fails ocuring '404 not found'.
            # if under score, '_', is used as a conjunction instead of '-',
            # it breaks MAAS DNS somehow..
            if args[:ifaces][0]['vlan']['name'] == 'untagged'
              params = {
                'subnet' => iface['cidr'],
                'ip' => iface['ip'],
                'hostname' => 'eth0' + '-' + iface['vlan']['vid'].to_s  + '-' + name,
                'mac' => container[:expanded_config][:"volatile.eth0.hwaddr"]
              }
            elsif args[:ifaces][0]['vlan']['name'] != 'untagged'
              params = {
                'subnet' => iface['cidr'],
                'ip' => iface['ip'],
                'hostname' => "eth#{index}" + '-' + name,
                'mac' => container[:expanded_config][:"volatile.eth#{index}.hwaddr"]
              }
            end
          end
          maas.ipaddresses('reserve', params)
        end
      end

      conn.start_container(name, :sync=>"true")

      fqdn = name + '.' + maas.get_domain
      wait_until_available(fqdn, logger)
      logger.info("#{name} has been created.")
      true
    end

    def destroy(name, args = {})
      logger.info("Calling <#{__method__.to_s}>")

      container = conn.container(name)
      args[:sync] ||= true

      if get_state(name) == 'Running'
        conn.stop_container(name, args)
      end

      wait_until_state(name, 'Stopped')
      conn.delete_container(name, args)

      if container[:config][:"user.network-config"]
        net_conf = YAML.load(
          container[:config][:"user.network-config"]
        )['config']
        # To remove DNS configuration
        net_conf.shift

        net_conf.each do |nic|
          if nic['subnets'][0]['type'] == 'static'
            # It assumes we only assign a single subnet on a VLAN.
            # Subnets in a VLAN, VLANs in a Fabric
            ip = nic['subnets'][0]['address'].split('/')[0]

            if maas.ipaddresses_reserved?(ip)
              maas.ipaddresses('release', { 'ip' => ip })
            end
          end
        end
      end

      # When multiple static IPs were reserved, it will not delete anything
      # since they are deleted when releasing the IPs above.
      maas.delete_dns_record(name)
      logger.info("#{name} has been destroyed.")
      true
    end
  end
end
