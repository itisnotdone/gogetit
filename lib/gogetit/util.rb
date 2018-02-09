require 'mkmf'
require 'net/ssh'
require 'net/http'
require 'active_support/core_ext/hash'
require 'json'
require 'socket'
require 'timeout'

module Gogetit
  module Util
    def run_command(cmd)
      logger.info("Calling <#{__method__.to_s}> to run '#{cmd}'")
      system(cmd)
    end

    def get_provider_of(name, providers)
      logger.info("Calling <#{__method__.to_s}> #{name}")
      if providers[:lxd].container_exists?(name)
        logger.info("It is a LXD container.")
        return 'lxd'
      elsif providers[:libvirt].domain_exists?(name)
        logger.info("It is a KVM domain.")
        return 'libvirt'
      else
        puts "#{name} is not found"
        return nil
      end
    end

    def is_port_open?(ip, port)
      logger.info("Calling <#{__method__.to_s}> to check #{ip}:#{port}")
      begin
        Timeout::timeout(1) do
          begin
            s = TCPSocket.new(ip, port)
            s.close
            return true
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError
            return false
          end
        end
      rescue Timeout::Error
      end

      return false
    end

    def get_http_content(url)
      logger.info("Calling <#{__method__.to_s}> to get #{url}")

      uri = URI.parse(url)

      if is_port_open?(uri.host, uri.port)
        http = Net::HTTP.new(uri.host, uri.port)
        res = http.request_post(uri.path, nil)
        if res.code == "200"
          res.body
        else
          logger.error("Unable to reach the content of #{url}.")
          false
        end
      else
        logger.error("Unable to reach the server: #{uri.host} or port: #{uri.port}.")
        false
      end
    end

    def knife_bootstrap_chef(name, provider, config)
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
          puts 'Bootstrapping with chef-server..'
          logger.info(knife_cmd)
          system(knife_cmd)
        end
      end
    end

    def knife_bootstrap_zero(name, provider, config)
      logger.info("Calling <#{__method__.to_s}>")
      config[:chef][:target_environment] ||= '_default'
      if find_executable 'knife'
        knife_cmd = "knife zero bootstrap #{name} \
        --node-name #{name} \
        --ssh-user ubuntu \
        --sudo \
        --environment #{config[:chef][:target_environment]}".gsub(/ * /, ' ')
        puts 'Bootstrapping with chef-zero..'
        logger.info(knife_cmd)
        system(knife_cmd)
      end
    end

    def knife_remove(name, options)
      logger.info("Calling <#{__method__.to_s}>")
      if find_executable 'knife'
        if options['chef']
          if system('knife ssl check')
            logger.info("With chef-server..")
            puts "Deleting node #{name}.."
            logger.info("knife node delete -y #{name}")
            system("knife node delete -y #{name}")
            puts "Deleting client #{name}.."
            logger.info("knife client delete -y #{name}")
            system("knife client delete -y #{name}")
          else
            abort('knife is not configured properly.')
          end
        elsif options['zero']
          logger.info("With chef-zero..")
          puts "Deleting node #{name}.."
          logger.info("knife node delete -y #{name}")
          system("knife node delete -y #{name}")
          puts "Deleting client #{name}.."
          logger.info("knife client delete -y #{name}")
          system("knife client delete -y #{name}")
        end
      end
    end

    def update_databags(config)
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
            run_command("knife data bag delete -y #{bag}")
          when 'n'
            puts 'Keeping..'
          end
      end

      puts 'Checking databags to create..'
      (databags_to_be - databags_as_is).each do |bag|
        puts "Creating databag '#{bag}'.."
        run_command("knife data bag create #{bag}")
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
                "knife vault update #{bag} #{item} --json #{item_file}"\
                " --search '*:*' -M client"
              )
            else
              run_command(
                "knife vault create #{bag} #{item} --json #{item_file}"\
                " --search '*:*' -M client"
              )
            end
            run_command(
              "knife vault refresh #{bag} #{item} --clean-unknown-clients -M client"
            )
          else
            run_command("knife data bag from file #{bag} #{item_file}")
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

    def wait_until_available(ip_or_fqdn, distro_name)
      logger.info("Calling <#{__method__.to_s}> for network connection..")
      until ping_available?(ip_or_fqdn)
        logger.info("Calling <#{__method__.to_s}> for ping to be ready..")
        sleep 3
      end
      logger.info("#{ip_or_fqdn} is now available to ping..")

      until ssh_available?(ip_or_fqdn, distro_name)
        logger.info("Calling <#{__method__.to_s}> for ssh to be ready..")
        sleep 3
      end
      logger.info("#{ip_or_fqdn} is now available to ssh..")
    end

    def ping_available?(host)
      # host can be both IP and ip_or_fqdn.
      logger.info("Calling <#{__method__.to_s}> for #{host}")
      `ping -c 1 -W 1 #{host}`
      $?.exitstatus == 0
    end

    def ssh_available?(ip_or_fqdn, user)
      logger.info("Calling <#{__method__.to_s}> for #{user}@#{ip_or_fqdn}")
      begin
        Net::SSH.start(
          ip_or_fqdn,
          user,
          :keys_only => true,
          :number_of_password_prompts => 0
        )
      rescue Exception => e
        puts e
        return false
      end
      true
    end

    def check_ip_available(addresses, maas)
      logger.info("Calling <#{__method__.to_s}>")
      # to do a ping test
      addresses.each do |ip|
        abort("#{ip} is already being used.") if ping_available?(ip)
      end
      # to check with MAAS
      ifaces = maas.ip_reserved?(addresses)
      abort("one of #{addresses.join(', ')} is already being used.") \
        unless ifaces
      return ifaces
    end

    def run_through_ssh(host, distro_name, commands)
      logger.info("Calling <#{__method__.to_s}>")
      Net::SSH.start(host, distro_name) do |ssh|
        commands.each do |cmd|
          logger.info("'#{cmd}' is being executed..")
          output = ssh.exec!(cmd)
          puts output if output != ''
        end
      end
    end
  end
end
