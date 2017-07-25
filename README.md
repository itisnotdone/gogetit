# Gogetit

Libraries with a CLI tool for dealing with things which I am working on such as MAAS, LXD, Libvirt and Chef.
Using this, you will get to used them all together in very efficient and nice way.

## Installation

### dependent packages
```bash
sudo apt install -y build-essential lxd-client libvirt-dev libvirt-bin
# logout and in

# to remove default network(virbr0)
virsh net-destroy default
virsh net-undefine default
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
