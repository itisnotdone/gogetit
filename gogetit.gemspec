# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'pry'
require 'gogetit/version'

Gem::Specification.new do |spec|
  spec.name          = 'gogetit'
  spec.version       = Gogetit::VERSION
  spec.authors       = ['Don Draper']
  spec.email         = ['donoldfashioned@gmail.com']

  spec.summary       = %q{Libraries with a CLI tool for dealing with things like MAAS, LXD and Libvirt.}
  spec.description   = <<-EOF
    This provides the ways that deal with mutiple virtualized and containerized solutions such as Libvirt(KVM) and LXD.
    This uses MAAS for bare-metal provision(KVM machine using Libvirt), DHCP and DNS.
    This will also provide the ways to deal with muchltiple development environment such as development, stage and production.
  EOF
  spec.homepage      = 'https://github.com/itisnotdone/gogetit.git'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'bin'
  spec.executables   = ['gogetit']
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'simplecov'

  spec.add_runtime_dependency 'json'
  spec.add_runtime_dependency 'hyperkit'
  spec.add_runtime_dependency 'maas-client'
  spec.add_runtime_dependency 'ruby-libvirt'
  spec.add_runtime_dependency 'oga'
  spec.add_runtime_dependency 'net-ssh'
  spec.add_runtime_dependency 'thor'
  spec.add_runtime_dependency 'hashie'
  spec.add_runtime_dependency 'table_print'
end
