require 'hyperkit'
require 'gogetit/util'
require 'yaml'
require 'hashie'
require 'table_print'

module Gogetit
  class GogetLXD
    include Gogetit::Util

    attr_reader :config, :logger, :conn, :maas

    def initialize(conf, maas, logger)
      @config = conf
      @conn = Hyperkit::Client.new(
          api_endpoint: config[:lxd][:nodes][0][:url],
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
      logger.info("Calling <#{__method__.to_s}> for #{name}")
      list.each do |c|
        return true if c == name
      end
      false
    end

    def get_state(name)
      logger.info("Calling <#{__method__.to_s}>")
      conn.container(name)[:status]
    end

    def wait_until_state(name, state)
      logger.info("Calling <#{__method__.to_s}> for being #{state}..")
      until get_state(name) == state
        sleep 3
      end
    end

    # to generate 'user.user-data'
    def generate_user_data(args, options)
      logger.info("Calling <#{__method__.to_s}>")

      args[:config] = {}

      if options['no-maas']
        args[:config][:'user.user-data'] = \
          YAML.load_file(options['file'])[:config]['user.user-data']
      else
        sshkeys = maas.get_sshkeys
        pkg_repos = maas.get_package_repos

        args[:config][:'user.user-data'] = { 'ssh_authorized_keys' => [] }

        sshkeys.each do |key|
          args[:config][:'user.user-data']['ssh_authorized_keys'].push(key['key'])
        end

        pkg_repos.each do |repo|
          if repo['name'] == 'main_archive'
            args[:config][:'user.user-data']['apt_mirror'] = repo['url']
          end
        end

        args[:config][:"user.user-data"]['source_image_alias'] = args[:alias]
        args[:config][:"user.user-data"]['maas'] = true
      end

      args[:config][:"user.user-data"]['gogetit'] = true

      # To disable to update apt database on first boot
      # so chef client can keep doing its job.
      args[:config][:'user.user-data']['package_update'] = false
      args[:config][:'user.user-data']['package_upgrade'] = false

      generate_cloud_init_config(config, args)

      args[:config][:"user.user-data"] = \
        "#cloud-config\n" + YAML.dump(args[:config][:"user.user-data"])[4..-1]

      return args
    end

    def generate_cloud_init_config(config, args)
      logger.info("Calling <#{__method__.to_s}>")
      # To add truested root CA certificates
      # https://cloudinit.readthedocs.io/en/latest/topics/examples.html
      # #configure-an-instances-trusted-ca-certificates
      if config[:cloud_init] && config[:cloud_init][:ca_certs]
        args[:config][:'user.user-data']['ca-certs'] = {}
        certs = []

        config[:cloud_init][:ca_certs].each do |ca|
          content = get_http_content(ca)
          certs.push(
            /^-----BEGIN CERTIFICATE-----.*-/m.match(content).to_s
          ) if content
        end

        args[:config][:'user.user-data']['ca-certs'] = { 'trusted' => certs }
      end

      # To get CA public key to be used for SSH authentication
      # https://cloudinit.readthedocs.io/en/latest/topics/examples.html
      # #writing-out-arbitrary-files
      if config[:cloud_init] && config[:cloud_init][:ssh_ca_public_key]
        args[:config][:'user.user-data']['write_files'] = []
        content = get_http_content(config[:cloud_init][:ssh_ca_public_key][:key_url])
        if content
          file = {
            'content'     => content.chop!,
            'path'        => config[:cloud_init][:ssh_ca_public_key][:key_path],
            'owner'       => config[:cloud_init][:ssh_ca_public_key][:owner],
            'permissions' => config[:cloud_init][:ssh_ca_public_key][:permissions]
          }
          args[:config][:'user.user-data']['write_files'].push(file)
          args[:config][:'user.user-data']['bootcmd'] = []
          args[:config][:'user.user-data']['bootcmd'].push(
            "cloud-init-per once ssh-ca-pub-key \
echo \"TrustedUserCAKeys #{file['path']}\" >> /etc/ssh/sshd_config"
          )
        end

        if config[:cloud_init][:ssh_ca_public_key][:revocation_url]
          content = get_http_content(config[:cloud_init][:ssh_ca_public_key][:revocation_url])
          if content
            args[:config][:'user.user-data']['bootcmd'].push(
              "cloud-init-per once download-key-revocation-list \
curl -o #{config[:cloud_init][:ssh_ca_public_key][:revocation_path]} \
#{config[:cloud_init][:ssh_ca_public_key][:revocation_url]}"
            )
            args[:config][:'user.user-data']['bootcmd'].push(
              "cloud-init-per once ssh-user-key-revocation-list \
echo \"RevokedKeys #{config[:cloud_init][:ssh_ca_public_key][:revocation_path]}\" \
>> /etc/ssh/sshd_config"
            )
          end
        end
      end

      # To add users
      # https://cloudinit.readthedocs.io/en/latest/topics/examples.html
      # #including-users-and-groups
      if config[:cloud_init] && config[:cloud_init][:users]
        args[:config][:'user.user-data']['users'] = []
        args[:config][:'user.user-data']['users'].push('default')

        config[:cloud_init][:users].each do |user|
          args[:config][:'user.user-data']['users'].push(Hashie.stringify_keys user)
        end
      end

      return args
    end

    def generate_network_config(args, options)
      logger.info("Calling <#{__method__.to_s}>")
      if options['no-maas']
        args[:config][:'user.network-config'] = \
          YAML.load_file(options['file'])[:config][:'user.network-config']

        options['ip_to_access'] = \
          args[:config][:"user.network-config"]['config'][1]['subnets'][0]['address']
          .split('/')[0]
        args[:config][:"user.network-config"] = \
          YAML.dump(args[:config][:"user.network-config"])[4..-1]

      elsif options['ipaddresses']
        options[:ifaces] = check_ip_available(options['ipaddresses'], maas)
        abort("There is no dns server specified for the gateway network.") \
          unless options[:ifaces][0]['dns_servers'][0]
        abort("There is no gateway specified for the gateway network.") \
          unless options[:ifaces][0]['gateway_ip']

        args[:config][:'user.network-config'] = {
          'version' => 1,
          'config' => [
            {
              'type' => 'nameserver',
              'address' => options[:ifaces][0]['dns_servers'][0]
            }
          ]
        }

        # to generate configuration for [:config][:'user.network-config']['config']
        options[:ifaces].each_with_index do |iface,index|
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
            if options[:ifaces][0]['vlan']['name'] != 'untagged'
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
            elsif options[:ifaces][0]['vlan']['name'] == 'untagged'
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
      end

      return args
    end

    # To configure devices
    def generate_devices(args, options)
      logger.info("Calling <#{__method__.to_s}>")
      args[:devices] = {}

      if options['no-maas']
        args[:devices] = \
          YAML.load_file(options['file'])[:devices]

      elsif options['ipaddresses']
        options[:ifaces].each_with_index do |iface,index|
          if index == 0
            if iface['vlan']['name'] == 'untagged' # or vid == 0
              args[:devices][:"eth#{index}"] = {
                mtu: iface['vlan']['mtu'].to_s,   #This must be string
                name: "eth#{index}",
                nictype: 'bridged',
                parent: config[:default][:root_bridge],
                type: 'nic'
              }
            elsif iface['vlan']['name'] != 'untagged' # or vid != 0
              args[:devices][:"eth#{index}"] = {
                mtu: iface['vlan']['mtu'].to_s,   #This must be string
                name: "eth#{index}",
                nictype: 'bridged',
                parent: config[:default][:root_bridge] + "-" + iface['vlan']['vid'].to_s,
                type: 'nic'
              }
            end
          # When options[:ifaces][0]['vlan']['name'] == 'untagged' and index > 0,
          # it does not need to generate more devices 
          # since it will configure the IPs with tagged VLANs.
          elsif options[:ifaces][0]['vlan']['name'] != 'untagged'
            args[:devices][:"eth#{index}"] = {
              mtu: iface['vlan']['mtu'].to_s,   #This must be string
              name: "eth#{index}",
              nictype: 'bridged',
              parent: config[:default][:root_bridge] + "-" + iface['vlan']['vid'].to_s,
              type: 'nic'
            }
          end
        end
      else
        abort("root_bridge #{config[:default][:root_bridge]} does not exist.") \
           unless conn.networks.include? config[:default][:root_bridge]

        root_bridge_mtu = nil
        # It assumes you only use one fabric as of now,
        # since there might be more fabrics with each untagged vlans on them,
        # which might make finding exact mtu fail as following process.
        default_fabric = 'fabric-0'

        maas.get_subnets.each do |subnet|
          if subnet['vlan']['name'] == 'untagged' and \
              subnet['vlan']['fabric'] == default_fabric
            root_bridge_mtu = subnet['vlan']['mtu']
            break
          end
        end

        args[:devices] = {}
        args[:devices][:"eth0"] = {
          mtu: root_bridge_mtu.to_s,   #This must be string
          name: 'eth0',
          nictype: 'bridged',
          parent: config[:default][:root_bridge],
          type: 'nic'
        }
      end

      return args
    end

    def reserve_ips(name, options, container)
      logger.info("Calling <#{__method__.to_s}>")
      # Generate params to reserve IPs
      options[:ifaces].each_with_index do |iface,index|
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
          if options[:ifaces][0]['vlan']['name'] == 'untagged'
            params = {
              'subnet' => iface['cidr'],
              'ip' => iface['ip'],
              'hostname' => 'eth0' + '-' + iface['vlan']['vid'].to_s  + '-' + name,
              'mac' => container[:expanded_config][:"volatile.eth0.hwaddr"]
            }
          elsif options[:ifaces][0]['vlan']['name'] != 'untagged'
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

    def create(name, options = {})
      logger.info("Calling <#{__method__.to_s}>")

      abort("Container #{name} already exists!") \
        if container_exists?(name)

      abort("Domain #{name}.#{maas.get_domain} already exists!") \
        if maas.domain_name_exists?(name) unless options['no-maas']

      args = {}

      if options['alias'].nil? or options['alias'].empty?
        args[:alias] = config[:lxd][:default_alias]
      else
        args[:alias] = options['alias']
      end

      args = generate_user_data(args, options)
      args = generate_network_config(args, options)
      args = generate_devices(args, options)

      args[:sync] ||= true

      conn.create_container(name, args)
      container = conn.container(name)

      container.devices = args[:devices].merge!(container.devices.to_hash)
      conn.update_container(name, container)
      # Fetch container object again
      container = conn.container(name)

      reserve_ips(name, options, container) \
        if options['vlans'] or options['ipaddresses'] \
          unless options['no-maas']

      conn.start_container(name, :sync=>"true")

      if options['no-maas']
        ip_or_fqdn = options['ip_to_access']
      else
        ip_or_fqdn = name + '.' + maas.get_domain
      end

      if conn.execute_command(name, "ls /etc/lsb-release")[:metadata][:return] == 0
        default_user = 'ubuntu'
      elsif conn.execute_command(name, "ls /etc/redhat-release")[:metadata][:return] == 0
        default_user = 'centos'
      else
        default_user = config[:default][:user]
      end

      args[:default_user] = default_user

      wait_until_available(ip_or_fqdn, default_user)
      logger.info("#{name} has been created.")

      if options['no-maas']
        puts "ssh #{default_user}@#{options['ip_to_access']}"
      else
        puts "ssh #{default_user}@#{name}"
      end

      { result: true, info: args }
    end

    def destroy(name, args = {})
      logger.info("Calling <#{__method__.to_s}>")

      container = conn.container(name)
      args[:sync] ||= true

      info = container.to_hash

      if get_state(name) == 'Running'
        conn.stop_container(name, args)
      end

      wait_until_state(name, 'Stopped')

      if YAML.load(container[:config][:"user.user-data"])['maas']
        logger.info("This is a MAAS enabled container.")
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

        maas.delete_dns_record(name)
      end

      conn.delete_container(name, args)

      # When multiple static IPs were reserved, it will not delete anything
      # since they are deleted when releasing the IPs above.
      logger.info("#{name} has been destroyed.")

      { result: true, info: info }
    end
  end
end
