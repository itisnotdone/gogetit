require 'yaml'
require 'logger'
require 'gogetit/util'
require 'gogetit/multilogger'

module Gogetit
  module Config
    extend Gogetit::Util
    class << self
      attr_reader :config, :logger
    end

    # TODO: It might be needed to disable one of logging devices according to satiation.
    STDOUT.sync = true
    log_to_stdout = Logger.new(STDOUT)
    @logger = Gogetit::MultiLogger.new(:loggers => log_to_stdout)
    logger.debug('Instantiate main objects..')

    @config = {}

    logger.debug('Defining home directory..')
    user_gogetit_home = Dir.home + '/.gogetit'
    config[:user_gogetit_home] = user_gogetit_home
    if not File.directory?(user_gogetit_home)
      logger.debug('Creating home directory..')
      FileUtils.mkdir(user_gogetit_home)
    end

    # TODO: It can be used to provide different behavior according to consumer.
    logger.debug('Defining default consumer..')
    config[:consumer] = 'gogetit_cli'

    logger.debug('Defining log directory..')
    log_dir = user_gogetit_home + '/log'
    config[:log_dir] = log_dir
    if not File.directory?(log_dir)
      logger.debug('Creating log directory..')
      FileUtils.mkdir(log_dir)
    end

    logger.debug('Define file log devices..')
    log_file = File.open(log_dir + '/debug.log', 'a')
    log_file.sync = true
    log_to_file = Logger.new(log_file)
    logger.add_logger(log_to_file)

    logger.debug('Defining logger..')
    # logger.datetime_format = "%Y-%m-%d %H:%M:%S"
    logger.progname = 'GoGetIt'

    lib_dir = Gem::Specification.find_by_name('gogetit').gem_dir + '/lib'

    config[:lib_dir] = lib_dir
    logger.debug('Loading GoGetIt default configuration..')
    conf_file = user_gogetit_home + '/gogetit.yml'
    if not File.exists?(conf_file)
      src = File.new(lib_dir + '/sample_conf/gogetit.yml')
      dst = Dir.new(user_gogetit_home)
      logger.debug('Copying GoGetIt default configuration..')
      FileUtils.cp(src, dst)
      abort('Please define default configuration for GoGetIt at ~/.gogetit/gogetit.yml.')
    end
    config.merge!(symbolize_keys(YAML.load_file(conf_file)))

    logger.debug('Define provider configuration directory..')
    provider_conf_dir = user_gogetit_home + '/conf'
    config[:provider_conf_dir] = provider_conf_dir
    default_provider_conf_file = provider_conf_dir + '/default.yml'
    config[:default_provider_conf_file] = default_provider_conf_file
    if not File.exists?(default_provider_conf_file)
      if not File.directory?(provider_conf_dir)
        logger.debug('Creating provider configuration directory..')
        FileUtils.mkdir(provider_conf_dir)
      end
      src = File.new(lib_dir + '/sample_conf/default.yml')
      dst = Dir.new(provider_conf_dir)
      logger.debug('Copying provider configuration file..')
      FileUtils.cp(src, dst)
      abort('Please define default configuration for providers at ~/.gogetit/conf/default.yml.')
    end

  end
end
