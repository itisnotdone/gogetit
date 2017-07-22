require 'libvirt'
require 'securerandom'
require 'oga'
require 'rexml/document'
require 'util'

module Gogetit
  class GogetLibvirt
    include Gogetit::Util

    attr_reader :config, :conn, :maas, :logger

    def initialize(conf, maas, logger)
      @config = conf
      @conn = Libvirt::open(config[:libvirt][:url])
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

    # subject.create(name: 'test01')
    def create(name, conf_file = nil)
      logger.info("Calling <#{__method__.to_s}>")
      if maas.domain_name_exists?(name) or domain_exists?(name)
        puts "Domain #{name} already exists! Please check both on MAAS and libvirt."
        return false
      end

      conf_file ||= config[:default_provider_conf_file]
      domain = symbolize_keys(YAML.load_file(conf_file))
      domain[:name] = name
      domain[:uuid] = SecureRandom.uuid

      dom = conn.define_domain_xml(define_domain(domain))
      maas.refresh_pods

      system_id = maas.get_system_id(domain[:name])
      maas.wait_until_state(system_id, 'Ready')
      logger.info("Calling to deploy...")
      maas.conn.request(:post, ['machines', system_id], {'op' => 'deploy'})
      maas.wait_until_state(system_id, 'Deployed')
      logger.info("#{domain[:name]} has been created.")
      true
    end

    def destroy(name)
      logger.info("Calling <#{__method__.to_s}>")
      system_id = maas.get_system_id(name)
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
      dom.destroy if dom.active?
      Oga.parse_xml(dom.xml_desc).xpath('domain/devices/disk/source').each do |d|
        pool_path = d.attribute('file').value.split('/')[0..2].join('/')
        pools.each do |p|
          if Oga.parse_xml(p.xml_desc).at_xpath('pool/target/path').inner_text == pool_path
            logger.info("Deleting volume in #{p.name} pool.")
            p.lookup_volume_by_name(d.attribute('file').value.split('/')[3]).delete
          end
        end
      end
      dom.undefine

      maas.refresh_pods
      logger.info("#{name} has been destroyed.")
      true
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

      #print_xml(doc)
      #volumes.each do |v|
      #  print_xml(v)
      #end

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
      volume_doc.at_xpath('volume/capacity').inner_text = domain[:disk][:root][:capacity].to_s

      create_volume(domain[:disk][:root][:pool], Oga::XML::Generator.new(volume_doc).to_xml)
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
