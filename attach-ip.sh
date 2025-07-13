#!/bin/bash

# Attach multiple IP addresses to VMs
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
    echo "  $0 myvm 192.168.122.10,192.168.122.11,192.168.122.12  # Three IPs"
    echo ""
    echo "Note: VM must be running. Use 'virsh net-list' to see available networks."
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

echo "Attaching ${#IP_ARRAY[@]} IP addresses to VM: $VM_NAME"
echo "IPs: ${IP_ARRAY[*]}"
echo "Network: $NETWORK_NAME"

# Get current interface count to determine starting interface names
CURRENT_INTERFACES=$(virsh domiflist "$VM_NAME" | awk 'NR>2 && NF>0 {print $1}' | wc -l)
echo "Debug: Current interface count: $CURRENT_INTERFACES"

# Attach the required number of interfaces and collect MAC addresses
declare -a MAC_ARRAY
for i in "${!IP_ARRAY[@]}"; do
    SLOT=$((CURRENT_INTERFACES + i + 6))  # Start from enp7s0
    INTERFACE_NAME="enp${SLOT}s0"
    
    echo "Adding interface $INTERFACE_NAME for IP ${IP_ARRAY[$i]}..."
    virsh attach-interface "$VM_NAME" network "$NETWORK_NAME" --model virtio --persistent
    sleep 2  # Give time for interface to be created
    
    # Get the MAC address of the newly attached interface
    # Get the last non-empty line with actual interface data
    NEW_MAC=$(virsh domiflist "$VM_NAME" | awk 'NR>2 && NF>=5 {mac=$5} END {print mac}')
    MAC_ARRAY[$i]="$NEW_MAC"
    echo "Interface $INTERFACE_NAME has MAC: $NEW_MAC"
    
    # Debug: Show current domiflist output
    echo "Debug: Current domiflist output:"
    virsh domiflist "$VM_NAME"
done

echo "All interfaces attached successfully!"
echo "MAC addresses collected: ${MAC_ARRAY[*]}"

# Create DHCP reservations for each MAC→IP mapping
echo "Creating DHCP reservations..."
for i in "${!IP_ARRAY[@]}"; do
    MAC="${MAC_ARRAY[$i]}"
    IP="${IP_ARRAY[$i]}"
    SLOT=$((CURRENT_INTERFACES + i + 6))
    HOST_NAME="${VM_NAME}-enp${SLOT}s0"
    
    echo "Creating DHCP reservation: $MAC → $IP (host: $HOST_NAME)"
    
    # Add DHCP host reservation to the network
    virsh net-update "$NETWORK_NAME" add ip-dhcp-host \
        "<host mac='$MAC' name='$HOST_NAME' ip='$IP'/>" \
        --live --config || {
        echo "Warning: Failed to add DHCP reservation for $MAC → $IP"
        echo "This might be because the reservation already exists or there's a conflict"
    }
done

echo "DHCP reservations created successfully!"

# Get VM IP for SSH connection
VM_IP=$(virsh domifaddr "$VM_NAME" | awk 'NR==3{print $4}' | cut -d'/' -f1)

if [ -z "$VM_IP" ]; then
    echo "Warning: Could not get VM IP address for automatic configuration"
    echo "Manual configuration required inside VM"
else
    echo "Configuring DHCP-based IP assignment inside VM via SSH..."
    
    # Wait for interfaces to be detected
    echo "Waiting for new interfaces to be detected..."
    sleep 5
    
    # Apply the configuration via SSH
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$VM_IP "echo 'SSH connection test'" 2>/dev/null; then
        echo "Generating complete netplan configuration..."
        
        # Debug: Show what MAC addresses we have before generating config
        echo "Debug: MAC_ARRAY contents before netplan generation:"
        for i in "${!MAC_ARRAY[@]}"; do
            echo "  MAC_ARRAY[$i] = '${MAC_ARRAY[$i]}'"
        done
        
        # Create the complete netplan configuration using DHCP
        # Build the configuration string with proper variable substitution
        NETPLAN_CONFIG="network:
  version: 2
  ethernets:"

        for i in "${!IP_ARRAY[@]}"; do
            SLOT=$((CURRENT_INTERFACES + i + 6))
            IFACE="enp${SLOT}s0"
            MAC="${MAC_ARRAY[$i]}"
            
            echo "Debug: Building config for $IFACE with MAC: $MAC"
            
            NETPLAN_CONFIG="$NETPLAN_CONFIG
    $IFACE:
      match:
        macaddress: \"$MAC\"
      dhcp4: true
      dhcp6: false"
        done
        
        echo "Debug: Complete NETPLAN_CONFIG:"
        echo "$NETPLAN_CONFIG"
        
        # Apply the configuration via SSH
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$VM_IP << EOF
# Suppress apt update notifications
export APT_LISTCHANGES_FRONTEND=none
export DEBIAN_FRONTEND=noninteractive

# Create netplan configuration file
NETPLAN_FILE="/etc/netplan/60-additional-interfaces.yaml"

# Create a backup if file exists
if [ -f "\$NETPLAN_FILE" ]; then
    sudo cp "\$NETPLAN_FILE" "\$NETPLAN_FILE.backup"
fi

# Write the complete configuration
echo "Creating DHCP-based netplan configuration with ${#IP_ARRAY[@]} interfaces..."
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

# Restart networking to ensure DHCP reservations are picked up
echo "Restarting networking services to pick up DHCP reservations..."
sudo systemctl restart systemd-networkd
sleep 5

echo "All interfaces configured successfully with DHCP reservations!"

# Show all IPs to verify
echo "All configured IPs:"
ip addr show | grep "inet " | grep -v "127.0.0.1"
EOF
        
        if [ $? -eq 0 ]; then
            echo "✅ All IP addresses configured successfully with DHCP reservations!"
            echo "IPs should now appear in 'virsh net-dhcp-leases $NETWORK_NAME' and 'virsh domifaddr $VM_NAME'"
        else
            echo "❌ Failed to apply network configuration via SSH"
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