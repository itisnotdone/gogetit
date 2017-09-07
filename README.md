# Gogetit

Libraries with a CLI tool for dealing with things such as [MAAS](https://docs.ubuntu.com/maas/2.2/en/), [LXD](https://github.com/lxc/lxd/tree/master/doc), Libvirt and Chef.
By using this, you will get to use them all together in automated and efficient way.

## Features
- Provides an API and a CLI tool for dealing with Libvirt(KVM) and LXD.
- Aware of MAAS and works with [maas-client](https://github.com/itisnotdone/maas-client) to manage IP and FQDN allocation.
- Aware of Chef knife and its sub commands such as Vault to automate routine tasks.
- Being used by [kitchen-gogetkitchen](https://github.com/itisnotdone/kitchen-gogetkitchen) as a driver for Chef Test Kitchen.

## Limitations
- Network resource awareness is only provided by MAAS.
- Only LXD and Libvirt(KVM) are available as provider.
- Only IPv4 is available for IP assignment.
- It is tested only on Ubuntu 16.04 with OVS as virtual switch.

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
gogetit create lxd01
gogetit create lxd01 --provider lxd

# For advanced network configuration
gogetit create lxd01 -p lxd -i 192.168.0.10

# When specifying multiple IPs, the first one will be chosen as gateway.
# And the IP which belongs to the gateway interface will be the IP of the FQDN
# of the container which is set by MAAS.
# The IPs should belong to networks defined and recognized by MAAS.
gogetit create lxd01 -p lxd -i 192.168.10.10 10.0.0.2

# When specifying multiple VLANs, the first one will be chosen as gateway.
# gogetit create lxd01 -p lxd -v 0 10 12
# gogetit create lxd01 -p lxd -v 10 11

gogetit create kvm01 -p libvirt
gogetit create kvm01 -p libvirt -i 192.168.10.10 10.0.0.2

# to provision with a bare metal machine
# gogetit create kvm01 -p bare

gogetit destroy lxd01
gogetit rebuild kvm01

# to create a container bootstrapping as a chef node
gogetit create chef01 --chef

or

CHEF=true gogetit create chef01


# to destroy a container deleting corresponding chef node and client
gogetit destroy chef01 --chef
```

```ruby
require 'gogetit'
```

## TODO
- Provisioning LXD with useful cloud-init user-data.
- Deploying bare metal machine from machine pool.
- Static IP auto-assignment with VLAN info.

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
