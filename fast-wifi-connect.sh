#!/bin/bash

# Configuration
VERSION="5.0"
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/wifi-connection.log"
TMP_FILE="/tmp/network_temp.$$"
CONFIG_DIR="$HOME/.config/fast-wifi"
SAVED_NETWORKS="$CONFIG_DIR/saved_networks.conf"
INTERFACE=""
MAX_LOG_LINES=1000
DEPENDENCIES=("nmcli" "ip" "awk" "grep" "curl" "ss" "ping")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# ASCII Art
show_banner() {
    echo -e "${BLUE}"
    cat << "EOF"
 ███████╗ █████╗ ███████╗████████╗██╗    ██╗██╗███████╗██╗
 ██╔════╝██╔══██╗██╔════╝╚══██╔══╝██║    ██║██║██╔════╝██║
 █████╗  ███████║███████╗   ██║   ██║ █╗ ██║██║█████╗  ██║
 ██╔══╝  ██╔══██║╚════██║   ██║   ██║███╗██║██║██╔══╝  ██║
 ██║     ██║  ██║███████║   ██║   ╚███╔███╔╝██║██║     ██║ 
 ╚═╝     ╚═╝  ╚═╝╚══════╝   ╚═╝    ╚══╝╚══╝ ╚═╝╚═╝     ╚═╝  
EOF
    echo -e "${NC}"
    echo -e "${YELLOW}Version ${VERSION} - The Ultimate Network Connection Manager${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

# Status Display
show_status() {
    INTERFACE=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2; exit}' | xargs)
    
    # WiFi Status
    wifi_ssid=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2)
    [ -n "$wifi_ssid" ] && wifi_status="${GREEN}📶 Connected: $wifi_ssid${NC}" || wifi_status="${RED}🔴 WiFi: Disconnected${NC}"
    
    # LAN Status
    if [ -n "$INTERFACE" ]; then
        lan_state=$(ip link show "$INTERFACE" 2>/dev/null | grep -o "state [A-Z]*" | awk '{print $2}')
        [ "$lan_state" = "UP" ] && lan_status="${GREEN}🔵 LAN: Active${NC}" || lan_status="${YELLOW}🟡 LAN: Inactive${NC}"
    else
        lan_status="${YELLOW}🟡 LAN: No Interface${NC}"
    fi
    
    # IP Addresses
    ipv4=$(ip -o -4 addr show | grep -v '127.0.0.1' | awk '{print $4}' | cut -d/ -f1 | head -n1)
    ipv6=$(ip -o -6 addr show | grep -v '::1' | awk '{print $4}' | head -n1)
    
    echo -e "\n${CYAN}=== Network Status ================================================${NC}"
    echo -e "| ${wifi_status}"
    echo -e "| ${lan_status}"
    echo -e "| ${YELLOW}IPv4: ${ipv4:-Not Available}${NC}"
    echo -e "| ${YELLOW}IPv6: ${ipv6:-Not Available}${NC}"
    echo -e "${CYAN}===================================================================${NC}\n"
}

# Dependency Management
install_dependency() {
    local dep=$1
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo -e "${YELLOW}Installing $dep...${NC}"
        if command -v pacman >/dev/null; then
            sudo pacman -S --noconfirm "$dep"
        elif command -v apt-get >/dev/null; then
            sudo apt-get install -y "$dep"
        else
            echo -e "${RED}Failed to install $dep - Unsupported package manager${NC}"
            return 1
        fi
    fi
}

# Log Management
rotate_logs() {
    [ -f "$LOG_FILE" ] && [ $(wc -l < "$LOG_FILE") -gt $MAX_LOG_LINES ] && 
    mv "$LOG_FILE" "$LOG_FILE.old"
}

# Initial Setup
init_setup() {
    mkdir -p "$LOG_DIR" "$CONFIG_DIR"
    touch "$LOG_FILE" "$SAVED_NETWORKS"
    rotate_logs
    INTERFACE=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2; exit}' | xargs)
}

# Logging System
log() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# Spinner Animation
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while [ -d /proc/$pid ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Input Validation
validate_number() {
    local input=$1
    local min=$2
    local max=$3
    [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge "$min" ] && [ "$input" -le "$max" ]
}

# Enhanced WiFi Scanner
scan_networks() {
    echo -e "\n${YELLOW}Scanning available networks...${NC}"
    (timeout 15s nmcli -f SSID,BARS,SECURITY,CHAN device wifi list --rescan yes 2>&1) > "$TMP_FILE" &
    spinner
    
    if grep -q "Error:" "$TMP_FILE"; then
        echo -e "${RED}Scan failed!${NC}"
        return 1
    fi

    echo -e "\n${CYAN}Available Networks:${NC}"
    column -t -s $'\t' "$TMP_FILE" | awk '{print "| " $0}'
    echo -e "${CYAN}===================================================================${NC}"
    log "Network scan completed"
}

# Connection with Retry Logic
connect_with_retry() {
    local SSID=$1
    local PASSWORD=$2
    local RETRIES=3
    
    for ((i=1; i<=RETRIES; i++)); do
        echo -e "\n${YELLOW}Attempt $i/$RETRIES...${NC}"
        if nmcli device wifi connect "$SSID" password "$PASSWORD"; then
            echo -e "${GREEN}"
            figlet -f small "Connected!"
            echo -e "${NC}"
            log "SUCCESS: Connected to $SSID"
            return 0
        fi
        sleep 2
    done
    
    echo -e "${RED}Connection failed after $RETRIES attempts${NC}"
    log "FAILURE: Could not connect to $SSID"
    return 1
}

# Connect WiFi
connect_wifi() {
    local SSID="" PASSWORD="" attempts=0 max_attempts=5
    
    while [ $attempts -lt $max_attempts ]; do
        read -p "Enter WiFi name (SSID) or 'q' to quit: " SSID
        [ "$SSID" == "q" ] && return
        
        if grep -q "^$SSID:" "$SAVED_NETWORKS"; then
            PASSWORD=$(grep "^$SSID:" "$SAVED_NETWORKS" | cut -d: -f2)
            echo -e "${GREEN}Using saved password${NC}"
            break
        fi
        
        while true; do
            read -sp "Enter password: " PASSWORD
            echo
            if [ ${#PASSWORD} -lt 8 ]; then
                echo -e "${RED}Password must be at least 8 characters!${NC}"
                ((attempts++))
                [ $attempts -ge $max_attempts ] && { 
                    echo -e "${RED}Max attempts reached!${NC}"
                    return 1
                }
            else
                break
            fi
        done
        
        break
    done
    
    connect_with_retry "$SSID" "$PASSWORD" && show_diagnostics
}

# LAN Management
manage_lan() {
    echo -e "\n${MAGENTA}=== LAN Management ===${NC}"
    
    INTERFACE=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2; exit}' | xargs)
    [ -z "$INTERFACE" ] && { echo -e "${RED}No LAN interface detected!${NC}"; return; }
    
    local CURRENT_STATE=$(ip link show "$INTERFACE" | grep -o "state [A-Z]*" | awk '{print $2}')
    echo -e "Interface: ${CYAN}$INTERFACE${NC}"
    echo -e "Current State: ${YELLOW}$CURRENT_STATE${NC}"
    
    echo "1. Enable LAN"
    echo "2. Disable LAN"
    echo "3. Refresh Status"
    read -p "Choose: " choice
    
    case $choice in
        1) 
            sudo ip link set "$INTERFACE" up
            echo -e "${GREEN}LAN enabled${NC}" ;;
        2) 
            sudo ip link set "$INTERFACE" down
            echo -e "${YELLOW}LAN disabled${NC}" ;;
        3)
            echo -e "New State: $(ip link show "$INTERFACE" | grep -o "state [A-Z]*")" ;;
        *) echo -e "${RED}Invalid option${NC}" ;;
    esac
}

# WiFi Adapter Control
manage_wifi_adapter() {
    echo -e "\n${CYAN}=== WiFi Adapter Control ===${NC}"
    
    local wifi_status=$(nmcli radio wifi)
    echo -e "Current Status: ${YELLOW}$wifi_status${NC}"
    
    echo "1. Enable WiFi"
    echo "2. Disable WiFi"
    echo "3. Restart Adapter"
    echo "4. Back to Menu"
    read -p "Choose: " choice
    
    case $choice in
        1) 
            nmcli radio wifi on
            echo -e "${GREEN}WiFi enabled${NC}" ;;
        2) 
            nmcli radio wifi off
            echo -e "${YELLOW}WiFi disabled${NC}" ;;
        3)
            sudo nmcli networking off && sudo nmcli networking on
            echo -e "${GREEN}Network services restarted${NC}" ;;
        4) return ;;
        *) echo -e "${RED}Invalid option${NC}" ;;
    esac
}

# MAC Filtering
mac_filtering() {
    echo -e "\n${CYAN}=== MAC Address Filtering ===${NC}"
    echo "1. Allow device"
    echo "2. Block device"
    read -p "Choose: " choice
    
    read -p "Enter MAC (AA:BB:CC:DD:EE:FF): " mac
    [[ ! "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] && { 
        echo -e "${RED}Invalid MAC format!${NC}"
        return
    }
    
    case $choice in
        1)
            sudo iptables -A INPUT -m mac --mac-source "$mac" -j ACCEPT
            echo -e "${GREEN}Allowed traffic from $mac${NC}" ;;
        2)
            sudo iptables -A INPUT -m mac --mac-source "$mac" -j DROP
            echo -e "${RED}Blocked traffic from $mac${NC}" ;;
        *) echo -e "${RED}Invalid option${NC}" ;;
    esac
}

# Network Diagnostics
show_diagnostics() {
    echo -e "\n${CYAN}=== Network Diagnostics ===${NC}"
    
    LOCAL_IP4=$(ip -o -4 addr show | grep -v '127.0.0.1' | awk '{print $4}' | cut -d/ -f1 | head -n1)
    LOCAL_IP6=$(ip -o -6 addr show | grep -v '::1' | awk '{print $4}' | head -n1)
    PUBLIC_IP=$(curl -4 -s ifconfig.me || echo "Not available")
    GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)
    DNS_SERVERS=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | paste -sd "," -)
    OPEN_PORTS=$(ss -tuln | awk 'NR>1 {print $5}' | cut -d: -f2 | sort -un | paste -sd "," -)
    
    printf "%-15s %s\n" "Local IPv4:" "$LOCAL_IP4"
    printf "%-15s %s\n" "Local IPv6:" "$LOCAL_IP6"
    printf "%-15s %s\n" "Public IP:" "$PUBLIC_IP"
    printf "%-15s %s\n" "Gateway:" "$GATEWAY"
    printf "%-15s %s\n" "DNS Servers:" "${DNS_SERVERS:-None}"
    printf "%-15s %s\n" "Open Ports:" "${OPEN_PORTS:-None}"
    
    echo -e "\n${YELLOW}Internet Connection:${NC}"
    if ping -c 2 -W 1 8.8.8.8 >/dev/null 2>&1; then
        local latency=$(ping -c 2 8.8.8.8 | tail -1 | awk '{print $4}' | cut -d'/' -f2)
        echo -e "${GREEN}✅ Connected (Latency: ${latency} ms)${NC}"
    else
        echo -e "${RED}❌ No connection${NC}"
    fi
}

# Saved Networks Manager
manage_saved_networks() {
    while true; do
        clear
        echo -e "${MAGENTA}=== Saved Networks ===${NC}"
        
        if [ ! -s "$SAVED_NETWORKS" ]; then
            echo -e "${YELLOW}No saved networks found${NC}"
        else
            echo -e "${CYAN}Saved Networks:${NC}"
            nl -w2 -s') ' "$SAVED_NETWORKS" | awk -F: '{print $1}'
        fi
        
        echo -e "\n${YELLOW}1. Connect to network"
        echo "2. Forget network"
        echo "3. Back to menu"
        read -p "Choose: " choice
        
        case $choice in
            1)
                if [ -s "$SAVED_NETWORKS" ]; then
                    read -p "Enter number: " num
                    SSID=$(sed -n "${num}p" "$SAVED_NETWORKS" | cut -d: -f1)
                    [ -n "$SSID" ] && connect_with_retry "$SSID" "$(grep "^$SSID:" "$SAVED_NETWORKS" | cut -d: -f2)"
                else
                    echo -e "${RED}No saved networks!${NC}"
                fi
                ;;
            2)
                read -p "Enter number to delete: " num
                SSID=$(sed -n "${num}p" "$SAVED_NETWORKS" | cut -d: -f1)
                if [ -n "$SSID" ]; then
                    sed -i "/^$SSID:/d" "$SAVED_NETWORKS"
                    echo -e "${GREEN}Deleted $SSID${NC}"
                else
                    echo -e "${RED}Invalid selection!${NC}"
                fi
                ;;
            3) break ;;
            *) echo -e "${RED}Invalid option!${NC}" ;;
        esac
        read -p "Press Enter..."
    done
}

# Network Cleanup
clean_orphaned_networks() {
    echo -e "\n${CYAN}=== Network Cleanup ===${NC}"
    
    sys_cons=$(nmcli -t -f NAME con show | grep -vFf <(awk -F: '{print $1}' "$SAVED_NETWORKS"))
    
    if [ -z "$sys_cons" ]; then
        echo -e "${GREEN}✅ No orphaned networks found${NC}"
        return
    fi
    
    echo -e "${YELLOW}Orphaned Networks:${NC}"
    mapfile -t networks <<< "$sys_cons"
    for i in "${!networks[@]}"; do 
        echo "$((i+1)). ${networks[$i]}"
    done
    
    read -p "Enter numbers to delete (space-separated): " nums
    for n in $nums; do
        index=$((n-1))
        if [ -n "${networks[$index]}" ]; then
            nmcli con delete "${networks[$index]}" >/dev/null
            echo -e "${RED}🗑 Deleted: ${networks[$index]}${NC}"
        fi
    done
}

# Connection History
show_connection_history() {
    echo -e "\n${CYAN}=== Connection History ===${NC}"
    tail -10 "$LOG_FILE" | awk '
    BEGIN {print "Last 10 connections:"}
    /SUCCESS/ {printf "🟩"; count++}
    /FAILURE/ {printf "🟥"; count++} 
    END {if(count==0) print "No recent history"; else printf "\n"}'
}

# Bandwidth Monitor
show_bandwidth() {
    echo -e "\n${CYAN}=== Bandwidth Monitor ===${NC}"
    
    if ! command -v iftop >/dev/null; then
        echo -e "${YELLOW}Installing iftop...${NC}"
        install_dependency iftop || return
    fi
    
    local iface=$(ip route | grep default | awk '{print $5}')
    [ -z "$iface" ] && { echo -e "${RED}No active interface!${NC}"; return; }
    
    echo -e "Monitoring: ${YELLOW}$iface${NC}"
    sudo iftop -i "$iface"
}

# QR Generator
generate_qr() {
    if ! command -v qrencode >/dev/null; then
        echo -e "${YELLOW}Installing qrencode...${NC}"
        install_dependency qrencode || return
    fi
    
    local SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2)
    [ -z "$SSID" ] && { echo -e "${RED}Not connected to WiFi!${NC}"; return; }
    
    local PASS=$(grep "^$SSID:" "$SAVED_NETWORKS" | cut -d: -f2)
    [ -z "$PASS" ] && { echo -e "${RED}Password not saved!${NC}"; return; }
    
    echo -e "\n${CYAN}QR Code for $SSID:${NC}"
    qrencode -t ANSIUTF8 "WIFI:S:$SSID;T:WPA;P:$PASS;;"
}

# View Logs
view_logs() {
    echo -e "\n${CYAN}=== Connection Logs ===${NC}"
    if [ -s "$LOG_FILE" ]; then
        less "$LOG_FILE"
    else
        echo -e "${YELLOW}No logs found${NC}"
    fi
}

# Main Menu
main_menu() {
    while true; do
        clear
        show_banner
        show_status
        echo -e "${CYAN}=== Main Menu ===================================================${NC}"
        echo "1. WiFi Operations        4. Advanced Tools"
        echo "2. LAN Operations         5. Exit"
        echo "3. Diagnostics & Monitoring"
        echo -e "${CYAN}===================================================================${NC}"
        read -p "Choose (1-5): " choice
        
        case $choice in
            1) wifi_operations ;;
            2) lan_operations ;;
            3) diagnostics_menu ;;
            4) advanced_tools ;;
            5) 
                echo -e "${GREEN}Exiting...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option!${NC}"
                ;;
        esac
    done
}

# Submenu: WiFi Operations
wifi_operations() {
    while true; do
        clear
        show_banner
        show_status
        echo -e "${CYAN}=== WiFi Operations ===${NC}"
        echo "1. Scan Networks"
        echo "2. Connect to New Network"
        echo "3. Manage Saved Networks"
        echo "4. Signal Monitor"
        echo "5. Clean Orphaned Networks"
        echo "6. Back to Main Menu"
        read -p "Choose (1-6): " choice
        
        case $choice in
            1) scan_networks ;;
            2) connect_wifi ;;
            3) manage_saved_networks ;;
            4) monitor_signal ;;
            5) clean_orphaned_networks ;;
            6) break ;;
            *) echo -e "${RED}Invalid option!${NC}" ;;
        esac
        read -p "Press Enter..."
    done
}

# Submenu: LAN Operations
lan_operations() {
    while true; do
        clear
        show_banner
        show_status
        echo -e "${CYAN}=== LAN Operations ===${NC}"
        echo "1. Enable LAN"
        echo "2. Disable LAN"
        echo "3. Show LAN Info"
        echo "4. Back to Main Menu"
        read -p "Choose (1-4): " choice
        
        case $choice in
            1|2) manage_lan $choice ;;
            3) manage_lan 3 ;;
            4) break ;;
            *) echo -e "${RED}Invalid option!${NC}" ;;
        esac
        read -p "Press Enter..."
    done
}

# Submenu: Diagnostics
diagnostics_menu() {
    while true; do
        clear
        show_banner
        show_status
        echo -e "${CYAN}=== Diagnostics & Monitoring ===${NC}"
        echo "1. Network Diagnostics"
        echo "2. Bandwidth Monitor"
        echo "3. Connection History"
        echo "4. Run Troubleshooter"
        echo "5. Back to Main Menu"
        read -p "Choose (1-5): " choice
        
        case $choice in
            1) show_diagnostics ;;
            2) show_bandwidth ;;
            3) show_connection_history ;;
            4) run_troubleshooter ;;
            5) break ;;
            *) echo -e "${RED}Invalid option!${NC}" ;;
        esac
        read -p "Press Enter..."
    done
}

# Submenu: Advanced Tools
advanced_tools() {
    while true; do
        clear
        show_banner
        show_status
        echo -e "${CYAN}=== Advanced Tools ===${NC}"
        echo "1. MAC Filtering"
        echo "2. WiFi Adapter Control"
        echo "3. Generate QR Code"
        echo "4. View Logs"
        echo "5. Back to Main Menu"
        read -p "Choose (1-5): " choice
        
        case $choice in
            1) mac_filtering ;;
            2) manage_wifi_adapter ;;
            3) generate_qr ;;
            4) view_logs ;;
            5) break ;;
            *) echo -e "${RED}Invalid option!${NC}" ;;
        esac
        read -p "Press Enter..."
    done
}

# Cleanup
cleanup() {
    rm -f "$TMP_FILE"
    log "Script session ended"
}

# Initialize
trap cleanup EXIT
init_setup

# Check and install dependencies
for dep in "${DEPENDENCIES[@]}" qrencode iftop; do
    install_dependency "$dep" || exit 1
done

log "Script started - version $VERSION"
main_menu
