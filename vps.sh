#!/bin/bash

# Colors for UI
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function show_header() {
    clear
    echo -e "${CYAN}=======================================${NC}"
    echo -e "${GREEN}       KVM VPS MANAGER UTILITY       ${NC}"
    echo -e "${CYAN}=======================================${NC}"
}

function setup_vds() {
    echo -e "${YELLOW}Setting up VDS Dependencies (KVM, QEMU, Libvirt)...${NC}"
    sudo apt-get update -y
    sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst libguestfs-tools wget curl
    sudo systemctl enable --now libvirtd
    
    # Start default network if not active
    sudo virsh net-start default >/dev/null 2>&1
    sudo virsh net-autostart default >/dev/null 2>&1
    
    echo -e "${GREEN}Setup Complete! ✅ Dependencies and KVM are ready.${NC}"
    read -p "Press Enter to return to menu..."
}

function list_vps() {
    echo -e "${CYAN}Available VPS:${NC}"
    mapfile -t vps_list < <(virsh list --all --name | grep -v '^$')
    if [ ${#vps_list[@]} -eq 0 ]; then
        echo -e "${RED}No VPS found.${NC}"
        return 1
    fi
    for i in "${!vps_list[@]}"; do
        echo "$((i+1)). ${vps_list[$i]}"
    done
    return 0
}

function create_vps() {
    echo -e "${CYAN}--- Create New VPS ---${NC}"
    read -p "Name: " vps_name
    read -p "Password (Root): " vps_pass
    read -p "RAM (in MB, e.g., 2048): " vps_ram
    read -p "CPU (Cores, e.g., 2): " vps_cpu
    read -p "SSD (in GB, e.g., 20): " vps_ssd
    read -p "SSH Port (e.g., 2222, 2223) [Leave blank for 22]: " vps_port
    
    if [ -z "$vps_port" ]; then
        vps_port=22
    fi

    echo "Select Software:"
    echo "1. Ubuntu 22.04"
    echo "2. Debian 12"
    read -p "Choose (1/2): " os_choice

    os_variant="ubuntu22.04"
    image_url="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    
    if [ "$os_choice" == "2" ]; then
        os_variant="debian11"
        image_url="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
    fi

    echo -e "${YELLOW}Downloading Base OS Image (if not exists)...${NC}"
    mkdir -p /var/lib/libvirt/images/base
    base_image="/var/lib/libvirt/images/base/base_os.qcow2"
    if [ ! -f "$base_image" ]; then
        wget -O "$base_image" "$image_url"
    fi

    echo -e "${YELLOW}Creating VPS Disk and Configuring OS & Network...${NC}"
    vps_disk="/var/lib/libvirt/images/${vps_name}.qcow2"
    qemu-img create -f qcow2 -b "$base_image" -F qcow2 "$vps_disk" "${vps_ssd}G"
    
    # Save port locally
    echo "$vps_port" > "/var/lib/libvirt/images/${vps_name}.port"
    
    # Inject password, fix SSH port, remove cloud-init, and FORCE network DHCP on boot
    virt-customize -a "$vps_disk" \
        --uninstall cloud-init \
        --root-password password:"$vps_pass" \
        --run-command "sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config" \
        --run-command "sed -i 's/^#Port 22/Port $vps_port/g' /etc/ssh/sshd_config" \
        --run-command "grep -q '^Port ' /etc/ssh/sshd_config || echo 'Port $vps_port' >> /etc/ssh/sshd_config" \
        --run-command "sed -i 's/^Port 22/Port $vps_port/g' /etc/ssh/sshd_config" \
        --run-command "mkdir -p /etc/systemd/network" \
        --run-command "echo -e '[Match]\nName=en* eth*\n[Network]\nDHCP=yes' > /etc/systemd/network/20-wired.network" \
        --run-command "systemctl enable systemd-networkd systemd-resolved"

    echo -e "${YELLOW}Booting VPS...${NC}"
    virt-install \
        --name "$vps_name" \
        --memory "$vps_ram" \
        --vcpus "$vps_cpu" \
        --disk "$vps_disk",bus=virtio \
        --import \
        --os-variant "$os_variant" \
        --network default,model=virtio \
        --noautoconsole

    echo -e "${GREEN}Done ✅ VPS '$vps_name' created successfully!${NC}"
    echo -e "${GREEN}SSH Port assigned: $vps_port${NC}"
    read -p "Press Enter to return to menu..."
}

function manage_vps() {
    echo -e "${CYAN}--- Manage VPS ---${NC}"
    list_vps
    if [ $? -ne 0 ]; then read -p "Press Enter to return..."; return; fi
    
    read -p "Select VPS by typing number: " vps_num
    selected_vps="${vps_list[$((vps_num-1))]}"
    
    if [ -z "$selected_vps" ]; then echo -e "${RED}Invalid selection.${NC}"; sleep 1; return; fi
    
    echo -e "${CYAN}Managing: $selected_vps${NC}"
    echo "1. Start"
    echo "2. Restart"
    echo "3. Reinstall (Coming Soon)"
    echo "4. Change Password"
    read -p "Choose option: " m_opt
    
    case $m_opt in
        1) virsh start "$selected_vps" ;;
        2) virsh reboot "$selected_vps" ;;
        3) echo -e "${RED}Reinstall feature coming soon (Requires deleting and recreating).${NC}" ;;
        4) 
           read -p "Enter new root password: " new_pass
           virsh destroy "$selected_vps" 2>/dev/null
           virt-customize -a "/var/lib/libvirt/images/${selected_vps}.qcow2" --root-password password:"$new_pass"
           virsh start "$selected_vps"
           echo -e "${GREEN}Password updated!${NC}"
           ;;
        *) echo "Invalid option." ;;
    esac
    read -p "Press Enter to return..."
}

function connect_vps() {
    echo -e "${CYAN}--- Connect VPS ---${NC}"
    list_vps
    if [ $? -ne 0 ]; then read -p "Press Enter to return..."; return; fi
    
    read -p "Select VPS by typing number: " vps_num
    selected_vps="${vps_list[$((vps_num-1))]}"
    
    if [ -z "$selected_vps" ]; then echo -e "${RED}Invalid selection.${NC}"; sleep 1; return; fi

    echo -e "${YELLOW}Fetching IP address... (Waiting up to 30 seconds for boot)${NC}"
    
    MAC=$(virsh domiflist "$selected_vps" | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
    vps_ip=""
    
    for i in {1..15}; do
        vps_ip=$(virsh net-dhcp-leases default | grep -i "$MAC" | awk '{print $5}' | cut -d/ -f1 | head -n 1)
        if [ -n "$vps_ip" ]; then
            break
        fi
        sleep 2
    done

    if [ -z "$vps_ip" ]; then
        vps_ip=$(virsh domifaddr "$selected_vps" --source arp 2>/dev/null | awk 'NR>2 {print $4}' | cut -d/ -f1 | head -n 1)
    fi
    
    if [ -z "$vps_ip" ]; then
        vps_ip="Failed to fetch IP. Network issue or boot took too long."
    fi

    if [ -f "/var/lib/libvirt/images/${selected_vps}.port" ]; then
        saved_port=$(cat "/var/lib/libvirt/images/${selected_vps}.port")
    else
        saved_port="22"
    fi

    echo -e "${GREEN}==============================${NC}"
    echo -e "Connection Details for Termius:"
    echo -e "VPS Name : ${CYAN}$selected_vps${NC}"
    echo -e "IP       : ${CYAN}$vps_ip${NC}"
    echo -e "Username : ${CYAN}root${NC}"
    echo -e "Password : ${CYAN}[The password you set during creation]${NC}"
    echo -e "Port     : ${CYAN}$saved_port${NC}"
    echo -e "${GREEN}==============================${NC}"
    read -p "Press Enter to return to menu..."
}

function delete_vps() {
    echo -e "${CYAN}--- Delete VPS ---${NC}"
    list_vps
    if [ $? -ne 0 ]; then read -p "Press Enter to return..."; return; fi
    
    read -p "Select VPS by typing number: " vps_num
    selected_vps="${vps_list[$((vps_num-1))]}"
    
    if [ -z "$selected_vps" ]; then echo -e "${RED}Invalid selection.${NC}"; sleep 1; return; fi
    
    read -p "By typing 'y' you confirm that you want to delete your VPS '$selected_vps': " confirm
    if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
        echo -e "${RED}Deleting VPS...${NC}"
        virsh destroy "$selected_vps" 2>/dev/null
        virsh undefine "$selected_vps" --remove-all-storage
        rm -f "/var/lib/libvirt/images/${selected_vps}.port"
        echo -e "${GREEN}VPS deleted successfully!${NC}"
    else
        echo "Deletion cancelled."
    fi
    read -p "Press Enter to return..."
}

while true; do
    show_header
    echo "1. Create VPS"
    echo "2. Manage VPS"
    echo "3. Connect"
    echo "4. Delete VPS"
    echo "5. Setup (Run this first on new VDS)"
    echo "0. Exit"
    echo -e "${CYAN}---------------------------------------${NC}"
    read -p "Enter your choice: " choice

    case $choice in
        1) create_vps ;;
        2) manage_vps ;;
        3) connect_vps ;;
        4) delete_vps ;;
        5) setup_vds ;;
        0) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid choice!${NC}"; sleep 1 ;;
    esac
done
