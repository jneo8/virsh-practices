# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a VM management toolkit that provides multipass-like functionality using virsh/libvirt. The project consists of four main shell scripts that simplify virtual machine operations on Linux systems, with a focus on Ubuntu cloud images and DHCP-based networking.

## Core Scripts

### launch-vm.sh
The main VM creation script that mimics multipass behavior:
- Downloads Ubuntu cloud images automatically (focal/jammy/noble releases)
- Creates VMs with cloud-init configuration for automated setup
- Supports custom SSH keys, memory, CPU, and disk specifications
- Uses overlay disks (qcow2 backing files) for efficient storage
- Handles SSH key fallback hierarchy: custom → ~/.ssh/id_rsa.pub → ~/.ssh/id_ed25519.pub → generated fallback
- Creates temporary cloud-init ISO for first boot configuration

### list-vms.sh  
VM inventory and status script:
- Lists all VMs with their state and IP addresses
- Can show details for specific VMs with connection instructions
- Attempts to SSH into running VMs to gather all network interfaces
- Provides libvirt management command examples

### clean-vm.sh
VM cleanup script:
- Stops and removes VMs completely using virsh destroy/undefine
- Cleans up associated disk images, cloud-init ISOs, and metadata
- Handles both libvirt definitions and storage cleanup
- Removes temporary cloud-init data files

### attach-ip.sh
Advanced network configuration script:
- Attaches multiple network interfaces to running VMs
- Creates DHCP reservations for specific IP addresses
- Generates netplan configuration for DHCP-based IP assignment
- Uses MAC address matching for interface identification
- Supports multiple IPs per VM with automated interface naming (enp*s0)

## Architecture

The scripts work together as a cohesive VM management system:

1. **Image Management**: Downloads and caches Ubuntu cloud images in `/var/lib/libvirt/images/`
2. **Cloud-init Integration**: Generates temporary cloud-init configurations for automated VM setup
3. **SSH Key Handling**: Flexible SSH key injection with fallback hierarchy for passwordless access
4. **Memory Unit Conversion**: Converts human-readable memory specs (1G, 2G) to MB for virt-install
5. **Overlay Storage**: Uses qcow2 backing files to minimize disk usage and enable rapid VM creation
6. **Network Management**: DHCP-based IP assignment with libvirt network integration
7. **Interface Management**: Dynamic network interface attachment with MAC-to-IP reservations

## Network Architecture

- **Primary Network**: Uses libvirt's `default` network with DHCP
- **Multi-IP Support**: Creates additional network interfaces for each IP address
- **DHCP Reservations**: Maps MAC addresses to specific IP addresses via `virsh net-update`
- **Interface Naming**: Sequential interface naming (enp6s0, enp7s0, etc.) for predictable configuration
- **Netplan Integration**: Generates Ubuntu netplan configuration for DHCP-based IP assignment

## Common Commands

Launch a basic VM:
```bash
./launch-vm.sh myvm
```

Launch with custom specifications:
```bash
./launch-vm.sh myvm jammy 2G 2 10G ~/.ssh/mykey.pub
```

List all VMs:
```bash
./list-vms.sh
```

Show specific VM details:
```bash
./list-vms.sh myvm
```

Attach multiple IP addresses to a running VM:
```bash
./attach-ip.sh myvm 192.168.122.10,192.168.122.11,192.168.122.12
```

Clean up a VM:
```bash
./clean-vm.sh myvm
```

## VM Management Workflow

1. **Launch**: Use `launch-vm.sh` to create and start a VM with cloud-init
2. **Monitor**: Use `list-vms.sh` to check status and get connection info
3. **Network**: Use `attach-ip.sh` to assign additional IP addresses if needed
4. **Connect**: SSH to VMs using `ssh ubuntu@<ip>` (passwordless with injected keys)
5. **Cleanup**: Use `clean-vm.sh` to completely remove VMs and associated resources

## Dependencies

The scripts require:
- libvirt/virsh (VM management)
- virt-install (VM creation)
- qemu-img (disk image manipulation)
- genisoimage (cloud-init ISO creation)
- wget (image downloads)
- ssh (remote VM configuration)
- Standard Unix utilities (awk, grep, cut, etc.)

## Key Design Patterns

- **Idempotent Operations**: Running launch-vm.sh on existing VMs just starts them
- **Defensive Programming**: Scripts check for existing resources and VM states before operations
- **Cloud-Native Approach**: Uses Ubuntu cloud images with cloud-init rather than ISO installations
- **Minimal Configuration**: Sensible defaults with comprehensive override capabilities
- **Clean Separation**: Each script has a single responsibility (create, list, network, cleanup)
- **Error Handling**: Scripts use `set -e` and validate inputs before proceeding
- **Template-Based Configuration**: Uses cloud-init user-data templates for consistent VM setup

## File Structure and Locations

- **Base Images**: `/var/lib/libvirt/images/<release>-server-cloudimg-amd64.img`
- **VM Disks**: `/var/lib/libvirt/images/<vm-name>.qcow2` (overlay format)
- **Cloud-init ISOs**: `/var/lib/libvirt/images/<vm-name>-cloud-init.iso`
- **Temporary Config**: `/tmp/cloud-init-<vm-name>/` (cleaned up after VM creation)
- **Network Config**: Generated netplan files at `/etc/netplan/60-additional-interfaces.yaml` inside VMs