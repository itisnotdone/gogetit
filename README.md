# Gogetit

Libraries with a CLI tool for dealing with things which I am working on such as [MAAS](https://docs.ubuntu.com/maas/2.2/en/), [LXD](https://github.com/lxc/lxd/tree/master/doc), Libvirt and Chef.
Using this, you will get to use them all together in automated and efficient way.

## Features
- Provides an API and a CLI tool for dealing with Libvirt(KVM) and LXD.
- Aware of [MAAS](https://github.com/itisnotdone/maas-client) and works with it to manage IP and FQDN allocation.
- Aware of Chef knife and its sub commands such as Vault to automate routine tasks.
- Can be used as a [kitchen driver](https://github.com/itisnotdone/kitchen-gogetkitchen) for Chef Kitchen.

## Installation

### dependent packages
```bash
sudo apt install -y build-essential lxd-client libvirt-dev libvirt-bin
# logout and in

# to remove default network(virbr0)
virsh net-destroy default
virsh net-undefine default

# chefdk environment
```

### install
```bash
$ gem install gogetit
$ gem install gogetit --no-ri --no-rdoc
```
## Usage
```bash
gogetit list
gogetit create lxd lxd01
gogetit create libvirt kvm01

gogetit destroy lxd01
gogetit rebuild kvm01

# to create a container bootstrapping as a chef node
gogetit create --chef chef01

# to destroy a container deleting corresponding chef node and client
gogetit destroy --chef chef01
```

```ruby
require 'gogetit'
```

## TODO
- Network subnets and space aware via MAAS
- Static IP allocation

## Development and Contributing
Clone and then execute followings:

    $ cd gogetit
    $ gem install bundle
    $ bundle

Questions and pull requests are always welcome!

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Gogetit project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/gogetit/blob/master/CODE_OF_CONDUCT.md).
