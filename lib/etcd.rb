require 'json'
require 'etcd'

module Etcd
  class Etcd
    attr_reader :etcd_conn

    include Gogetit::Util

    def initialize(config)
      @etcd_conn = Etcd::Client.connect(uris: config[:etcd_url]).connect
    end

    def env_name
      if etcd_conn.get('env_name') == nil or etcd_conn.get('env_name') == ''
        etcd_conn.set('env_name', recognize_env)
        etcd_conn.get('env_name')
      else
        etcd_conn.get('env_name')
      end
    end

    def import_env
      file = File.read('lib/env/'+env_name+'.json')
      env_data = JSON.parse(file)
      etcd_conn.set('env', env_data.to_json)
    end

    def env
      if ! etcd_conn.get('env')
        import_env
      else
        JSON.parse(etcd_conn.get('env'))
      end
    end
  end
end
