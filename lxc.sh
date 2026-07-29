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
        PORT=$(shuf -i 10000-65000 -n 1)
        if ! ss -tuln | grep -q ":$PORT\b" ; then
            echo "$PORT"
            break
        fi
    done
}

# 1. SETUP FUNCTION (FULLY UPDATED FOR FRESH INSTALL)
setup_env() {
    echo -e "${CYAN}--- Setting up Complete LXC Environment ---${NC}"
    
    # Step 1: Install LXD if not present
    if ! command -v lxd &> /dev/null; then
        echo -e "${YELLOW}[*] Installing LXD via snap...${NC}"
        apt-get update -y > /dev/null 2>&1
        apt-get install -y snapd > /dev/null 2>&1
        snap install lxd
        echo -e "${GREEN}[+] LXD Installed!${NC}"
    else
        echo -e "${GREEN}[+] LXD is already installed.${NC}"
    fi

    # Step 2: Initialize LXD
    echo -e "${YELLOW}[*] Initializing LXD...${NC}"
    lxd init --auto 2>/dev/null

    # Step 3: FIX STORAGE POOL FOREVER
    echo -e "${YELLOW}[*] Configuring Storage Pool & Root Device...${NC}"
    # Remove any broken root device from default profile
    lxc profile device remove default root 2>/dev/null
    # Create a fresh directory-backed pool named 'vpspool'
    lxc storage create vpspool dir 2>/dev/null
    # Attach 'vpspool' to the default profile
    lxc profile device add default root disk path=/ pool=vpspool 2>/dev/null

    # Step 4: Networking & Firewall
    echo -e "${YELLOW}[*] Applying Internet/Firewall forwarding rules...${NC}"
    iptables -I FORWARD -i lxdbr0 -j ACCEPT 2>/dev/null
    iptables -I FORWARD -o lxdbr0 -j ACCEPT 2>/dev/null
    lxc network set lxdbr0 ipv4.nat true 2>/dev/null
    sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw 2>/dev/null
    ufw reload >/dev/null 2>&1
    
    echo -e "${GREEN}[+] Environment Setup Complete! Your server is 100% ready.${NC}"
    pause
}

# 2. CREATE FUNCTION
create_vps() {
    echo -e "${CYAN}--- Create New VPS ---${NC}"
    read -p "Enter VPS Name: " vps_name
    read -p "Enter RAM in GB (e.g., 1, 2, 4): " ram_gb
    read -p "Enter CPU Cores (e.g., 1, 2): " cpu_cores
    read -p "Enter SSD Storage in GB (e.g., 10, 20): " disk_gb
    read -p "Enable Nesting & Privileged mode (for Docker)? (y/n): " opt_priv
    
    echo -e "${YELLOW}--- Termius (SSH) & Port Forwarding Setup ---${NC}"
    read -p "Enter Root Password for VPS: " root_pass
    read -p "Enter SSH Port (Leave blank for random single port): " custom_port
    read -p "Enter Extra Port Range to Forward (e.g., 14000-14100, or leave blank): " port_range

    if [ -z "$vps_name" ] || [ -z "$ram_gb" ] || [ -z "$cpu_cores" ] || [ -z "$disk_gb" ] || [ -z "$root_pass" ]; then
        echo -e "${RED}[!] Error: All required fields must be filled!${NC}"
        pause
        return
    fi

    if [ -z "$custom_port" ]; then
        ssh_port=$(generate_random_port)
    else
        ssh_port=$custom_port
    fi

    echo -e "${YELLOW}[*] Launching Ubuntu 22.04 container...${NC}"
    
    if [[ "$opt_priv" =~ ^[Yy]$ ]]; then
        if ! lxc launch ubuntu:22.04 "$vps_name" -c security.privileged=true -c security.nesting=true; then
            echo -e "${RED}[!] Critical Error: Failed to create VPS! Please run 'Setup Environment' (Option 1) first.${NC}"
            pause
            return
        fi
    else
        if ! lxc launch ubuntu:22.04 "$vps_name"; then
            echo -e "${RED}[!] Critical Error: Failed to create VPS! Please run 'Setup Environment' (Option 1) first.${NC}"
            pause
            return
        fi
    fi

    echo -e "${YELLOW}[*] Configuring resources...${NC}"
    lxc config set "$vps_name" limits.memory "${ram_gb}GB"
    lxc config set "$vps_name" limits.cpu "$cpu_cores"
    lxc config device override "$vps_name" root size="${disk_gb}GB"

    echo -e "${YELLOW}[*] Setting up SSH & Removing Annoying UI Prompts...${NC}"
    sleep 3 
    
    lxc exec "$vps_name" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get purge -y needrestart > /dev/null 2>&1"
    lxc exec "$vps_name" -- bash -c 'echo "Dpkg::Options { \"--force-confdef\"; \"--force-confold\"; }" > /etc/apt/apt.conf.d/99-force-confold'
    
    lxc exec "$vps_name" -- bash -c "echo 'root:$root_pass' | chpasswd"
    lxc exec "$vps_name" -- rm -f /etc/ssh/sshd_config.d/*.conf
    lxc exec "$vps_name" -- bash -c "echo -e 'PasswordAuthentication yes\nPermitRootLogin yes' > /etc/ssh/sshd_config.d/99-custom.conf"
    lxc exec "$vps_name" -- sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
    lxc exec "$vps_name" -- sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
    lxc exec "$vps_name" -- systemctl restart ssh

    lxc config device add "$vps_name" ssh_proxy proxy listen=tcp:0.0.0.0:$ssh_port connect=tcp:127.0.0.1:22

    if [ -n "$port_range" ]; then
        echo -e "${YELLOW}[*] Forwarding Port Range: $port_range...${NC}"
        lxc config device add "$vps_name" extra_ports proxy listen=tcp:0.0.0.0:$port_range connect=tcp:127.0.0.1:$port_range
    fi

    echo -e "${GREEN}[+] VPS '$vps_name' created successfully! 🚀${NC}"
    echo -e "${CYAN}>> Assigned SSH Port : $ssh_port ${NC}"
    [ -n "$port_range" ] && echo -e "${CYAN}>> Forwarded Ports : $port_range ${NC}"
    pause
}

# 3. MANAGE FUNCTION
manage_vps() {
    echo -e "${CYAN}--- Manage VPS ---${NC}"
    select_vps || { pause; return; }
    
    echo "1. Edit Resources (RAM/CPU/SSD)"
    echo "2. Setup/Reset Termius SSH & Add/Change Port Range"
    echo "3. Start VPS"
    echo "4. Stop VPS"
    echo -e "${RED}5. Reinstall VPS (Wipe Data, Keep Same Port/Resources/Nesting)${NC}"
    read -p "Select option [1-5]: " mng_opt

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
        read -p "Enter Custom SSH Port (Leave blank for random): " custom_port
        read -p "Enter Extra Port Range to Forward (e.g., 14000-14100, or leave blank): " port_range
        echo -e "${YELLOW}[*] Configuring SSH & Ports...${NC}"
        
        if [ -z "$custom_port" ]; then
            ssh_port=$(generate_random_port)
        else
            ssh_port=$custom_port
        fi
        
        lxc exec "$SELECTED_VPS" -- bash -c "echo 'root:$root_pass' | chpasswd"
        lxc exec "$SELECTED_VPS" -- rm -f /etc/ssh/sshd_config.d/*.conf
        lxc exec "$SELECTED_VPS" -- bash -c "echo -e 'PasswordAuthentication yes\nPermitRootLogin yes' > /etc/ssh/sshd_config.d/99-custom.conf"
        lxc exec "$SELECTED_VPS" -- sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
        lxc exec "$SELECTED_VPS" -- sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
        lxc exec "$SELECTED_VPS" -- systemctl restart ssh
        
        lxc config device add "$SELECTED_VPS" ssh_proxy proxy listen=tcp:0.0.0.0:$ssh_port connect=tcp:127.0.0.1:22 2>/dev/null || lxc config device set "$SELECTED_VPS" ssh_proxy listen=tcp:0.0.0.0:$ssh_port
        
        if [ -n "$port_range" ]; then
            lxc config device add "$SELECTED_VPS" extra_ports proxy listen=tcp:0.0.0.0:$port_range connect=tcp:127.0.0.1:$port_range 2>/dev/null || lxc config device set "$SELECTED_VPS" extra_ports listen=tcp:0.0.0.0:$port_range connect=tcp:127.0.0.1:$port_range
        fi
        
        echo -e "${GREEN}[+] Termius SSH & Ports configured successfully!${NC}"
        echo -e "${CYAN}>> SSH Port : $ssh_port ${NC}"
        [ -n "$port_range" ] && echo -e "${CYAN}>> Port Range : $port_range ${NC}"
        
    elif [ "$mng_opt" == "3" ]; then
        echo -e "${YELLOW}[*] Starting '$SELECTED_VPS'...${NC}"
        lxc start "$SELECTED_VPS"
        echo -e "${GREEN}[+] VPS Started successfully!${NC}"
        
    elif [ "$mng_opt" == "4" ]; then
        echo -e "${YELLOW}[*] Stopping '$SELECTED_VPS'...${NC}"
        lxc stop "$SELECTED_VPS"
        echo -e "${GREEN}[+] VPS Stopped successfully!${NC}"
        
    elif [ "$mng_opt" == "5" ]; then
        echo -e "${RED}[!] WARNING: This will WIPE ALL DATA on '$SELECTED_VPS'.${NC}"
        read -p "Are you sure you want to reinstall? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            read -p "Enter NEW Root Password for the reinstalled VPS: " root_pass
            
            curr_ram=$(lxc config get "$SELECTED_VPS" limits.memory 2>/dev/null)
            curr_cpu=$(lxc config get "$SELECTED_VPS" limits.cpu 2>/dev/null)
            curr_disk=$(lxc config device get "$SELECTED_VPS" root size 2>/dev/null)
            curr_nest=$(lxc config get "$SELECTED_VPS" security.nesting 2>/dev/null)
            curr_priv=$(lxc config get "$SELECTED_VPS" security.privileged 2>/dev/null)
            curr_port=$(lxc config device get "$SELECTED_VPS" ssh_proxy listen 2>/dev/null | awk -F: '{print $NF}')
            curr_range=$(lxc config device get "$SELECTED_VPS" extra_ports listen 2>/dev/null | awk -F: '{print $NF}')
            if [ -z "$curr_port" ]; then curr_port=$(generate_random_port); fi
            
            echo -e "${YELLOW}[*] Stopping and deleting old VPS...${NC}"
            lxc stop "$SELECTED_VPS" --force 2>/dev/null
            lxc delete "$SELECTED_VPS" 2>/dev/null
            
            echo -e "${YELLOW}[*] Launching fresh Ubuntu 22.04...${NC}"
            cmd=(lxc launch ubuntu:22.04 "$SELECTED_VPS")
            [ "$curr_nest" == "true" ] && cmd+=(-c security.nesting=true)
            [ "$curr_priv" == "true" ] && cmd+=(-c security.privileged=true)
            
            if ! "${cmd[@]}"; then
                echo -e "${RED}[!] Critical Error: Failed to reinstall VPS! Please check LXD storage pool.${NC}"
                pause
                return
            fi
            
            echo -e "${YELLOW}[*] Restoring previous resources...${NC}"
            [ -n "$curr_ram" ] && lxc config set "$SELECTED_VPS" limits.memory "$curr_ram"
            [ -n "$curr_cpu" ] && lxc config set "$SELECTED_VPS" limits.cpu "$curr_cpu"
            [ -n "$curr_disk" ] && lxc config device override "$SELECTED_VPS" root size="$curr_disk"
            
            echo -e "${YELLOW}[*] Configuring SSH & Removing UI Prompts...${NC}"
            sleep 3
            
            lxc exec "$SELECTED_VPS" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get purge -y needrestart > /dev/null 2>&1"
            lxc exec "$SELECTED_VPS" -- bash -c 'echo "Dpkg::Options { \"--force-confdef\"; \"--force-confold\"; }" > /etc/apt/apt.conf.d/99-force-confold'
            
            lxc exec "$SELECTED_VPS" -- bash -c "echo 'root:$root_pass' | chpasswd"
            lxc exec "$SELECTED_VPS" -- rm -f /etc/ssh/sshd_config.d/*.conf
            lxc exec "$SELECTED_VPS" -- bash -c "echo -e 'PasswordAuthentication yes\nPermitRootLogin yes' > /etc/ssh/sshd_config.d/99-custom.conf"
            lxc exec "$SELECTED_VPS" -- sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
            lxc exec "$SELECTED_VPS" -- sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
            lxc exec "$SELECTED_VPS" -- systemctl restart ssh
            
            lxc config device add "$SELECTED_VPS" ssh_proxy proxy listen=tcp:0.0.0.0:$curr_port connect=tcp:127.0.0.1:22
            if [ -n "$curr_range" ]; then
                lxc config device add "$SELECTED_VPS" extra_ports proxy listen=tcp:0.0.0.0:$curr_range connect=tcp:127.0.0.1:$curr_range
            fi
            
            echo -e "${GREEN}[+] Reinstall complete! VPS is fresh and ready.${NC}"
            echo -e "${CYAN}>> SSH Port (Restored) : $curr_port ${NC}"
            [ -n "$curr_range" ] && echo -e "${CYAN}>> Port Range (Restored): $curr_range ${NC}"
        else
            echo -e "${YELLOW}[-] Reinstall cancelled.${NC}"
        fi
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
        extra_ports=$(lxc config device get "$SELECTED_VPS" extra_ports listen 2>/dev/null | awk -F: '{print $NF}')
        
        echo -e "\n${GREEN}=== Termius Connection Details ===${NC}"
        echo -e "Host IP     : ${CYAN}$host_ip${NC}"
        if [ -n "$ssh_port" ]; then
            echo -e "SSH Port    : ${CYAN}$ssh_port${NC}"
            [ -n "$extra_ports" ] && echo -e "Port Range  : ${CYAN}$extra_ports${NC}"
            echo -e "Username    : ${CYAN}root${NC}"
            echo -e "Password    : ${CYAN}(The password you set)${NC}"
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
    echo -e "  ${GREEN}1.${NC} Setup Environment (Run First on Fresh Server)"
    echo -e "  ${GREEN}2.${NC} Create VPS"
    echo -e "  ${GREEN}3.${NC} Manage VPS (Start/Stop/Reinstall/Edit)"
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
