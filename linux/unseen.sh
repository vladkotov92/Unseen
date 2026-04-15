#!/bin/bash

# ANSI color codes
RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[92m"
YELLOW="\033[93m"
RED="\033[91m"

KILL_SWITCH=0
TOR_SYS_USER=""

# Display banner
display_banner() {
    clear
    printf "${GREEN}${BOLD}"
    cat << "EOF"

  _    _ _   _  _____ ______ ______ _   _ 
 | |  | | \ | |/ ____|  ____|  ____| \ | |
 | |  | |  \| | (___ | |__  | |__  |  \| |
 | |  | | . ` |\___ \|  __| |  __| | . ` |
 | |__| | |\  |____) | |____| |____| |\  |
  \____/|_| \_|_____/|______|______|_| \_|

                  Developer: A Russian Boy

EOF
    printf "${RESET}${YELLOW}* GitHub: https://github.com/vladkotov92${RESET}\n\n"
}

# Check running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        printf "${RED}[!] Please run as root: sudo bash unseen.sh${RESET}\n"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    for cmd in tor jq curl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            printf "${RED}[!] '$cmd' not found. Run: bash install.sh${RESET}\n"
            exit 1
        fi
    done
}

# Detect desktop environment
detect_de() {
    if [ -n "$GNOME_DESKTOP_SESSION_ID" ] || [ "$XDG_CURRENT_DESKTOP" = "GNOME" ]; then
        echo "gnome"
    elif [ "$XDG_CURRENT_DESKTOP" = "KDE" ]; then
        echo "kde"
    else
        echo "other"
    fi
}

# Enable SOCKS proxy
set_proxy() {
    printf "${YELLOW}[+] Enabling SOCKS proxy...${RESET}\n"
    DE=$(detect_de)
    REAL_USER=${SUDO_USER:-$USER}

    case "$DE" in
        gnome)
            sudo -u "$REAL_USER" gsettings set org.gnome.system.proxy mode 'manual' 2>/dev/null
            sudo -u "$REAL_USER" gsettings set org.gnome.system.proxy.socks host '127.0.0.1' 2>/dev/null
            sudo -u "$REAL_USER" gsettings set org.gnome.system.proxy.socks port 9050 2>/dev/null
            printf "${GREEN}[+] GNOME proxy set.${RESET}\n"
            ;;
        kde)
            kwriteconfig5 --file kioslaverc --group "Proxy Settings" --key ProxyType 1 2>/dev/null
            kwriteconfig5 --file kioslaverc --group "Proxy Settings" --key socksProxy "socks://127.0.0.1:9050" 2>/dev/null
            printf "${GREEN}[+] KDE proxy set.${RESET}\n"
            ;;
        *)
            export ALL_PROXY="socks5://127.0.0.1:9050"
            export http_proxy="socks5://127.0.0.1:9050"
            export https_proxy="socks5://127.0.0.1:9050"
            printf "${YELLOW}[+] Proxy set via environment variables.${RESET}\n"
            ;;
    esac
}

# Disable SOCKS proxy
reset_proxy() {
    printf "${YELLOW}[+] Disabling SOCKS proxy...${RESET}\n"
    DE=$(detect_de)
    REAL_USER=${SUDO_USER:-$USER}

    case "$DE" in
        gnome)
            sudo -u "$REAL_USER" gsettings set org.gnome.system.proxy mode 'none' 2>/dev/null
            printf "${GREEN}[+] GNOME proxy reset.${RESET}\n"
            ;;
        kde)
            kwriteconfig5 --file kioslaverc --group "Proxy Settings" --key ProxyType 0 2>/dev/null
            printf "${GREEN}[+] KDE proxy reset.${RESET}\n"
            ;;
        *)
            unset ALL_PROXY http_proxy https_proxy
            printf "${GREEN}[+] Environment proxy variables cleared.${RESET}\n"
            ;;
    esac
}

# Ask user for exit node
choose_exit_node() {
    printf "${YELLOW}[+] Exit node country (e.g. US, DE, NL, FR, IT)${RESET}\n"
    printf "${YELLOW}    Press ENTER to let Tor choose automatically: ${RESET}"
    read -r EXIT_NODE

    rm -f /tmp/torrc

    if [ -z "$EXIT_NODE" ]; then
        printf "${GREEN}[+] Using automatic exit node.${RESET}\n"
        EXIT_NODE=""
    else
        EXIT_NODE=$(echo "$EXIT_NODE" | tr '[:lower:]' '[:upper:]')
        printf "${GREEN}[+] Exit node set to: ${EXIT_NODE}${RESET}\n"
        cat > /tmp/torrc << EOF
SocksPort 9050
ExitNodes {${EXIT_NODE}}
StrictNodes 1
GeoIPExcludeUnknown 1
EOF
    fi
}

# Handle exit node mismatch
handle_exit_node_error() {
    printf "\n"
    printf "${YELLOW}[?] What do you want to do?${RESET}\n"
    printf "    ${BOLD}1)${RESET} Choose a different country\n"
    printf "    ${BOLD}2)${RESET} Let Tor choose automatically\n"
    printf "${YELLOW}    Choice [1/2]: ${RESET}"
    read -r CHOICE

    case "$CHOICE" in
        1)
            choose_exit_node
            start_tor
            set_proxy
            fetch_info
            ;;
        2)
            printf "${GREEN}[+] Using automatic exit node.${RESET}\n"
            rm -f /tmp/torrc
            EXIT_NODE=""
            start_tor
            set_proxy
            fetch_info
            ;;
        *)
            printf "${RED}[!] Invalid choice. Exiting.${RESET}\n"
            exit 1
            ;;
    esac
}

# Detect dedicated Tor system user (needed for kill switch isolation)
detect_tor_user() {
    for u in debian-tor tor _tor; do
        if id "$u" >/dev/null 2>&1; then
            TOR_SYS_USER="$u"
            return 0
        fi
    done
    TOR_SYS_USER=""
    return 1
}

# Start Tor
start_tor() {
    printf "${YELLOW}[+] Starting Tor...${RESET}\n"

    systemctl stop tor 2>/dev/null
    pkill -x tor 2>/dev/null
    sleep 1

    detect_tor_user

    rm -f /tmp/tor.log
    if [ -n "$TOR_SYS_USER" ]; then
        [ -f /tmp/torrc ] && chmod 644 /tmp/torrc
        if [ -f /tmp/torrc ]; then
            sudo -u "$TOR_SYS_USER" tor -f /tmp/torrc --Log "notice file /tmp/tor.log" >/dev/null 2>&1 &
        else
            sudo -u "$TOR_SYS_USER" tor --Log "notice file /tmp/tor.log" >/dev/null 2>&1 &
        fi
    else
        if [ -f /tmp/torrc ]; then
            tor -f /tmp/torrc > /tmp/tor.log 2>&1 &
        else
            tor > /tmp/tor.log 2>&1 &
        fi
    fi

    printf "${YELLOW}[+] Waiting for bootstrap${RESET}"
    for i in $(seq 1 60); do
        sleep 2
        if grep -q "Bootstrapped 100%" /tmp/tor.log 2>/dev/null; then
            printf "\n${GREEN}[+] Tor is ready!${RESET}\n"
            return 0
        fi
        printf "."
    done

    printf "\n${RED}[!] Bootstrap failed. Check: cat /tmp/tor.log${RESET}\n"
    exit 1
}

# Stop Tor
stop_tor() {
    pkill -x tor 2>/dev/null
    sleep 1
}

# Monitor Tor process and alert if it drops
MONITOR_PID=""
monitor_tor() {
    while true; do
        sleep 5
        if ! pgrep -x tor >/dev/null 2>&1; then
            printf "\n${RED}[!] Tor has dropped!${RESET}\n"
            [ "$KILL_SWITCH" -eq 1 ] && printf "${RED}[!] Kill Switch active — all traffic is blocked.${RESET}\n"
            break
        fi
    done
}

# Fetch IP and location through Tor
fetch_info() {
    printf "${YELLOW}[+] Fetching connection info...${RESET}\n\n"

    LOCATION=$(curl -s \
        --socks5 127.0.0.1:9050 \
        --socks5-hostname 127.0.0.1:9050 \
        --max-time 20 \
        "http://ip-api.com/json/")

    IP=$(echo "$LOCATION"           | jq -r '.query')
    COUNTRY=$(echo "$LOCATION"      | jq -r '.country')
    COUNTRY_CODE=$(echo "$LOCATION" | jq -r '.countryCode')
    REGION=$(echo "$LOCATION"       | jq -r '.regionName')
    CITY=$(echo "$LOCATION"         | jq -r '.city')

    if [ -z "$IP" ] || [ "$IP" = "null" ]; then
        printf "${RED}[!] Could not fetch info.${RESET}\n"
        exit 1
    fi

    # Verify exit country matches requested one
    if [ -n "$EXIT_NODE" ] && [ "$COUNTRY_CODE" != "$EXIT_NODE" ]; then
        printf "${RED}[!] Tor ignored StrictNodes: got ${COUNTRY_CODE} instead of ${EXIT_NODE}${RESET}\n"
        pkill -x tor 2>/dev/null
        sleep 1
        handle_exit_node_error
        return
    fi

    printf "${GREEN}${BOLD}Connection active${RESET}\n"
    printf "${GREEN}──────────────────────${RESET}\n"
    printf "${BOLD}IP:${RESET}      ${GREEN}${IP}${RESET}\n"
    printf "${BOLD}Country:${RESET} ${GREEN}${COUNTRY}${RESET}\n"
    printf "${BOLD}Region:${RESET}  ${GREEN}${REGION}${RESET}\n"
    printf "${BOLD}City:${RESET}    ${GREEN}${CITY}${RESET}\n"
    printf "${GREEN}──────────────────────${RESET}\n\n"
    printf "${YELLOW}Press CTRL+C to disconnect  |  CTRL+R to restart${RESET}\n"
}

# Full restart — clean up and re-run the script from scratch
restart_program() {
    printf "\n${YELLOW}[~] Restarting...${RESET}\n"
    [ -n "$MONITOR_PID" ] && kill "$MONITOR_PID" 2>/dev/null
    [ "$KILL_SWITCH" -eq 1 ] && kill_switch_disable
    reset_proxy
    stop_tor
    exec bash "$0"
}

# Change Tor identity
change_identity() {
    printf "${YELLOW}[~] Changing identity...${RESET}\n"
    sudo systemctl reload tor 2>/dev/null || sudo service tor reload 2>/dev/null || pkill -HUP -x tor 2>/dev/null
    sleep 3
    printf "${YELLOW}[~] Identity changed.${RESET}\n"
}

# Ask user whether to enable Kill Switch
choose_kill_switch() {
    printf "${YELLOW}[?] Enable Kill Switch? (blocks all traffic if Tor drops) [y/n]: ${RESET}"
    read -r KS_CHOICE
    KS_CHOICE=$(echo "$KS_CHOICE" | tr '[:upper:]' '[:lower:]')
    if [ "$KS_CHOICE" = "y" ]; then
        KILL_SWITCH=1
        printf "${GREEN}[+] Kill Switch will be enabled.${RESET}\n"
    else
        KILL_SWITCH=0
    fi
}

# Enable Kill Switch via iptables
kill_switch_enable() {
    printf "${YELLOW}[+] Enabling Kill Switch...${RESET}\n"
    if [ -z "$TOR_SYS_USER" ]; then
        printf "${RED}[!] No dedicated Tor system user found (debian-tor/tor/_tor).${RESET}\n"
        printf "${RED}[!] Kill Switch cannot isolate Tor traffic safely — skipping.${RESET}\n"
        KILL_SWITCH=0
        return 1
    fi
    iptables -N UNSEEN_KS 2>/dev/null
    iptables -F UNSEEN_KS 2>/dev/null
    # Allow loopback (covers SOCKS proxy on 127.0.0.1:9050)
    iptables -A UNSEEN_KS -o lo -j ACCEPT
    # Allow Tor's own outbound traffic (connects to Tor relays)
    iptables -A UNSEEN_KS -m owner --uid-owner "$TOR_SYS_USER" -j ACCEPT
    # Block everything else
    iptables -A UNSEEN_KS -j DROP
    iptables -I OUTPUT -j UNSEEN_KS
    printf "${GREEN}[+] Kill Switch enabled. All traffic is blocked except through Tor (${TOR_SYS_USER}).${RESET}\n"
}

# Disable Kill Switch
kill_switch_disable() {
    iptables -D OUTPUT -j UNSEEN_KS 2>/dev/null
    iptables -F UNSEEN_KS 2>/dev/null
    iptables -X UNSEEN_KS 2>/dev/null
}

# Ask user whether to enable IP rotation
choose_rotation() {
    printf "${YELLOW}[?] Enable IP rotation? [y/n]: ${RESET}"
    read -r ROTATE_IP
    ROTATE_IP=$(echo "$ROTATE_IP" | tr '[:upper:]' '[:lower:]')

    if [ "$ROTATE_IP" = "y" ]; then
        printf "${YELLOW}[?] Rotate every how many seconds? (min 10): ${RESET}"
        read -r ROTATE_INTERVAL
        if ! echo "$ROTATE_INTERVAL" | grep -qE '^[0-9]+$' || [ "$ROTATE_INTERVAL" -lt 10 ]; then
            printf "${RED}[!] Invalid interval. Using 60 seconds.${RESET}\n"
            ROTATE_INTERVAL=60
        fi
        printf "${GREEN}[+] IP will rotate every ${ROTATE_INTERVAL} seconds.${RESET}\n"
    fi
}

# Cleanup on exit
cleanup() {
    printf "\n${RED}[!] Disconnecting...${RESET}\n"
    [ -n "$MONITOR_PID" ] && kill "$MONITOR_PID" 2>/dev/null
    [ "$KILL_SWITCH" -eq 1 ] && kill_switch_disable
    reset_proxy
    stop_tor
    printf "${GREEN}[+] Done. Goodbye.${RESET}\n"
    exit 0
}

trap cleanup INT TERM

main() {
    display_banner
    check_root
    check_dependencies
    kill_switch_disable
    choose_rotation
    choose_kill_switch
    if [ "$ROTATE_IP" = "y" ]; then
        rm -f /tmp/torrc
    else
        choose_exit_node
    fi
    start_tor
    set_proxy
    [ "$KILL_SWITCH" -eq 1 ] && kill_switch_enable
    fetch_info
    monitor_tor &
    MONITOR_PID=$!

    if [ "$ROTATE_IP" = "y" ]; then
        while true; do
            elapsed=0
            while [ "$elapsed" -lt "$ROTATE_INTERVAL" ]; do
                if read -r -t 1 -n 1 key 2>/dev/null && [ "$key" = $'\x12' ]; then
                    restart_program
                fi
                elapsed=$((elapsed + 1))
            done
            change_identity
            fetch_info
        done
    else
        while true; do
            if read -r -t 1 -n 1 key 2>/dev/null && [ "$key" = $'\x12' ]; then
                restart_program
            fi
        done
    fi
}

main