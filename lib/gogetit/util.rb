require 'mkmf'
require 'net/ssh'
require 'active_support/core_ext/hash'

module Gogetit
  module Util
    def knife_bootstrap(name, type, config, logger)
      logger.info("Calling <#{__method__.to_s}>")
      if find_executable 'knife'
        if system('knife ssl check')
          install_cmd = "curl \
          -l #{config[:chef][:bootstrap][:install_script][type.to_sym]} \
          | sudo bash -s --"
          knife_cmd = "knife bootstrap -y #{name} \
          --node-name #{name} \
          --ssh-user ubuntu \
          --sudo \
          --bootstrap-install-command \"#{install_cmd}\"".gsub(/ * /, ' ')
          puts 'Bootstrapping..'
          puts knife_cmd
          system(knife_cmd)
        end
      end
    end

    def update_vault(config, logger)
      logger.info("Calling <#{__method__.to_s}>")
      # It assumes the data_bags directory is under the root directory of Chef Repo
      data_bags_dir = "#{config[:chef][:chef_repo_root]}/data_bags"
      (Dir.entries("#{data_bags_dir}") - ['.', '..']).each do |bag|
        (Dir.entries("#{data_bags_dir}/#{bag}").select do |f|
            /^((?!keys).)*\.json/.match(f)
          end
        ).each do |item|
          puts 'Refreshing vaults..'
          refresh_cmd = "knife vault refresh #{bag} #{item.gsub('.json', '')} --clean-unknown-clients"
          puts refresh_cmd
          system(refresh_cmd)
        end
        puts 'Updating data bags..'
        update_cmd = "knife data bag from file #{bag} #{data_bags_dir}/#{bag}"
        puts update_cmd
        system(update_cmd)
      end
    end

    def knife_remove(name, logger)
      logger.info("Calling <#{__method__.to_s}>")
      if find_executable 'knife'
        if system('knife ssl check')
          puts "Deleting node #{name}.."
          system("knife node delete -y #{name}")
          puts "Deleting client #{name}.."
          system("knife client delete -y #{name}")
        end
      end
    end

    def recognize_env
      thedir = 'lib/env'
      gateway = get_gateway(4)
      Dir.foreach(thedir) do |item|
        if item.match(/\.json$/)
          env_data = JSON.parse(File.read(thedir+'/'+item))
          if gateway =~ Regexp.new(env_data['regexp_pattern'])
            return env_data['name']
          end
        end
      end
    end

    def get_gateway(version)
      IO.popen("ip -#{version.to_s} route").read.each_line do |route|
        if route.include? 'default'
          route.split[2]
        else
          'There is no get_gateway!'
          nil
        end
      end
    end

    # taken from https://gist.github.com/andrewpcone/11359798
		def symbolize_keys(thing)
		  case thing
		  when Array
		    thing.map{|v| symbolize_keys(v)}
		  when Hash
		    inj = thing.inject({}) {|h, (k,v)| h[k] = symbolize_keys(v); h}
		    inj.symbolize_keys
		  else
		    thing
		  end
		end

    def wait_until_available(fqdn, logger)
      logger.info("Calling <#{__method__.to_s}>")
      until ping_available?(fqdn, logger)
        logger.info("Calling <#{__method__.to_s}> for ping to be ready..")
        sleep 3
      end
      logger.info("#{fqdn} is now available to ping..")

      until ssh_available?(fqdn, 'ubuntu', logger)
        logger.info("Calling <#{__method__.to_s}> for ssh to be ready..")
        sleep 3
      end
      logger.info("#{fqdn} is now available to ssh..")
    end

    def ping_available?(host, logger)
      # host can be both IP and FQDN.
      logger.info("Calling <#{__method__.to_s}> for #{host}")
      `ping -c 1 -W 1 #{host}`
      $?.exitstatus == 0
    end

    def ssh_available?(fqdn, user, logger)
      logger.info("Calling <#{__method__.to_s}>")
      begin
        Net::SSH.start(fqdn, user).class
      rescue Exception => e
        puts e
      end
    end

    def check_ip_available(addresses, maas, logger)
      logger.info("Calling <#{__method__.to_s}>")
      # to do a ping test
      addresses.each do |ip|
        abort("#{ip} is already being used.") if ping_available?(ip, logger)
      end
      # to check with MAAS
      ifaces = maas.ip_reserved?(addresses)
      abort("one of #{addresses.join(', ')} is already being used.") \
        unless ifaces
      return ifaces
    end

    def run_through_ssh(host, commands, logger)
      logger.info("Calling <#{__method__.to_s}>")
      Net::SSH.start(host, 'ubuntu') do |ssh|
        commands.each do |cmd|
          logger.info("'#{cmd}' is being executed..")
          output = ssh.exec!(cmd)
          puts output if output != ''
        end
      end
    end
  end
end
