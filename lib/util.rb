require 'pry'
require 'net/ssh'
require 'active_support/core_ext/hash'

module Gogetit
  module Util
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

    def upgrade_package(fqdn, user)
      logger.info("Calling <#{__method__.to_s}>..")
      Net::SSH.start(fqdn, user) do |ssh|
        begin
          puts ssh.exec!("sudo apt update")
          puts ssh.exec!("sudo apt full-upgrade -y")
          ssh.exec!("sudo reboot")
        rescue Exception => e
          puts e
        end
      end
    end

    def ping_available?(fqdn)
      `ping -c 1 -W 1 #{fqdn}`
      $?.exitstatus == 0
    end

    def ssh_available?(fqdn, user)
      begin
        Net::SSH.start(fqdn, user).class
      rescue Exception => e
        puts e
      end
    end
  end
end
