#!/bin/bash

# List VMs and their IP addresses
# Usage: ./list-vms.sh [vm-name]

show_usage() {
    echo "Usage: $0 [vm-name]"
    echo ""
    echo "Examples:"
    echo "  $0           # List all VMs with IP addresses"
    echo "  $0 myvm      # Show specific VM details"
    exit 1
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
fi

VM_NAME="$1"

get_vm_info() {
    local vm="$1"
    local state=$(virsh domstate "$vm" 2>/dev/null)
    local ips=""
    
    if [ "$state" = "running" ]; then
        # Try to get IP addresses from virsh domifaddr (DHCP leases)
        local dhcp_ip=$(virsh domifaddr "$vm" 2>/dev/null | awk 'NR==3{print $4}' | cut -d'/' -f1)
        
        # Also try to get static IPs by SSH into the VM
        if [ -n "$dhcp_ip" ]; then
            local all_ips=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$dhcp_ip "ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print \$2}' | cut -d'/' -f1 | tr '\n' ',' | sed 's/,$/\n/'" 2>/dev/null || echo "$dhcp_ip")
            ips="$all_ips"
        else
            ips="<no-ip>"
        fi
    else
        ips="<stopped>"
    fi
    
    printf "%-20s %-10s %-25s\n" "$vm" "$state" "$ips"
}

if [ -n "$VM_NAME" ]; then
    # Show specific VM
    if virsh list --all | grep -q "$VM_NAME"; then
        echo "VM Details:"
        printf "%-20s %-10s %-25s\n" "NAME" "STATE" "IP ADDRESSES"
        printf "%-20s %-10s %-25s\n" "----" "-----" "-------------"
        get_vm_info "$VM_NAME"
        
        if [ "$(virsh domstate "$VM_NAME" 2>/dev/null)" = "running" ]; then
            echo ""
            echo "Connect: ssh ubuntu@$(virsh domifaddr "$VM_NAME" 2>/dev/null | awk 'NR==3{print $4}' | cut -d'/' -f1)"
        fi
    else
        echo "VM '$VM_NAME' not found"
        exit 1
    fi
else
    # List all VMs
    vms=$(virsh list --all --name | grep -v '^$')
    
    if [ -z "$vms" ]; then
        echo "No VMs found"
        exit 0
    fi
    
    echo "Virtual Machines:"
    printf "%-20s %-10s %-25s\n" "NAME" "STATE" "IP ADDRESSES"
    printf "%-20s %-10s %-25s\n" "----" "-----" "-------------"
    
    for vm in $vms; do
        get_vm_info "$vm"
    done
    
    echo ""
    echo "Commands:"
    echo "  Start VM:   virsh start <vm-name>"
    echo "  Stop VM:    virsh shutdown <vm-name>"
    echo "  Delete VM:  virsh destroy <vm-name> && virsh undefine <vm-name> --remove-all-storage"
fi