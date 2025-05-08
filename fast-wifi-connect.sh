#!/bin/bash

# Configuration
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/wifi-connection.log"
TMP_FILE="/tmp/network_temp"
VERSION="1.0"
AUTHOR="Your Name"

# ASCII Art
show_banner() {
    echo -e "\e[34m"
    echo " ███████╗ █████╗ ███████╗████████╗██╗    ██╗██╗███████╗██╗"
    echo " ██╔════╝██╔══██╗██╔════╝╚══██╔══╝██║    ██║██║██╔════╝██║"
    echo " █████╗  ███████║███████╗   ██║   ██║ █╗ ██║██║█████╗  ██║"
    echo " ██╔══╝  ██╔══██║╚════██║   ██║   ██║███╗██║██║██╔══╝  ██║"
    echo " ██║     ██║  ██║███████║   ██║   ╚███╔███╔╝██║███████╗███████╗"
    echo " ╚═╝     ╚═╝  ╚═╝╚══════╝   ╚═╝    ╚══╝╚══╝ ╚═╝╚══════╝╚══════╝"
    echo -e "\e[0m"
}

# Initial Setup
init_logs() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
}

# Logging System
log() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# Network Scanner
scan_networks() {
    echo -e "\n\e[33mScanning available networks...\e[0m"
    nmcli device wifi list --rescan yes > "$TMP_FILE"
    awk -F'  +' '{printf "%-30s %-15s %-10s %-10s\n", $2, $7, $8, $6}' "$TMP_FILE" | column -t
}

# Connection Manager
connect_wifi() {
    read -p "Enter WiFi name: " SSID
    read -sp "Enter password: " PASSWORD
    echo -e "\n\e[33mAttempting connection...\e[0m"
    
    if nmcli device wifi connect "$SSID" password "$PASSWORD"; then
        echo -e "\e[32m"
        figlet "Connected to $SSID"
        echo -e "\e[0m"
        log "SUCCESS: Connected to $SSID"
        return 0
    else
        echo -e "\e[31mConnection failed!\e[0m"
        log "FAILURE: Connection attempt to $SSID"
        return 1
    fi
}

# Network Diagnostics
show_diagnostics() {
    local IP_ADDR=$(hostname -I | awk '{print $1}')
    local PUBLIC_IP=$(curl -s ifconfig.me)
    
    echo -e "\n\e[36m=== Network Diagnostics ===\e[0m"
    echo -e "Local IP:\t $IP_ADDR"
    echo -e "Public IP:\t $PUBLIC_IP"
    echo -e "Open Ports:\t $(ss -tulpn | grep LISTEN | wc -l)"
    echo -e "Gateway:\t $(ip route | grep default | awk '{print $3}')"
    echo -e "DNS Servers:\t $(grep nameserver /etc/resolv.conf | awk '{print $2}')"
    
    log "Diagnostics - Local: $IP_ADDR, Public: $PUBLIC_IP"
}

# LAN Manager
manage_lan() {
    echo -e "\n\e[35m=== LAN Management ===\e[0m"
    local INTERFACE=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2}')
    
    echo "1. Enable LAN"
    echo "2. Disable LAN"
    read -p "Choose option: " CHOICE
    
    case $CHOICE in
        1) sudo ip link set $INTERFACE up
           echo "LAN enabled" ;;
        2) sudo ip link set $INTERFACE down
           echo "LAN disabled" ;;
        *) echo "Invalid option" ;;
    esac
}

# Main Menu
main_menu() {
    clear
    show_banner
    PS3=$'\n\e[32mChoose an option: \e[0m'
    
    select option in "Scan Networks" "Connect WiFi" "LAN Options" "Show Diagnostics" "View Logs" "Exit"; do
        case $REPLY in
            1) scan_networks ;;
            2) connect_wifi && show_diagnostics ;;
            3) manage_lan ;;
            4) show_diagnostics ;;
            5) less "$LOG_FILE" ;;
            6) exit 0 ;;
            *) echo "Invalid option" ;;
        esac
    done
}

# Initial Checks
check_dependencies() {
    command -v nmcli >/dev/null 2>&1 || {
        echo -e "\e[31mNetworkManager is required but not installed!\e[0m"
        exit 1
    }
    
    command -v figlet >/dev/null 2>&1 || {
        echo "Note: Install 'figlet' for better banner display"
    }
}

# Execution Flow
init_logs
check_dependencies
main_menu
