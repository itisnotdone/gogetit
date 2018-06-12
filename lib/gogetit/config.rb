require 'yaml'
require 'logger'
require 'gogetit/util'
require 'gogetit/multilogger'
require 'hashie'

module Gogetit
  module Config
    extend Gogetit::Util
    class << self
      attr_reader :config, :logger
    end

    # TODO: It might be needed to disable one of logging devices according to satiation.
    STDOUT.sync = true
    log_to_stdout = Logger.new(STDOUT)
    # Instantiate main objects
    @logger = Gogetit::MultiLogger.new(:loggers => log_to_stdout)

    @config = {}

    # Define home directory
    user_gogetit_home = Dir.home + '/.gogetit'
    config[:user_gogetit_home] = user_gogetit_home
    if not File.directory?(user_gogetit_home)
      logger.info('Creating home directory..')
      FileUtils.mkdir(user_gogetit_home)
    end

    # TODO: It can be used to provide different behavior according to consumer.
    # Define default consumer
    config[:consumer] = 'gogetit_cli'

    # Define log directory
    log_dir = user_gogetit_home + '/log'
    config[:log_dir] = log_dir
    if not File.directory?(log_dir)
      logger.info('Creating log directory..')
      FileUtils.mkdir(log_dir)
    end

    # Define file log devices
    log_file = File.open(log_dir + '/debug.log', 'a')
    log_file.sync = true
    log_to_file = Logger.new(log_file)
    logger.add_logger(log_to_file)

    # Define logger
    # logger.datetime_format = "%Y-%m-%d %H:%M:%S"
    logger.progname = 'GoGetIt'

    lib_dir = Gem::Specification.find_by_name('gogetit').gem_dir + '/lib'

    config[:lib_dir] = lib_dir
    # Load GoGetIt default configuration
    conf_file = user_gogetit_home + '/gogetit.yml'
    if not File.exists?(conf_file)
      src = File.new(lib_dir + '/sample_conf/gogetit.yml')
      dst = Dir.new(user_gogetit_home)
      logger.info('Copying GoGetIt default configuration..')
      FileUtils.cp(src, dst)
      abort("Please define default configuration for GoGetIt at ~/.gogetit/gogetit.yml.\n"\
      "Or you can run this command below on the previous workstation to copy existing configurations.\n"\
      "scp -r ~/.gogetit ubuntu@#{`hostname -f`.chop!}:~/")
    end
    config.merge!(Hashie.symbolize_keys YAML.load_file(conf_file))

    # to check if lxd is well deployed and configured.
    if Dir.exist?("#{ENV["HOME"]}/.config/lxc")

      if Dir.exist?("#{ENV["HOME"]}/.config/lxc/servercerts")

        certificates = (
          Dir.entries("#{ENV["HOME"]}/.config/lxc/servercerts") - ['.', '..']
        )

        if not certificates.empty?

          config[:lxd][:nodes].each do |node|
            if not certificates.include? "#{node[:name]}.crt"
              puts "Unable to find the certificate for node, #{node[:name]}."
              puts "You might need to run following command to accept the certificate"
              puts "lxc remote add --accept-certificate #{node[:name]}"\
                " #{node[:url]}"
            end
          end

        end

      else
        abort(
          'Please check if remotes are properly registered with their certificates.'
        )
      end

    else
      puts "You might need to run following commands to accept the certificate"
      config[:lxd][:nodes].each do |node|
        puts "lxc remote add --accept-certificate #{node[:name]}"\
          " #{node[:url]}"
      end
      abort('Please check if LXD is installed properly.')
    end

    config[:libvirt][:nodes].each do |node|
      if node[:url].split('//')[0].include? "ssh"
        if not ssh_available?(
          node[:url].split('//')[1].split('/')[0].split('@')[1],
          node[:url].split('//')[1].split('/')[0].split('@')[0]
        )
          puts "Please check the URL or SSH private key."
          puts "OR SCP the previous .ssh folder if you are rebuilding"\
            " your workstation."
          puts "scp -r ~/.ssh ubuntu@#{`hostname -f`.chop!}:~/"
          abort("Unable to make connection with #{node[:url]}.")
        end
      end
    end
  end
end
