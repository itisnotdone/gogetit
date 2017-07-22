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

  spec.add_development_dependency 'bundler', '~> 1.15'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'pry', '~> 0.10.4'
  spec.add_development_dependency 'simplecov', '~> 0.14.1'

  #spec.add_runtime_dependency 'etcd-rb', '~> 1.1.0'
  spec.add_runtime_dependency 'json', '~> 2.1.0'
  spec.add_runtime_dependency 'hyperkit', '~> 1.1.0'
  spec.add_runtime_dependency 'maas-client', '~> 0.1.23'
  spec.add_runtime_dependency 'ruby-libvirt', '~> 0.7.0'
  spec.add_runtime_dependency 'oga', '~> 2.10'
  spec.add_runtime_dependency 'net-ssh', '~> 4.1.0'
  spec.add_runtime_dependency 'thor', '~> 0.19.0'
end
