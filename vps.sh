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

# --- HELPER FUNCTION: SELECT VPS BY NUMBER ---
select_vps() {
    mapfile -t vps_array < <(lxc list -c n --format csv)
    
    if [ ${#vps_array[@]} -eq 0 ]; then
        echo -e "${RED}[!] No Active VPS found!${NC}"
        return 1
    fi
    
    echo -e "${CYAN}--- Available VPS List ---${NC}"
    for i in "${!vps_array[@]}"; do
        echo -e "  ${GREEN}$((i+1)).${NC} ${vps_array[$i]}"
    done
    echo "--------------------------"
    read -p "Select VPS by number: " vps_num
    
    if ! [[ "$vps_num" =~ ^[0-9]+$ ]] || [ "$vps_num" -lt 1 ] || [ "$vps_num" -gt "${#vps_array[@]}" ]; then
        echo -e "${RED}[!] Invalid selection!${NC}"
        return 1
    fi
    
    SELECTED_VPS="${vps_array[$((vps_num-1))]}"
    return 0
}

# --- HELPER FUNCTION: GENERATE RANDOM UNUSED PORT ---
generate_random_port() {
    while true; do
        # Generate random port between 10000 and 65000
        PORT=$(shuf -i 10000-65000 -n 1)
        # Check if port is in use
        if ! ss -tuln | grep -q ":$PORT\b" ; then
            echo "$PORT"
            break
        fi
    done
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
    read -p "Enter SSD Storage in GB (e.g., 10, 20): " disk_gb
    echo -e "${YELLOW}--- Termius (SSH) Setup ---${NC}"
    read -p "Enter Root Password for VPS: " root_pass

    if [ -z "$vps_name" ] || [ -z "$ram_gb" ] || [ -z "$cpu_cores" ] || [ -z "$disk_gb" ] || [ -z "$root_pass" ]; then
        echo -e "${RED}[!] Error: All fields are required!${NC}"
        pause
        return
    fi

    echo -e "${YELLOW}[*] Launching Ubuntu 22.04 container...${NC}"
    lxc launch ubuntu:22.04 "$vps_name"

    echo -e "${YELLOW}[*] Configuring resources...${NC}"
    lxc config set "$vps_name" limits.memory "${ram_gb}GB"
    lxc config set "$vps_name" limits.cpu "$cpu_cores"
    lxc config device override "$vps_name" root size="${disk_gb}GB"

    echo -e "${YELLOW}[*] Setting up SSH for Termius (Instant setup)...${NC}"
    sleep 3 # Just waiting 3 seconds for systemd to initialize inside container
    
    # Generate random port
    ssh_port=$(generate_random_port)
    
    # Configure SSH password and settings (Fixed Authentication issue)
    lxc exec "$vps_name" -- bash -c "echo 'root:$root_pass' | chpasswd"
    lxc exec "$vps_name" -- bash -c "echo -e 'PasswordAuthentication yes\nPermitRootLogin yes' > /etc/ssh/sshd_config.d/99-custom-ssh.conf"
    lxc exec "$vps_name" -- sed -i 's/^#*PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
    lxc exec "$vps_name" -- sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
    lxc exec "$vps_name" -- systemctl restart ssh

    # Forward port from Host to Container
    lxc config device add "$vps_name" ssh_proxy proxy listen=tcp:0.0.0.0:$ssh_port connect=tcp:127.0.0.1:22

    echo -e "${GREEN}[+] VPS '$vps_name' created successfully! 🚀${NC}"
    echo -e "${CYAN}>> Assigned SSH Port: $ssh_port ${NC}"
    pause
}

# 3. MANAGE (EDIT RESOURCES) FUNCTION
manage_vps() {
    echo -e "${CYAN}--- Manage VPS ---${NC}"
    select_vps || { pause; return; }
    
    echo "1. Edit Resources (RAM/CPU/SSD)"
    echo "2. Setup/Reset Termius SSH (Generates New Random Port)"
    read -p "Select option [1-2]: " mng_opt

    if [ "$mng_opt" == "1" ]; then
        echo -e "${YELLOW}(Leave blank and press Enter to keep current value)${NC}"
        read -p "Enter new RAM in GB: " new_ram
        read -p "Enter new CPU Cores: " new_cpu
        read -p "Enter new SSD in GB: " new_disk
        
        if [ -n "$new_ram" ]; then lxc config set "$SELECTED_VPS" limits.memory "${new_ram}GB"; fi
        if [ -n "$new_cpu" ]; then lxc config set "$SELECTED_VPS" limits.cpu "$new_cpu"; fi
        if [ -n "$new_disk" ]; then
            lxc config device set "$SELECTED_VPS" root size="${new_disk}GB" 2>/dev/null || lxc config device override "$SELECTED_VPS" root size="${new_disk}GB"
        fi
        echo -e "${GREEN}[+] Resources updated for '$SELECTED_VPS'!${NC}"
        
    elif [ "$mng_opt" == "2" ]; then
        read -p "Enter Root Password: " root_pass
        echo -e "${YELLOW}[*] Configuring SSH...${NC}"
        
        ssh_port=$(generate_random_port)
        
        lxc exec "$SELECTED_VPS" -- bash -c "echo 'root:$root_pass' | chpasswd"
        lxc exec "$SELECTED_VPS" -- bash -c "echo -e 'PasswordAuthentication yes\nPermitRootLogin yes' > /etc/ssh/sshd_config.d/99-custom-ssh.conf"
        lxc exec "$SELECTED_VPS" -- sed -i 's/^#*PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
        lxc exec "$SELECTED_VPS" -- sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
        lxc exec "$SELECTED_VPS" -- systemctl restart ssh
        
        # Try adding device, if it exists, set the new port instead
        lxc config device add "$SELECTED_VPS" ssh_proxy proxy listen=tcp:0.0.0.0:$ssh_port connect=tcp:127.0.0.1:22 2>/dev/null || lxc config device set "$SELECTED_VPS" ssh_proxy listen=tcp:0.0.0.0:$ssh_port
        
        echo -e "${GREEN}[+] Termius SSH configured! New Port: $ssh_port ${NC}"
    fi
    pause
}

# 4. CONNECT FUNCTION
connect_vps() {
    echo -e "${CYAN}--- Connect to VPS ---${NC}"
    select_vps || { pause; return; }
    
    echo ""
    echo -e "${YELLOW}How do you want to connect?${NC}"
    echo "1. Get Termius Details (IP & Port)"
    echo "2. Direct Console Connect (Auto-login)"
    read -p "Select option [1-2]: " conn_opt

    if [ "$conn_opt" == "1" ]; then
        host_ip=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")
        ssh_port=$(lxc config device get "$SELECTED_VPS" ssh_proxy listen 2>/dev/null | awk -F: '{print $NF}')
        
        echo -e "\n${GREEN}=== Termius Connection Details ===${NC}"
        echo -e "Host IP  : ${CYAN}$host_ip${NC}"
        if [ -n "$ssh_port" ]; then
            echo -e "Port     : ${CYAN}$ssh_port${NC}"
            echo -e "Username : ${CYAN}root${NC}"
            echo -e "Password : ${CYAN}(The password you set)${NC}"
        else
            echo -e "${RED}[!] SSH Port not found! Use Manage -> Option 2 to setup SSH first.${NC}"
        fi
        echo "=================================="
        pause
    elif [ "$conn_opt" == "2" ]; then
        echo -e "${YELLOW}[*] Connecting to root@$SELECTED_VPS... (Type 'exit' to leave)${NC}"
        lxc exec "$SELECTED_VPS" -- bash
        pause
    fi
}

# 5. DELETE FUNCTION
delete_vps() {
    echo -e "${CYAN}--- Delete VPS ---${NC}"
    select_vps || { pause; return; }
    
    echo -e "${RED}[*] Stopping and deleting '$SELECTED_VPS'...${NC}"
    lxc stop "$SELECTED_VPS" --force
    lxc delete "$SELECTED_VPS"
    echo -e "${GREEN}[-] VPS '$SELECTED_VPS' deleted completely.${NC}"
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
    echo -e "  ${GREEN}3.${NC} Manage VPS (Edit Resources / Termius SSH)"
    echo -e "  ${GREEN}4.${NC} Connect VPS (Terminal / Termius Info)"
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
