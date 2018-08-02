require 'gogetit/version'
require 'gogetit/config'
require 'gogetit/maas'
require 'providers/lxd'
require 'providers/libvirt'

module Gogetit

  class << self
    attr_reader :config, :logger, :maas, :lxd, :libvirt
  end

  @config = Gogetit::Config.config
  @logger = Gogetit::Config.logger
  @maas = Gogetit::GogetMAAS.new(config, logger)
  @lxd = Gogetit::GogetLXD.new(config, maas, logger)
  @libvirt = Gogetit::GogetLibvirt.new(config, maas, logger)

  def self.list_all_types
    logger.debug("Calling <#{__method__.to_s}>")

    nodes = []

    # for LXD
    conn = lxd.conn
    config[:lxd][:nodes].each do |node|
      puts "Listing LXC containers on #{node[:url]}..."

      conn.containers.each do |con|
        row = {}
        row[:name] = conn.container(con).to_hash[:name]
        row[:status] = conn.container_state(con).to_hash[:status].upcase
        if conn.container_state(con).to_hash[:network] && \
            conn.container_state(con).to_hash[:network][:eth0] && \
            conn.container_state(con).to_hash[:network][:eth0][:addresses] && \
            conn.container_state(con).to_hash[:network][:eth0][:addresses][0] && \
            conn.container_state(con).to_hash[:network][:eth0][:addresses][0][:address]
          row[:ipv4] = \
            # only print the first IP address on the first interface
            conn.container_state(con).to_hash[:network][:eth0][:addresses][0][:address]
        else
          row[:ipv4] = "NA"
        end
        row[:host] = node[:name]
        row[:type] = 'LXC(LXD)'
        nodes << row
      end
    end

    # for Libvirt(KVM), machines in pods controlled by MAAS
    conn = maas.conn
    begin
      machines = conn.request(:get, ['machines'])
    rescue StandardError => e
      puts e
      abort(
        "This method depends on MAAS with maas-client.\n"\
        "Please check if MAAS or maas-client is configured properly."
      )
    end
    config[:libvirt][:nodes].each do |node|
      puts "Listing KVM instances on #{node[:url]}..."
      machines.each do |machine|
        if machine['pod']['name'] == node[:name]
          row = {}
          row[:name] = machine['hostname']
          row[:status] = machine['status_name']
          if machine['interface_set'][0]['links'][0]['ip_address']
            row[:ipv4] = machine['interface_set'][0]['links'][0]['ip_address']
          else
            row[:ipv4] = 'NA'
          end
          row[:host] = node[:name]
          row[:type] = 'KVM(Libvirt)'
          nodes << row
        end
      end
    end

    puts '-------------------------------------------------------------------------'
    tp nodes, :name, :status, :ipv4, :host, :type
    puts
  end

end
