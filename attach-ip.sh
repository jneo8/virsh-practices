#!/bin/bash

# Attach multiple IP addresses to VMs using IP aliasing on one new interface
# Usage: ./attach-ip.sh <vm-name> <ip1,ip2,ip3,...> [network-name]

set -e

VM_NAME="$1"
IP_LIST="$2"
NETWORK_NAME="${3:-default}"

show_usage() {
    echo "Usage: $0 <vm-name> <ip1,ip2,ip3,...> [network-name]"
    echo ""
    echo "Examples:"
    echo "  $0 myvm 192.168.122.10                     # Single IP"
    echo "  $0 myvm 192.168.122.10,192.168.122.11     # Two IPs"
    echo "  $0 myvm 192.168.122.10,192.168.122.11,192.168.122.12  # Multiple IPs"
    echo ""
    echo "Note: VM must be running. Adds one new interface and uses IP aliasing."
    echo "      Use 'virsh net-list' to see available networks."
    exit 1
}

if [ -z "$VM_NAME" ] || [ -z "$IP_LIST" ] || [ "$VM_NAME" = "-h" ] || [ "$VM_NAME" = "--help" ]; then
    show_usage
fi

# Parse IP addresses into an array
IFS=',' read -ra IP_ARRAY <<< "$IP_LIST"

# Validate IP address format
validate_ip() {
    local ip="$1"
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "Error: Invalid IP address format: $ip"
        exit 1
    fi
}

# Validate all IP addresses
for ip in "${IP_ARRAY[@]}"; do
    validate_ip "$ip"
done

# Check if VM exists
if ! virsh list --all | grep -q "$VM_NAME"; then
    echo "Error: VM '$VM_NAME' not found"
    exit 1
fi

# Check if VM is running
if ! virsh domstate "$VM_NAME" | grep -q "running"; then
    echo "Error: VM '$VM_NAME' is not running. Start it first with: virsh start $VM_NAME"
    exit 1
fi

# Check if network exists
if ! virsh net-list --all | grep -q "$NETWORK_NAME"; then
    echo "Error: Network '$NETWORK_NAME' not found"
    echo "Available networks:"
    virsh net-list --all
    exit 1
fi

echo "Configuring ${#IP_ARRAY[@]} IP addresses for VM: $VM_NAME using IP aliasing"
echo "IPs: ${IP_ARRAY[*]}"
echo "Network: $NETWORK_NAME"

# Check current interfaces and add only one new interface (enp7s0)
CURRENT_INTERFACES=$(virsh domiflist "$VM_NAME" | awk 'NR>2 && NF>0 {print $1}' | wc -l)
echo "Current interface count: $CURRENT_INTERFACES"

# Add only one new interface for enp7s0
NEXT_INTERFACE_INDEX=$((CURRENT_INTERFACES + 1))
echo "Adding one new interface (will become enp${NEXT_INTERFACE_INDEX}s0)..."

virsh attach-interface "$VM_NAME" network "$NETWORK_NAME" --model virtio --persistent
sleep 2
echo "New interface added successfully!"

# Get the newly added interface MAC address (last interface)
LAST_INTERFACE_LINE=$((CURRENT_INTERFACES + 3))  # +3 because of header lines
TARGET_INTERFACE_MAC=$(virsh domiflist "$VM_NAME" | awk "NR==$LAST_INTERFACE_LINE && NF>=5 {print \$5}")
TARGET_INTERFACE="enp${NEXT_INTERFACE_INDEX}s0"
echo "Using new interface $TARGET_INTERFACE with MAC: $TARGET_INTERFACE_MAC for IP aliasing"

# Create DHCP reservations for IP aliasing
# echo "Creating DHCP reservations for IP aliasing..."
# for i in "${!IP_ARRAY[@]}"; do
#     IP="${IP_ARRAY[$i]}"
#     HOST_NAME="${VM_NAME}-${TARGET_INTERFACE}-alias-${i}"
#     
#     echo "Creating DHCP reservation: $TARGET_INTERFACE_MAC → $IP (host: $HOST_NAME)"
#     
#     # Add DHCP host reservation to the network (same MAC, different IPs)
#     virsh net-update "$NETWORK_NAME" add ip-dhcp-host \
#         "<host mac='$TARGET_INTERFACE_MAC' name='$HOST_NAME' ip='$IP'/>" \
#         --live --config || {
#         echo "Warning: Failed to add DHCP reservation for $TARGET_INTERFACE_MAC → $IP"
#         echo "This might be because the reservation already exists or there's a conflict"
#     }
# done
# 
# echo "DHCP reservations created successfully!"

# Get VM IP for SSH connection
VM_IP=$(virsh domifaddr "$VM_NAME" | awk 'NR==3{print $4}' | cut -d'/' -f1)

if [ -z "$VM_IP" ]; then
    echo "Warning: Could not get VM IP address for automatic configuration"
    echo "Manual configuration required inside VM"
else
    echo "Configuring IP aliasing inside VM via SSH..."
    
    # Wait for DHCP reservations to be processed
    echo "Waiting for DHCP reservations to be processed..."
    sleep 5
    
    # Apply the configuration via SSH
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$VM_IP "echo 'SSH connection test'" 2>/dev/null; then
        echo "Generating IP aliasing configuration..."
        
        # Get the actual interface name that corresponds to our MAC address
        ACTUAL_TARGET_INTERFACE=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$VM_IP "ip link show | grep -B1 '$TARGET_INTERFACE_MAC' | head -1 | awk '{print \$2}' | sed 's/:$//'")
        
        if [ -z "$ACTUAL_TARGET_INTERFACE" ]; then
            echo "Error: Could not find interface with MAC $TARGET_INTERFACE_MAC"
            exit 1
        fi
        
        echo "Using interface: $ACTUAL_TARGET_INTERFACE (MAC: $TARGET_INTERFACE_MAC) for IP aliasing"
        
        # Create netplan configuration for IP aliasing
        NETPLAN_CONFIG="network:
  version: 2
  ethernets:
    $ACTUAL_TARGET_INTERFACE:
      dhcp4: true
      dhcp6: false
      addresses:"

        # Add all additional IPs as static addresses
        for i in "${!IP_ARRAY[@]}"; do
            IP="${IP_ARRAY[$i]}"
            NETPLAN_CONFIG="$NETPLAN_CONFIG
        - $IP/24"
        done
        
        echo "Complete NETPLAN_CONFIG:"
        echo "$NETPLAN_CONFIG"
        
        # Apply the configuration via SSH
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$VM_IP << EOF
# Suppress apt update notifications
export APT_LISTCHANGES_FRONTEND=none
export DEBIAN_FRONTEND=noninteractive

# Create netplan configuration file
NETPLAN_FILE="/etc/netplan/60-ip-aliasing.yaml"

# Create a backup if file exists
if [ -f "\$NETPLAN_FILE" ]; then
    sudo cp "\$NETPLAN_FILE" "\$NETPLAN_FILE.backup"
fi

# Write the complete configuration
echo "Creating IP aliasing netplan configuration with ${#IP_ARRAY[@]} additional IPs..."
sudo tee "\$NETPLAN_FILE" > /dev/null << 'NETPLAN_EOF'
$NETPLAN_CONFIG
NETPLAN_EOF

# Set proper permissions
sudo chmod 600 "\$NETPLAN_FILE"
sudo chown root:root "\$NETPLAN_FILE"

# Show what was configured
echo "=== Complete netplan configuration ==="
sudo cat "\$NETPLAN_FILE"
echo "=== End configuration ==="

# Apply the configuration
sudo netplan generate
sudo netplan apply

# Wait for addresses to be configured
echo "Waiting for IP addresses to be configured..."
sleep 5

echo "IP aliasing configured successfully!"

# Show all IPs to verify
echo "All configured IPs:"
ip addr show | grep "inet " | grep -v "127.0.0.1"
EOF
        
        if [ $? -eq 0 ]; then
            echo "✅ All IP addresses configured successfully using IP aliasing!"
            echo "All IPs are now configured on interface: $ACTUAL_TARGET_INTERFACE"
        else
            echo "❌ Failed to apply IP aliasing configuration via SSH"
        fi
    else
        echo "❌ Could not connect to VM via SSH"
        echo "Manual configuration required"
    fi
fi

echo ""
echo "Current VM interfaces:"
virsh domiflist "$VM_NAME"

echo ""
echo "Verify with: ./list-vms.sh $VM_NAME"
echo "Test connectivity: ping ${IP_ARRAY[0]}"
