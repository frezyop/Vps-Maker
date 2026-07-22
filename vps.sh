#!/bin/bash

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Please run as root (sudo bash)${NC}"
  exit 1
fi

# Pause function to keep UI clean
pause() {
    echo ""
    read -p "Press [Enter] to return to the main menu..."
}

# 1. SETUP FUNCTION
setup_env() {
    echo -e "${YELLOW}[*] Setting up LXC/LXD Environment...${NC}"
    if ! command -v lxd &> /dev/null; then
        echo -e "${RED}[-] LXD not found. Installing LXD via snap...${NC}"
        apt update && apt install -y snapd
        snap install lxd
        lxd init --auto
        echo -e "${GREEN}[+] LXD installed and initialized successfully!${NC}"
    else
        echo -e "${GREEN}[+] LXD is already installed and ready!${NC}"
    fi
    pause
}

# 2. CREATE FUNCTION
create_vps() {
    echo -e "${CYAN}--- Create New VPS ---${NC}"
    read -p "Enter VPS Name: " vps_name
    read -p "Enter RAM in GB (e.g., 1, 2, 4): " ram_gb
    read -p "Enter CPU Cores (e.g., 1, 2): " cpu_cores

    if [ -z "$vps_name" ] || [ -z "$ram_gb" ] || [ -z "$cpu_cores" ]; then
        echo -e "${RED}[!] Error: All fields are required!${NC}"
        pause
        return
    fi

    echo -e "${YELLOW}[*] Launching Ubuntu 22.04 container...${NC}"
    lxc launch ubuntu:22.04 "$vps_name"

    echo -e "${YELLOW}[*] Configuring resources (${ram_gb}GB RAM, ${cpu_cores} CPUs)...${NC}"
    lxc config set "$vps_name" limits.memory "${ram_gb}GB"
    lxc config set "$vps_name" limits.cpu "$cpu_cores"

    echo -e "${GREEN}[+] VPS '$vps_name' created successfully! 🚀${NC}"
    pause
}

# 3. MANAGE (EDIT RESOURCES) FUNCTION
manage_vps() {
    echo -e "${CYAN}--- Active VPS List ---${NC}"
    lxc list
    echo "-----------------------"
    read -p "Enter VPS Name to edit resources: " vps_name
    read -p "Enter new RAM in GB (e.g., 1, 2, 4): " new_ram
    read -p "Enter new CPU Cores (e.g., 1, 2): " new_cpu
    
    if [ -n "$new_ram" ]; then
        lxc config set "$vps_name" limits.memory "${new_ram}GB"
    fi
    if [ -n "$new_cpu" ]; then
        lxc config set "$vps_name" limits.cpu "$new_cpu"
    fi
    
    echo -e "${GREEN}[+] Resources updated successfully for '$vps_name'!${NC}"
    pause
}

# 4. CONNECT FUNCTION
connect_vps() {
    echo -e "${CYAN}--- Active VPS List ---${NC}"
    lxc list
    echo "-----------------------"
    read -p "Enter VPS Name to connect: " vps_name
    echo -e "${YELLOW}[*] Connecting to root@$vps_name... (Type 'exit' to leave)${NC}"
    lxc exec "$vps_name" -- bash
    pause
}

# 5. DELETE FUNCTION
delete_vps() {
    echo -e "${CYAN}--- Active VPS List ---${NC}"
    lxc list
    echo "-----------------------"
    read -p "Enter VPS Name to delete: " vps_name
    
    echo -e "${RED}[*] Stopping and deleting '$vps_name'...${NC}"
    lxc stop "$vps_name" --force
    lxc delete "$vps_name"
    echo -e "${GREEN}[-] VPS '$vps_name' deleted completely.${NC}"
    pause
}

# MAIN MENU
while true; do
    clear
    echo -e "${BLUE}"
    echo "  ███████╗██████╗ ███████╗███████╗██╗   ██╗ "
    echo "  ██╔════╝██╔══██╗██╔════╝╚══███╔╝╚██╗ ██╔╝ "
    echo "  █████╗  ██████╔╝█████╗    ███╔╝  ╚████╔╝  "
    echo "  ██╔══╝  ██╔══██╗██╔══╝   ███╔╝    ╚██╔╝   "
    echo "  ██║     ██║  ██║███████╗███████╗   ██║    "
    echo "  ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝   ╚═╝    "
    echo -e "${CYAN}        L X C   V P S   M A N A G E R        ${NC}"
    echo -e "${YELLOW}=============================================${NC}"
    echo -e "  ${GREEN}1.${NC} Setup Environment"
    echo -e "  ${GREEN}2.${NC} Create VPS"
    echo -e "  ${GREEN}3.${NC} Manage VPS (Edit Resources)"
    echo -e "  ${GREEN}4.${NC} Connect VPS"
    echo -e "  ${GREEN}5.${NC} Delete VPS"
    echo -e "  ${RED}6.${NC} Exit"
    echo -e "${YELLOW}=============================================${NC}"
    read -p "Select choice [1-6]: " main_choice

    case $main_choice in
        1) setup_env ;;
        2) create_vps ;;
        3) manage_vps ;;
        4) connect_vps ;;
        5) delete_vps ;;
        6) clear; echo -e "${GREEN}Thanks for using the script!${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid choice! Please select 1-6.${NC}"; sleep 2 ;;
    esac
done
