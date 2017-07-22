require 'hyperkit'
require 'util'

module Gogetit
  class GogetLXD
    include Gogetit::Util

    attr_reader :config, :conn, :maas, :logger

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

    def wait_until_available(fqdn)
      until ping_available?(fqdn)
        logger.info("Calling <#{__method__.to_s}> for ping to be ready..")
        sleep 3
      end
      logger.info("#{fqdn} is now available to ping..")
      until ssh_available?(fqdn, 'ubuntu')
        logger.info("Calling <#{__method__.to_s}> for ssh to be ready..")
        sleep 3
      end
      logger.info("#{fqdn} is now available to ssh..")
    end

    def create(name, args = {})
      logger.info("Calling <#{__method__.to_s}>")
      if container_exists?(name) or maas.domain_name_exists?(name)
        puts "Container #{name} already exists!"
        return false
      end

      args[:alias] ||= config[:lxd][:default_alias]
      args[:profiles] ||= config[:lxd][:profiles]
      args[:sync] ||= true
      conn.create_container(name, args)
      conn.start_container(name, :sync=>"true")

      fqdn = name + '.' + maas.get_domain
      wait_until_available(fqdn)
      logger.info("#{name} has been created.")
      true
    end

    def destroy(name, args = {})
      logger.info("Calling <#{__method__.to_s}>")
      args[:sync] ||= true
      if get_state(name) == 'Running'
        conn.stop_container(name, args)
      end
      wait_until_state(name, 'Stopped')
      conn.delete_container(name, args)
      maas.delete_dns_record(name)
      logger.info("#{name} has been destroyed.")
      true
    end
  end
end
