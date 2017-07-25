require 'mkmf'
require 'net/ssh'
require 'active_support/core_ext/hash'

module Gogetit
  module Util
    def knife_bootstrap(name, type, config)
      if find_executable 'knife'
        if system('knife ssl check')
          install_cmd = "curl \
          -l #{config[:chef][:bootstrap][:install_script][type.to_sym]} \
          | sudo bash -s --"
          knife_cmd = "knife bootstrap -y #{name} \
          --node-name #{name} \
          --ssh-user ubuntu \
          --sudo \
          --bootstrap-install-command \"#{install_cmd}\""
          system(knife_cmd)
        end
      end
    end

    def knife_remove(name)
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
