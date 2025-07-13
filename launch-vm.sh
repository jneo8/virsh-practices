#!/bin/bash

# Simple VM launcher similar to multipass
# Usage: ./launch-vm.sh <vm-name> [release] [memory] [cpus] [disk] [ssh-key-path]

set -e

VM_NAME="$1"
RELEASE="${2:-jammy}"  # Ubuntu 22.04 LTS
MEMORY_INPUT="${3:-1G}"
CPUS="${4:-1}"
DISK="${5:-5G}"
SSH_KEY_PATH="$6"

# Convert memory to MB for virt-install
convert_memory() {
    local mem="$1"
    if [[ "$mem" =~ ^([0-9]+)G$ ]]; then
        echo $((${BASH_REMATCH[1]} * 1024))
    elif [[ "$mem" =~ ^([0-9]+)M$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$mem" =~ ^([0-9]+)$ ]]; then
        echo "$mem"
    else
        echo "1024"  # Default 1G
    fi
}

MEMORY=$(convert_memory "$MEMORY_INPUT")

IMAGES_DIR="/var/lib/libvirt/images"
CLOUD_INIT_DIR="/tmp/cloud-init-$VM_NAME"

show_usage() {
    echo "Usage: $0 <vm-name> [release] [memory] [cpus] [disk] [ssh-key-path]"
    echo ""
    echo "Examples:"
    echo "  $0 myvm                                    # Ubuntu 22.04, 1G RAM, 1 CPU, 5G disk, default SSH key"
    echo "  $0 myvm focal                              # Ubuntu 20.04"
    echo "  $0 myvm jammy 2G 2 10G                    # Ubuntu 22.04, 2G RAM, 2 CPUs, 10G disk"
    echo "  $0 myvm jammy 2G 2 10G ~/.ssh/mykey.pub   # Custom SSH public key"
    echo ""
    echo "Available releases: focal (20.04), jammy (22.04), noble (24.04)"
    echo "SSH key: If not specified, uses ~/.ssh/id_rsa.pub or generates a default key"
    exit 1
}

if [ -z "$VM_NAME" ] || [ "$VM_NAME" = "-h" ] || [ "$VM_NAME" = "--help" ]; then
    show_usage
fi

# Map release names to URLs
case "$RELEASE" in
    "focal"|"20.04")
        IMAGE_URL="https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
        OS_VARIANT="ubuntu20.04"
        ;;
    "jammy"|"22.04")
        IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
        OS_VARIANT="ubuntu22.04"
        ;;
    "noble"|"24.04")
        IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
        OS_VARIANT="ubuntu24.04"
        ;;
    *)
        echo "Error: Unknown release '$RELEASE'"
        echo "Available: focal, jammy, noble"
        exit 1
        ;;
esac

# Handle SSH key
get_ssh_key() {
    if [ -n "$SSH_KEY_PATH" ]; then
        if [ -f "$SSH_KEY_PATH" ]; then
            cat "$SSH_KEY_PATH"
        else
            echo "Error: SSH key file '$SSH_KEY_PATH' not found" >&2
            exit 1
        fi
    elif [ -f ~/.ssh/id_rsa.pub ]; then
        cat ~/.ssh/id_rsa.pub
    elif [ -f ~/.ssh/id_ed25519.pub ]; then
        cat ~/.ssh/id_ed25519.pub
    else
        # Generate a fallback key content (this won't actually work for SSH)
        echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDExample... user@host"
        echo "Warning: No SSH key found. You may need to set a password or provide a valid SSH key." >&2
    fi
}

SSH_KEY=$(get_ssh_key)
BASE_IMAGE="$IMAGES_DIR/${RELEASE}-server-cloudimg-amd64.img"
VM_DISK="$IMAGES_DIR/${VM_NAME}.qcow2"

echo "Launching $VM_NAME..."
echo "Release: Ubuntu $RELEASE"
echo "Memory: ${MEMORY}MB"
echo "CPUs: $CPUS"
echo "Disk: $DISK"

# Check if VM already exists
if virsh list --all | grep -q "$VM_NAME"; then
    echo "VM $VM_NAME already exists. Starting..."
    virsh start "$VM_NAME" 2>/dev/null || echo "VM already running"
    echo "Connect: ssh ubuntu@$(virsh domifaddr $VM_NAME | awk 'NR==3{print $4}' | cut -d'/' -f1)"
    exit 0
fi

# Download base image if not exists
if [ ! -f "$BASE_IMAGE" ]; then
    echo "Downloading Ubuntu $RELEASE cloud image..."
    sudo wget -O "$BASE_IMAGE" "$IMAGE_URL"
fi

# Create VM disk from base image
echo "Creating VM disk..."
sudo qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$VM_DISK" "$DISK"

# Create cloud-init configuration
mkdir -p "$CLOUD_INIT_DIR"

# User data (cloud-init)
cat > "$CLOUD_INIT_DIR/user-data" << EOF
#cloud-config
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $SSH_KEY

package_update: true
packages:
  - curl
  - wget
  - git

runcmd:
  - systemctl enable ssh
  - systemctl start ssh
EOF

# Meta data
cat > "$CLOUD_INIT_DIR/meta-data" << EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

# Create cloud-init ISO
sudo genisoimage -output "$IMAGES_DIR/${VM_NAME}-cloud-init.iso" \
    -volid cidata -joliet -rock \
    "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"

# Create and start VM
echo "Creating VM..."
sudo virt-install \
    --name "$VM_NAME" \
    --memory "$MEMORY" \
    --vcpus "$CPUS" \
    --disk path="$VM_DISK",format=qcow2,bus=virtio \
    --disk path="$IMAGES_DIR/${VM_NAME}-cloud-init.iso",device=cdrom \
    --network default \
    --os-variant "$OS_VARIANT" \
    --graphics none \
    --console pty,target_type=serial \
    --import \
    --noautoconsole

# Wait for VM to get IP
echo "Waiting for VM to start..."
sleep 10

# Get IP address
IP=$(virsh domifaddr "$VM_NAME" | awk 'NR==3{print $4}' | cut -d'/' -f1)
if [ -n "$IP" ]; then
    echo ""
    echo "VM $VM_NAME is ready!"
    echo "Connect: ssh ubuntu@$IP"
    echo "Stop: virsh shutdown $VM_NAME"
    echo "Delete: virsh destroy $VM_NAME && virsh undefine $VM_NAME --remove-all-storage"
else
    echo "VM created but IP not available yet. Check with: virsh domifaddr $VM_NAME"
fi

# Cleanup
rm -rf "$CLOUD_INIT_DIR"