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

  def self.get_provider_of(name)
    if lxd.container_exists?(name)
      logger.info("Calling <#{__method__.to_s}>, It is a LXD container.")
      return 'lxd'
    elsif libvirt.domain_exists?(name)
      logger.info("Calling <#{__method__.to_s}>, It is a KVM domain.")
      return 'libvirt'
    else
      puts "#{name} is not found"
      return nil
    end
  end
end
