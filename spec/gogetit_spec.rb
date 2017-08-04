require 'spec_helper'
require 'gogetit'
require 'gogetit/version'

RSpec.describe Gogetit do

  name = 'rspec-test'

  it 'has a version number' do
    expect(Gogetit::VERSION).not_to be nil
  end

  context 'LXD' do
    it 'can create a lxc container' do
      Gogetit.lxd.create(name)
      expect(Gogetit.lxd.list).to include(name)
    end

    it 'does not create if already exists' do
      expect(Gogetit.lxd.create(name)).to be false
    end

    it 'can delete a lxc container' do
      sleep 3
      Gogetit.lxd.destroy(name)
      expect(Gogetit.lxd.list).not_to include(name)
    end
  end

  context 'Libvirt' do
    it 'can create a domain' do
      Gogetit.libvirt.create(name)
      expect(Gogetit.libvirt.domain_exists?(name)).to be true
    end

    it 'does not create if already exists' do
      expect(Gogetit.libvirt.create(name)).to be false
    end

    it 'can destroy a domain' do
      Gogetit.libvirt.destroy(name)
      expect(Gogetit.libvirt.domain_exists?(name)).to be false
    end
  end

  #context 'Environment' do
  #  it 'can recognize its env' do
  #    expect(subject.env_name).to eq(subject.etcd_conn.get('env_name'))
  #  end

  #  it 'can import env variables' do
  #    subject.import_env
  #    expect(subject.env).to eq(JSON.parse(subject.etcd_conn.get('env')))
  #  end

  #  it 'can retrieve the Env values' do
  #    expect(subject.env).to be_an_instance_of(Hash)
  #  end
  #end
end

