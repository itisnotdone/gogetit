require 'maas/client'

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
      logger.info("Calling <#{__method__.to_s}>")
      conn.request(:get, ['machines']).each do |m|
        return true if m['hostname'] == name
      end
      false
    end

    def dnsresource_exists?(name)
      logger.info("Calling <#{__method__.to_s}>")
      conn.request(:get, ['dnsresources']).each do |item|
        return true if item['fqdn'] == name + '.' + get_domain
      end
      false
    end

    def domain_name_exists?(name)
      return true if dnsresource_exists?(name) or machine_exists?(name)
    end

    def ipaddresses(op = nil, params = nil)
      case op
      when nil
        conn.request(:get, ['ipaddresses'])
      when 'reserve'
        # sample = {
        #   'subnet' => '10.1.2.0/24',
        #   'ip' => '10.1.2.8',
        #   'hostname' => 'hostname',
        #   'mac' => 'blahblah'
        # }
        default_param = { 'op' => op }
        conn.request(:post, ['ipaddresses'], default_param.merge!(params))
      when 'release'
        # sample = {
        #   'ip' => '10.1.2.8',
        #   'hostname' => 'hostname',
        #   'mac' => 'blahblah'
        # }
        default_param = { 'op' => op }
        conn.request(:post, ['ipaddresses'], default_param.merge!(params))
      end
    end

    def delete_dns_record(name)
      logger.info("Calling <#{__method__.to_s}>")
      id = nil
      conn.request(:get, ['dnsresources']).each do |item|
        if item['fqdn'] == name + '.' + get_domain
          id = item['id']
        end
      end

      if ! id.nil?
        conn.request(:delete, ['dnsresources', id.to_s])
      else
        logger.warn('No such record found.')
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
  end
end
