# Virsh Practices - VM Management Toolkit

A collection of shell scripts that provide multipass-like functionality using virsh/libvirt for managing virtual machines on Linux systems. This toolkit simplifies VM operations with Ubuntu cloud images, automated setup, and network management.

## Features

- **🚀 Quick VM Creation**: Launch Ubuntu VMs in seconds using cloud images
- **🔐 Automated SSH Setup**: Passwordless SSH access with automatic key injection
- **💾 Efficient Storage**: Uses qcow2 overlay disks to minimize storage usage
- **🌐 Advanced Networking**: Multi-IP support with DHCP reservations
- **🧹 Complete Cleanup**: One-command VM removal with all associated resources
- **☁️ Cloud-Native**: Uses cloud-init for automated VM configuration

## Prerequisites

Ensure the following packages are installed on your Linux system:

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install libvirt-daemon-system libvirt-clients virt-manager qemu-kvm genisoimage wget ssh
```

**System Requirements:**
- Linux system with KVM support
- User must be in the `libvirt` group: `sudo usermod -a -G libvirt $USER`
- At least 2GB free space in `/var/lib/libvirt/images/`
- Internet connection for downloading Ubuntu cloud images

## Quick Start

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd virsh-practices
   ```

2. **Make scripts executable:**
   ```bash
   chmod +x *.sh
   ```

3. **Launch your first VM:**
   ```bash
   ./launch-vm.sh myvm
   ```

4. **Connect to the VM:**
   ```bash
   ssh ubuntu@<ip-address>
   ```

## Scripts Overview

### 🚀 launch-vm.sh
Creates and starts virtual machines with cloud-init configuration.

**Usage:**
```bash
./launch-vm.sh <vm-name> [release] [memory] [cpus] [disk] [ssh-key-path]
```

**Examples:**
```bash
# Basic VM with defaults (Ubuntu 22.04, 1G RAM, 1 CPU, 5G disk)
./launch-vm.sh myvm

# Custom Ubuntu release
./launch-vm.sh myvm focal

# Custom specifications
./launch-vm.sh myvm jammy 2G 2 10G

# Custom SSH key
./launch-vm.sh myvm jammy 2G 2 10G ~/.ssh/mykey.pub
```

**Supported Releases:**
- `focal` (Ubuntu 20.04 LTS)
- `jammy` (Ubuntu 22.04 LTS) - default
- `noble` (Ubuntu 24.04 LTS)

### 📋 list-vms.sh
Lists all VMs with their status and IP addresses.

**Usage:**
```bash
./list-vms.sh [vm-name]
```

**Examples:**
```bash
# List all VMs
./list-vms.sh

# Show specific VM details
./list-vms.sh myvm
```

### 🌐 attach-ip.sh
Attaches multiple IP addresses to running VMs using DHCP reservations.

**Usage:**
```bash
./attach-ip.sh <vm-name> <ip1,ip2,ip3,...> [network-name]
```

**Examples:**
```bash
# Single IP
./attach-ip.sh myvm 192.168.122.10

# Multiple IPs
./attach-ip.sh myvm 192.168.122.10,192.168.122.11,192.168.122.12
```

### 🧹 clean-vm.sh
Completely removes VMs and all associated resources.

**Usage:**
```bash
./clean-vm.sh <vm-name>
```

**Example:**
```bash
./clean-vm.sh myvm
```

## Workflow Examples

### Basic VM Management
```bash
# Create and start a VM
./launch-vm.sh webserver jammy 2G 2 20G

# Check VM status
./list-vms.sh webserver

# Connect to VM
ssh ubuntu@192.168.122.100

# Clean up when done
./clean-vm.sh webserver
```

### Multi-IP Load Balancer Setup
```bash
# Launch VM
./launch-vm.sh loadbalancer jammy 4G 4 50G

# Attach multiple IPs for load balancing
./attach-ip.sh loadbalancer 192.168.122.10,192.168.122.11,192.168.122.12

# Verify configuration
./list-vms.sh loadbalancer
```

### Development Environment
```bash
# Create VMs for different services
./launch-vm.sh database jammy 4G 2 20G
./launch-vm.sh backend jammy 2G 2 10G
./launch-vm.sh frontend jammy 1G 1 10G

# List all development VMs
./list-vms.sh
```

## Architecture

The toolkit uses a cloud-native approach with the following architecture:

- **Base Images**: Downloaded Ubuntu cloud images stored in `/var/lib/libvirt/images/`
- **VM Disks**: qcow2 overlay files that reference base images for efficiency
- **Cloud-init**: Automated VM configuration with SSH keys and package installation
- **Networking**: libvirt default network with DHCP and custom IP reservations
- **Storage**: Minimal disk usage through qcow2 backing files

## File Locations

| Component | Location |
|-----------|----------|
| Base Images | `/var/lib/libvirt/images/<release>-server-cloudimg-amd64.img` |
| VM Disks | `/var/lib/libvirt/images/<vm-name>.qcow2` |
| Cloud-init ISOs | `/var/lib/libvirt/images/<vm-name>-cloud-init.iso` |
| Temp Config | `/tmp/cloud-init-<vm-name>/` (auto-cleaned) |

## Troubleshooting

### Common Issues

**Permission denied when running scripts:**
```bash
# Make sure you're in the libvirt group
sudo usermod -a -G libvirt $USER
# Log out and back in, or run:
newgrp libvirt
```

**VM creation fails with "Network 'default' is not active":**
```bash
# Start the default network
sudo virsh net-start default
sudo virsh net-autostart default
```

**Cannot connect to VM via SSH:**
```bash
# Check VM IP address
./list-vms.sh <vm-name>

# Verify SSH key permissions
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
```

**Download fails for cloud images:**
```bash
# Manually download if needed
sudo wget -O /var/lib/libvirt/images/jammy-server-cloudimg-amd64.img \
  https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

### Debugging

**Check VM console output:**
```bash
sudo virsh console <vm-name>
# Press Ctrl+] to exit console
```

**View VM logs:**
```bash
sudo journalctl -u libvirtd
```

**Network debugging:**
```bash
# Check network status
virsh net-list --all
virsh net-dhcp-leases default

# Check VM interfaces
virsh domiflist <vm-name>
```

## Security Considerations

- VMs use passwordless sudo for the `ubuntu` user
- SSH keys are automatically injected for secure access
- VMs are isolated in libvirt's default network
- Cloud images are downloaded over HTTPS
- All temporary files are cleaned up after VM creation

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with different Ubuntu releases
5. Submit a pull request

## License

This project is open source. See the repository for license details.

## Related Projects

- [Multipass](https://multipass.run/) - Ubuntu VM management (inspiration for this toolkit)
- [libvirt](https://libvirt.org/) - Virtualization API
- [cloud-init](https://cloud-init.io/) - Cloud instance initialization
