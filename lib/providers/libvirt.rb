require 'libvirt'
require 'securerandom'
require 'oga'
require 'rexml/document'
require 'gogetit/util'

module Gogetit
  class GogetLibvirt
    include Gogetit::Util

    attr_reader :config, :logger, :conn, :maas

    def initialize(conf, maas, logger)
      @config = conf
      @conn = Libvirt::open(config[:libvirt][:nodes][0][:url])
      @maas = maas
      @logger = logger
    end

    def get_domain_list
      logger.info("Calling <#{__method__.to_s}>")
      domains = []
      conn.list_all_domains.each do |d|
        domains << d.name
      end
      domains
    end

    def domain_exists?(name)
      logger.info("Calling <#{__method__.to_s}>")
      get_domain_list.each do |d|
        return true if d == name
      end
      false
    end

    def get_mac_addr(domain_name)
      logger.info("Calling <#{__method__.to_s}>")
       Oga.parse_xml(conn.lookup_domain_by_name(domain_name).xml_desc)
        .at_xpath('domain/devices/interface[1]/mac')
        .attribute('address')
        .value
    end

    def get_domain_xml(domain_name)
      logger.info("Calling <#{__method__.to_s}>")
       Oga.parse_xml(conn.lookup_domain_by_name(domain_name).xml_desc)
    end

    def generate_nics(ifaces, domain)
      abort("There is no dns server specified for the gateway network.") \
        unless ifaces[0]['dns_servers'][0]
      abort("There is no gateway specified for the gateway network.") \
        unless ifaces[0]['gateway_ip']

      # It seems the first IP has to belong to the untagged VLAN in the Fabric.
      abort("The first IP you entered does not belong to the untagged"\
      " VLAN in the Fabric.") \
        unless ifaces[0]['vlan']['name'] == 'untagged'

      domain[:ifaces] = ifaces
      domain[:nic] = []

      ifaces.each_with_index do |iface,index|
        if index == 0
          if iface['vlan']['name'] == 'untagged'
            nic = {
              network: config[:default][:root_bridge],
              portgroup: config[:default][:root_bridge]
            }
          elsif iface['vlan']['name'] != 'untagged'
            nic = {
              network: config[:default][:root_bridge],
              portgroup: config[:default][:root_bridge] + '-' + \
              iface['vlan']['vid'].to_s
            }
          end
          domain[:nic].push(nic)
        elsif index > 0
          # Only if the fisrt interface has untagged VLAN,
          # it will be configured with VLANs.
          # This will not be hit as of now and might be deprecated.
          if ifaces[0]['vlan']['name'] != 'untagged'
            nic = {
              network: config[:default][:root_bridge],
              portgroup: config[:default][:root_bridge] + '-' + \
              iface['vlan']['vid'].to_s
            }
            domain[:nic].push(nic)
          end
        end
      end
      return domain
    end

    def configure_interfaces(ifaces, system_id)

      # It assumes you only have a physical interfaces.
      interfaces = maas.interfaces([system_id])

      maas.interfaces(
        [system_id, interfaces[0]['id']],
        {
          'op' => 'unlink_subnet',
          'id' => interfaces[0]['links'][0]['id']
        }
      )

      # VLAN configuration
      ifaces.each_with_index do |iface,index|
        if index == 0
          params = {
            'op' => 'link_subnet',
            'mode' => 'STATIC',
            'subnet' => ifaces[0]['id'],
            'ip_address' => ifaces[0]['ip'],
            'default_gateway' => 'True',
            'force' => 'False'
          }
          maas.interfaces([system_id, interfaces[0]['id']], params)

        elsif index > 0
          params = {
            'op' => 'create_vlan',
            'vlan' => iface['vlan']['id'],
            'parent' => interfaces[0]['id']
          }
          maas.interfaces([system_id], params)

          interfaces = maas.interfaces([system_id])

          params = {
            'op' => 'link_subnet',
            'mode' => 'STATIC',
            'subnet' => ifaces[index]['id'],
            'ip_address' => ifaces[index]['ip'],
            'default_gateway' => 'False',
            'force' => 'False'
          }

          maas.interfaces([system_id, interfaces[index]['id']], params)
        end
      end
    end

    def create(name, options = nil)
      logger.info("Calling <#{__method__.to_s}>")
      abort("Domain #{name} already exists!"\
      " Please check both on MAAS and libvirt.") \
        if maas.domain_name_exists?(name) or domain_exists?(name)

      domain = config[:libvirt][:specs][:default]
      ifaces = nil

      if options['ipaddresses']
        ifaces = check_ip_available(options['ipaddresses'], maas, logger)
        domain = generate_nics(ifaces, domain)
      elsif options['vlans']
        #check_vlan_available(options['vlans'])
      else
        domain[:nic] = [
          {
            network: config[:default][:root_bridge],
            portgroup: config[:default][:root_bridge]
          }
        ]
      end

      domain[:name] = name
      domain[:uuid] = SecureRandom.uuid

      dom = conn.define_domain_xml(define_domain(domain))
      maas.refresh_pods

      system_id = maas.get_system_id(domain[:name])
      maas.wait_until_state(system_id, 'Ready')

      if options['ipaddresses']
        configure_interfaces(ifaces, system_id)
      elsif options['vlans']
        #check_vlan_available(options['vlans'])
      else
      end

      logger.info("Calling to deploy...")

      distro = nil
      if options['distro'].nil? or options['distro'].empty?
        distro = 'xenial'
      else
        distro = options['distro']
      end

      maas.conn.request(:post, ['machines', system_id], \
                        {'op' => 'deploy', 'distro_series' => distro})
      maas.wait_until_state(system_id, 'Deployed')

      fqdn = name + '.' + maas.get_domain
      distro_name = maas.get_distro_name(system_id)
      wait_until_available(fqdn, distro_name, logger)

      # To enable serial console to use 'virsh console'
      if distro_name == 'ubuntu'
        commands = [
          'sudo systemctl enable serial-getty@ttyS0.service',
          'sudo systemctl start serial-getty@ttyS0.service'
        ]
        run_through_ssh(fqdn, distro_name, commands, logger)
      end

      logger.info("#{domain[:name]} has been created.")
      puts "ssh #{distro_name}@#{name}"

      domain[:default_user] = distro_name

      { result: true, info: domain }
    end

    def destroy(name)
      logger.info("Calling <#{__method__.to_s}>")

      system_id = maas.get_system_id(name)

      info = {}
      info[:machine] = \
        maas.conn.request(:get, ['machines', system_id])

      if maas.machine_exists?(name)
        if maas.get_machine_state(system_id) == 'Deployed'
          logger.info("Calling to release...")
          maas.conn.request(:post, ['machines', system_id], {'op' => 'release'})
          maas.wait_until_state(system_id, 'Ready')
        end
        maas.conn.request(:delete, ['machines', system_id])
      end

      pools = []
      conn.list_storage_pools.each do |name|
        pools << self.conn.lookup_storage_pool_by_name(name)
      end

      dom = conn.lookup_domain_by_name(name)
      info[:domain_xml] = dom.xml_desc

      dom.destroy if dom.active?
      Oga.parse_xml(dom.xml_desc).xpath('domain/devices/disk/source').each do |d|
        pool_path = d.attribute('file').value.split('/')[0..2].join('/')
        pools.each do |p|
          if Oga.parse_xml(p.xml_desc).at_xpath('pool/target/path')\
            .inner_text == pool_path
            logger.info("Deleting volume in #{p.name} pool.")
            p.lookup_volume_by_name(d.attribute('file').value.split('/')[3]).delete
          end
        end
      end
      dom.undefine

      logger.info("#{name} has been destroyed.")

      { result: true, info: info }
    end

    def deploy(name, options = nil)
      logger.info("Calling <#{__method__.to_s}>")
      abort("The machine, '#{name}', doesn't exist.") \
        unless maas.machine_exists?(name)

      system_id = maas.get_system_id(name)
      maas.wait_until_state(system_id, 'Ready')

      logger.info("Calling to deploy...")

      distro = nil
      if options['distro'].nil? or options['distro'].empty?
        distro = 'xenial'
      else
        distro = options['distro']
      end

      maas.conn.request(:post, ['machines', system_id], \
                        {'op' => 'deploy', 'distro_series' => distro})
      maas.wait_until_state(system_id, 'Deployed')

      fqdn = name + '.' + maas.get_domain
      distro_name = maas.get_distro_name(system_id)
      wait_until_available(fqdn, distro_name, logger)

      # To enable serial console to use 'virsh console'
      if distro_name == 'ubuntu'
        commands = [
          'sudo systemctl enable serial-getty@ttyS0.service',
          'sudo systemctl start serial-getty@ttyS0.service'
        ]
        run_through_ssh(fqdn, distro_name, commands, logger)
      end

      logger.info("#{name} has been created.")
      puts "ssh #{distro_name}@#{name}"

      distro[:default_user] = distro_name

      { result: true, info: distro }
    end

    def release(name)
      logger.info("Calling <#{__method__.to_s}>")

      system_id = maas.get_system_id(name)

      info = {}
      info[:machine] = \
        maas.conn.request(:get, ['machines', system_id])

      if maas.machine_exists?(name)
        if maas.get_machine_state(system_id) == 'Deployed'
          logger.info("Calling to release...")
          maas.conn.request(:post, ['machines', system_id], {'op' => 'release'})
          maas.wait_until_state(system_id, 'Ready')
        end
      end

      logger.info("#{name} has been released.")

      { result: true, info: info }
    end

    def define_domain(domain)
      logger.info("Calling <#{__method__.to_s}>")
      template = File.read(config[:lib_dir] + '/template/domain.xml')
      doc = Oga.parse_xml(template)

      name = domain[:name]
      doc.at_xpath('domain/name').inner_text = name
      uuid = domain[:uuid]
      doc.at_xpath('domain/uuid').inner_text = uuid
      vcpu = domain[:vcpu].to_s
      doc.at_xpath('domain/vcpu').inner_text = vcpu
      memory = domain[:memory].to_s
      doc.at_xpath('domain/memory').inner_text = memory
      doc.at_xpath('domain/currentMemory').inner_text = memory

      doc = define_volumes(doc, domain)
      doc = add_nic(doc, domain[:nic])

      # print_xml(doc)
      # volumes.each do |v|
      #   print_xml(v)
      # end

      return Oga::XML::Generator.new(doc).to_xml
    end

    def print_xml(doc)
      logger.info("Calling <#{__method__.to_s}>")
      output = REXML::Document.new(Oga::XML::Generator.new(doc).to_xml)
      formatter = REXML::Formatters::Pretty.new
      formatter.compact = true
      formatter.write(output, $stdout)
    end

    def get_pool_path(pool)
      logger.info("Calling <#{__method__.to_s}>")
      path = nil
      conn.list_all_storage_pools.each do |p|
        if p.name == pool
          pool_doc = Oga.parse_xml(p.xml_desc)
          path = pool_doc.at_xpath('pool/target/path').inner_text
        end
      end

      if path
        return path
      else
        raise 'No such pool found.'
      end
    end

    def define_volumes(document, domain)
      logger.info("Calling <#{__method__.to_s}>")
      disk_template = File.read(config[:lib_dir] + '/template/disk.xml')
      disk_doc = Oga.parse_xml(disk_template)
      volume_template = File.read(config[:lib_dir] + '/template/volume.xml')
      volume_doc = Oga.parse_xml(volume_template)

      defined_volumes = []

      # For root volume
      pool_path = get_pool_path(domain[:disk][:root][:pool])
      volume_name = "#{domain[:name]}_root_sda.qcow2"
      volume_file = pool_path + "/" + volume_name
      disk_doc.at_xpath('disk/source').attribute('file').value = volume_file
      document.at_xpath('domain/devices').children << disk_doc.at_xpath('disk')

      volume_doc.at_xpath('volume/name').inner_text = volume_name
      volume_doc.at_xpath('volume/target/path').inner_text = volume_file
      volume_doc.at_xpath('volume/capacity').inner_text = \
        domain[:disk][:root][:capacity].to_s

      create_volume(domain[:disk][:root][:pool], \
                    Oga::XML::Generator.new(volume_doc).to_xml)
      defined_volumes << volume_doc

      # For data(secondary) volumes
      if domain[:disk][:data] != [] and domain[:disk][:data] != nil
        disk_index = 98
        domain[:disk][:data].each do |v|
          pool_path = get_pool_path(v[:pool])
          volume_index = "sd" + disk_index.chr
          volume_name = "#{domain[:name]}_data_#{volume_index}.qcow2"
          volume_file = pool_path + "/" + volume_name
          disk_doc = Oga.parse_xml(disk_template)
          disk_doc.at_xpath('disk/source').attribute('file').value = volume_file
          disk_doc.at_xpath('disk/target').attribute('dev').value = volume_index
          document.at_xpath('domain/devices').children << disk_doc.at_xpath('disk')

          volume_doc = Oga.parse_xml(volume_template)
          volume_doc.at_xpath('volume/name').inner_text = volume_name
          volume_doc.at_xpath('volume/target/path').inner_text = volume_file
          volume_doc.at_xpath('volume/capacity').inner_text = v[:capacity].to_s
          create_volume(v[:pool], Oga::XML::Generator.new(volume_doc).to_xml)
          defined_volumes << volume_doc
          disk_index += 1
        end
      end

      return document
    end

    def create_volume(pool_name, volume_doc)
      logger.info("Calling <#{__method__.to_s}> to create volume in #{pool_name} pool.")
      pool = conn.lookup_storage_pool_by_name(pool_name)
      pool.create_volume_xml(volume_doc)
      pool.refresh
    end

    def add_nic(document, nic_conf)
      logger.info("Calling <#{__method__.to_s}>")
      template = File.read(config[:lib_dir] + "/template/nic.xml")
      doc = Oga.parse_xml(template)

      nic_conf.each do |nic|
        doc = Oga.parse_xml(template)
        doc.at_xpath('interface/source').attribute('network').value = nic[:network]
        doc.at_xpath('interface/source').attribute('portgroup').value = nic[:portgroup]
        document.at_xpath('domain/devices').children << doc.at_xpath('interface')
      end

      document
    end

    #def generate_xml
    #  domain = Oga::XML::Element.new(name: 'domain')
    #  domain.add_attribute(Oga::XML::Attribute.new(name: "type", value: "kvm"))
    #  name = Oga::XML::Element.new(name: 'name')
    #  name.inner_text = 'ceph'
    #  domain.children << name
    #  doc = REXML::Document.new(Oga::XML::Generator.new(domain).to_xml)
    #  formatter = REXML::Formatters::Pretty.new
    #  formatter.compact = true
    #  formatter.write(doc, $stdout)

    #  disk = create_element(name: 'domain')
    #  disk.add_attribute(Oga::XML::Attribute.new(name: "type", value: "file"))
    #  disk.add_attribute(Oga::XML::Attribute.new(name: "device", value: "disk"))
    #  driver = create_element(name: 'domain')
    #  driver.add_attribute(Oga::XML::Attribute.new(name: "name", value: "qemu"))
    #  driver.add_attribute(Oga::XML::Attribute.new(name: "type", value: "qcow2"))
    #  source = create_element(name: 'source')
    #  source.add_attribute(Oga::XML::Attribute.new(name: "file", value: file))
    #  target = create_element(name: 'target')
    #  target.add_attribute(Oga::XML::Attribute.new(name: "dev", value: seq_name))
    #  target.add_attribute(Oga::XML::Attribute.new(name: "bus", value: "scsi"))

    #end

    #def create_element(name)
    #  Oga::XML::Element.new(name: name)
    #end

    #def add_attribute(element, hash)
    #  element.add_attribute(Oga::XML::Attribute.new(hash))
    #end
  end
end
