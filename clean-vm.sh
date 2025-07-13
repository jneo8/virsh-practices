#!/bin/bash
set -e

VM_NAME="$1"
IMAGE_DIR="/var/lib/libvirt/images"

if [[ -z "$VM_NAME" ]]; then
    echo "Usage: $0 <vm-name>"
    exit 1
fi

VM_IMG="$IMAGE_DIR/${VM_NAME}.qcow2"
SEED_IMG="$IMAGE_DIR/${VM_NAME}-seed.img"

echo "🛑 Stopping VM: $VM_NAME"
if sudo virsh list --all | grep -q "$VM_NAME"; then
    if sudo virsh domstate "$VM_NAME" | grep -q running; then
        sudo virsh destroy "$VM_NAME" || true
    fi
    sudo virsh undefine "$VM_NAME" || true
else
    echo "⚠️  VM '$VM_NAME' not found in libvirt"
fi

echo "🗑 Removing disk images..."
[[ -f "$VM_IMG" ]] && sudo rm -v "$VM_IMG"
[[ -f "$SEED_IMG" ]] && sudo rm -v "$SEED_IMG"

echo "🧽 Removing leftover cloud-init data (user-data, meta-data)..."
[[ -f user-data ]] && rm -v user-data
[[ -f meta-data ]] && rm -v meta-data

echo "✅ Cleanup complete for VM '$VM_NAME'"
