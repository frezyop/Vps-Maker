#!/bin/bash

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo bash)"
  exit 1
fi

# Function to check and install LXD if missing
install_lxd() {
    if ! command -v lxd &> /dev/null; then
        echo "[-] LXD not found. Installing LXD..."
        apt update && apt install -y snapd
        snap install lxd
        lxd init --auto
        echo "[+] LXD installed and initialized successfully!"
    fi
}

# 1. SETUP FUNCTION
setup_env() {
    echo "[*] Setting up LXC/LXD Environment..."
    install_lxd
    echo "[+] Environment is ready and lightning fast!"
}

# 2. CREATE FUNCTION (RAM in GB)
create_vps() {
    install_lxd
    read -p "Enter VPS Name: " vps_name
    read -p "Enter RAM in GB (e.g., 1, 2, 4): " ram_gb
    read -p "Enter CPU Cores (e.g., 1, 2): " cpu_cores

    echo "[*] Launching Ubuntu 22.04 container..."
    lxc launch ubuntu:22.04 "$vps_name"

    echo "[*] Configuring resources (${ram_gb}GB RAM, ${cpu_cores} CPUs)..."
    lxc config set "$vps_name" limits.memory "${ram_gb}GB"
    lxc config set "$vps_name" limits.cpu "$cpu_cores"

    echo "[+] VPS '$vps_name' created successfully!"
}

# 3. MANAGE & EDIT RESOURCES FUNCTION
manage_vps() {
    echo "--- Active VPS List ---"
    lxc list
    echo "-----------------------"
    echo "1. Connect to VPS"
    echo "2. Edit Resources (RAM/CPU)"
    echo "3. Delete VPS"
    read -p "Choose an option: " choice

    case $choice in
        1)
            read -p "Enter VPS Name to connect: " vps_name
            lxc exec "$vps_name" -- bash
            ;;
        2)
            read -p "Enter VPS Name to edit resources: " vps_name
            read -p "Enter new RAM in GB (e.g., 1, 2, 4): " new_ram
            read -p "Enter new CPU Cores (e.g., 1, 2): " new_cpu
            
            lxc config set "$vps_name" limits.memory "${new_ram}GB"
            lxc config set "$vps_name" limits.cpu "$new_cpu"
            echo "[+] Resources updated successfully for '$vps_name'!"
            ;;
        3)
            read -p "Enter VPS Name to delete: " vps_name
            lxc stop "$vps_name" --force
            lxc delete "$vps_name"
            echo "[-] VPS '$vps_name' deleted."
            ;;
        *)
            echo "Invalid option!"
            ;;
    esac
}

# MAIN MENU
while true; do
    echo ""
    echo "=== LXC Turbo Manager ==="
    echo "1. Setup Environment"
    echo "2. Create VPS"
    echo "3. Manage VPS / Edit Resources"
    echo "4. Exit"
    read -p "Select choice: " main_choice

    case $main_choice in
        1) setup_env ;;
        2) create_vps ;;
        3) manage_vps ;;
        4) exit 0 ;;
        *) echo "Invalid choice!" ;;
    esac
done
