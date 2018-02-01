require 'maas/client'
require 'ipaddr'

module Gogetit
  class GogetMAAS
    attr_reader :config, :conn, :domain, :logger

    def initialize(conf, logger)
      @config = conf
      @conn = Maas::Client::MaasClient.new(
          config[:maas][:key],
          config[:maas][:url]
        )
      @logger = logger
    end

    def get_domain
      return @domain if @domain
      logger.info("Calling <#{__method__.to_s}>")
      @domain = conn.request(:get, ['domains'])[0]['name']
    end

    def machine_exists?(name)
      logger.info("Calling <#{__method__.to_s}> for #{name}")
      conn.request(:get, ['machines']).each do |m|
        return true if m['hostname'] == name
      end
      false
    end

    def get_distro_name(system_id)
      logger.info("Calling <#{__method__.to_s}>")
      conn.request(:get, ['machines']).each do |m|
        return m['osystem'] if m['system_id'] == system_id
      end
      false
    end

    def dnsresource_exists?(name)
      logger.info("Calling <#{__method__.to_s}> for #{name}")
      conn.request(:get, ['dnsresources']).each do |item|
        return true if item['fqdn'] == name + '.' + get_domain
      end
      false
    end

    def domain_name_exists?(name)
      logger.info("Calling <#{__method__.to_s}> for #{name}")
      return true if dnsresource_exists?(name) or machine_exists?(name)
    end

    def get_subnets
      logger.info("Calling <#{__method__.to_s}>")
      return conn.request(:get, ['subnets'])
    end

    def ip_reserved?(addresses)
      logger.info("Calling <#{__method__.to_s}>")
      ips = Set.new
      addresses.each do |ip|
        ips.add(IPAddr.new(ip))
      end

      reserved_ips = Set.new
      conn.request(:get, ['ipaddresses']).each do |ip|
        reserved_ips.add(IPAddr.new(ip['ip']))
      end

      rackcontroller_ips = Set.new
      conn.request(:get, ['rackcontrollers']).each do |rctrl|
        rctrl['ip_addresses'].each do |ip|
          rackcontroller_ips.add(IPAddr.new(ip))
        end
      end

      # reserved_ips | rackcontroller_ips
      # Returns a new array by joining ary with other_ary, 
      # excluding any duplicates and preserving the order from the original array.
      if ips.disjoint? reserved_ips | rackcontroller_ips
        subnets = conn.request(:get, ['subnets'])
        ipranges = conn.request(:get, ['ipranges'])

        ifaces = []

        ips.each do |ip|
          available = false
          subnets.each do |subnet|
            if IPAddr.new(subnet['cidr']).include?(ip)
              ipranges.each do |range|
                if range['subnet']['id'] == subnet['id']
                  first = IPAddr.new(range['start_ip']).to_i
                  last = IPAddr.new(range['end_ip']).to_i
                  if (first..last) === ip.to_i
                    logger.info("#{ip} is available.")
                    available = true
                    subnets.delete(subnet)
                    subnet['ip'] = ip.to_s
                    ifaces << subnet
                    break
                  end
                end
              end
            end
            break if available
          end

          if not available
            logger.info("#{ip.to_s} does not belong to any subnet pre-defined.")
            return false
          end
        end

      else
        logger.info("#{(ips & (reserved_ips | rackcontroller_ips)).to_a.join(', ')}\
                    is already reserved.")
        return false
      end

      return ifaces
    end

    def ipaddresses_reserved?(ip)
      logger.info("Calling <#{__method__.to_s}>")
      conn.request(:get, ['ipaddresses']).each do |address|
        if address['ip'] == ip
          logger.info("#{ip} is reserved.")
          return true
        end
      end
      return false
    end

    def ipaddresses(op = nil, params = nil)
      logger.info("Calling <#{__method__.to_s}>")
      case op
      when nil
        conn.request(:get, ['ipaddresses'])
      when 'reserve'
        # params = {
        #   'subnet' => '10.1.2.0/24',
        #   'ip' => '10.1.2.8',
        #   'hostname' => 'hostname',
        #   'mac' => 'blahblah'
        # }
        default_param = { 'op' => op }
        logger.info("#{params['ip']} is being reserved..")
        conn.request(:post, ['ipaddresses'], default_param.merge!(params))
      when 'release'
        # Gogetit.maas.ipaddresses('release', {'ip' => '10.1.2.8'})
        # params = {
        #   'ip' => '10.1.2.8',
        # }
        default_param = { 'op' => op }
        logger.info("#{params['ip']} is being released..")
        conn.request(:post, ['ipaddresses'], default_param.merge!(params))
      end
    end

    def interfaces(url = [], params = {})
      logger.info("Calling <#{__method__.to_s}>")

      url.insert(0, 'nodes')
      url.insert(2, 'interfaces')
      # ['nodes', system_id, 'interfaces']

      case params['op']
      when nil
        conn.request(:get, url)
      when 'create_vlan'
        logger.info("Creating a vlan interface for id: #{params['vlan']}..")
        conn.request(:post, url, params)
      when 'link_subnet'
        logger.info("Linking a subnet for id: #{url[3]}..")
        conn.request(:post, url, params)
      when 'unlink_subnet'
        logger.info("Linking a subnet for id: #{url[3]}..")
        conn.request(:post, url, params)
      end
    end

    def delete_dns_record(name)
      logger.info("Calling <#{__method__.to_s}>")
      conn.request(:get, ['dnsresources']).each do |item|
        if item['fqdn'] == name + '.' + get_domain
          logger.info("#{item['fqdn']} is being deleted..")
          conn.request(:delete, ['dnsresources', item['id']])
        end
      end
    end

    def refresh_pods
      logger.info("Calling <#{__method__.to_s}>")
      pod_id = conn.request(:get, ['pods'])
      pod_id.each do |pod|
        conn.request(:post, ['pods', pod['id']], { 'op' => 'refresh' } )
      end
    end

    def get_system_id(name)
      logger.info("Calling <#{__method__.to_s}>")
      conn.request(:get, ['machines']).each do |m|
        return m['system_id'] if m['hostname'] == name
      end
      nil
    end

    def wait_until_state(system_id, state)
      logger.info("Calling <#{__method__.to_s}> for being #{state}")
      until conn.request(:get, ['machines', system_id])['status_name'] == state
        sleep 3
      end
      logger.info("The status has become '#{state}'.")
    end

    def get_machine_state(system_id)
      logger.info("Calling <#{__method__.to_s}>")
      conn.request(:get, ['machines']).each do |m|
        return m['status_name'] if m['system_id'] == system_id
      end
      false
    end

    def change_hostname(system_id, hostname)
      logger.info("Calling <#{__method__.to_s}>")
      conn.request(:put, ['machines', system_id], { 'hostname' => hostname })
    end

    def get_sshkeys
      logger.info("Calling <#{__method__.to_s}>")
      conn.request(:get, ['account', 'prefs', 'sshkeys'])
    end

    def get_package_repos
      logger.info("Calling <#{__method__.to_s}>")
      conn.request(:get, ['package-repositories'])
    end
  end
end
