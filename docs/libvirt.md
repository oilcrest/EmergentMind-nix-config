# libvirt issues

- [libvirt issues](#libvirt-issues)
  - [networking](#networking)

## networking

If qemu isn't working because of lack of network, you need to run:

```bash
virsh net-autostart default
virsh net-start default
```

Is not clear how to get the first command to be part of the nix config
