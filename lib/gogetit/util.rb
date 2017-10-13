require 'mkmf'
require 'net/ssh'
require 'active_support/core_ext/hash'
require 'json'

module Gogetit
  module Util
    def run_command(cmd, logger)
      logger.info("Calling <#{__method__.to_s}> to run #{cmd}")
      system(cmd)
    end

    def knife_bootstrap(name, provider, config, logger)
      logger.info("Calling <#{__method__.to_s}>")
      config[:chef][:target_environment] ||= '_default'
      if find_executable 'knife'
        if system('knife ssl check')
          install_cmd = "curl \
          -l #{config[:chef][:bootstrap][:install_script][provider.to_sym]} \
          | sudo bash -s --"
          knife_cmd = "knife bootstrap -y #{name} \
          --node-name #{name} \
          --ssh-user ubuntu \
          --sudo \
          --environment #{config[:chef][:target_environment]} \
          --bootstrap-install-command \"#{install_cmd}\"".gsub(/ * /, ' ')
          puts 'Bootstrapping..'
          puts knife_cmd
          system(knife_cmd)
        end
      end
    end

    def update_databags(config, logger)
      logger.info("Calling <#{__method__.to_s}>")
      data_bags_dir = "#{config[:chef][:chef_repo_root]}/data_bags"

      puts 'Listing databags..'
      databags_as_is = `knife data bag list`.split
      databags_to_be = Dir.entries(data_bags_dir) - ['.', '..']

      puts 'Checking databags to delete..'
      (databags_as_is - databags_to_be).each do |bag|
        puts "Deleting databag '#{bag}'.."
          answer = ask(
            'Do you really want to delete this?',
            :echo => true,
            :limited_to => ['y', 'n']
          )
          case answer
          when 'y'
            run_command("knife data bag delete -y #{bag}", logger)
          when 'n'
            puts 'Keeping..'
          end
      end

      puts 'Checking databags to create..'
      (databags_to_be - databags_as_is).each do |bag|
        puts "Creating databag '#{bag}'.."
        run_command("knife data bag create #{bag}", logger)
      end

      puts 'Checking items..'
      databags_to_be.each do |bag|
        items_as_is = `knife data bag show #{bag}`.split
        Dir.entries(data_bags_dir+'/'+bag).select do |file|
          /^.*\.json/.match(file)
        end.each do |item|
          item_file = data_bags_dir+'/'+bag+'/'+item
          item = item.gsub('.json', '')
          if JSON.parse(File.read(item_file))['vault']
            if items_as_is.include? item
              run_command(
                "knife vault update #{bag} #{item} --json #{item_file} --search '*:*' -M client",
                logger
              )
            else
              run_command(
                "knife vault create #{bag} #{item} --json #{item_file} --search '*:*' -M client",
                logger
              )
            end
            run_command(
              "knife vault refresh #{bag} #{item} --clean-unknown-clients -M client",
              logger
            )
          else
            run_command("knife data bag from file #{bag} #{item_file}", logger)
          end
        end
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

    def wait_until_available(ip_or_fqdn, logger)
      logger.info("Calling <#{__method__.to_s}>")
      until ping_available?(ip_or_fqdn, logger)
        logger.info("Calling <#{__method__.to_s}> for ping to be ready..")
        sleep 3
      end
      logger.info("#{ip_or_fqdn} is now available to ping..")

      until ssh_available?(ip_or_fqdn, 'ubuntu', logger)
        logger.info("Calling <#{__method__.to_s}> for ssh to be ready..")
        sleep 3
      end
      logger.info("#{ip_or_fqdn} is now available to ssh..")
    end

    def ping_available?(host, logger)
      # host can be both IP and ip_or_fqdn.
      logger.info("Calling <#{__method__.to_s}> for #{host}")
      `ping -c 1 -W 1 #{host}`
      $?.exitstatus == 0
    end

    def ssh_available?(ip_or_fqdn, user, logger)
      logger.info("Calling <#{__method__.to_s}>")
      begin
        Net::SSH.start(ip_or_fqdn, user).class
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
