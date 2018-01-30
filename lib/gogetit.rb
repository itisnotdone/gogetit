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

end
