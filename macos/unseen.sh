#!/bin/bash

# ANSI color codes
RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[92m"
YELLOW="\033[93m"
RED="\033[91m"

KILL_SWITCH=0
MONITOR_PID=""
DNS_PROTECTED=0

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

# Check dependencies
check_dependencies() {
    if ! command -v tor >/dev/null 2>&1; then
        printf "${RED}[!] Tor not found. Install it with: brew install tor${RESET}\n"
        exit 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        printf "${RED}[!] jq not found. Install it with: brew install jq${RESET}\n"
        exit 1
    fi
}

# Enable SOCKS proxy on all interfaces
set_proxy() {
    printf "${YELLOW}[+] Enabling SOCKS proxy...${RESET}\n"
    while IFS= read -r service; do
        networksetup -setsocksfirewallproxy "$service" "127.0.0.1" "9050" off 2>/dev/null
        networksetup -setsocksfirewallproxystate "$service" on 2>/dev/null
    done <<< "$(networksetup -listallnetworkservices 2>/dev/null | grep -v '^\*' | tail -n +2)"
}

# Disable SOCKS proxy on all interfaces
reset_proxy() {
    printf "${YELLOW}[+] Disabling SOCKS proxy...${RESET}\n"
    while IFS= read -r service; do
        networksetup -setsocksfirewallproxystate "$service" off 2>/dev/null
    done <<< "$(networksetup -listallnetworkservices 2>/dev/null | grep -v '^\*' | tail -n +2)"
}

# Start Tor
start_tor() {
    printf "${YELLOW}[+] Starting Tor...${RESET}\n"

    brew services stop tor 2>/dev/null
    pkill -x tor 2>/dev/null
    sleep 1

    if [ -f /tmp/torrc ]; then
        tor -f /tmp/torrc > /tmp/tor.log 2>&1 &
    else
        tor > /tmp/tor.log 2>&1 &
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

# Ask user for exit node
choose_exit_node() {
    printf "${YELLOW}[+] Exit node country (e.g. US, DE, NL, FR, IT)${RESET}\n"
    printf "${YELLOW}    Press ENTER to let Tor choose automatically: ${RESET}"
    read -r EXIT_NODE

    rm -f /tmp/torrc

    if [ -z "$EXIT_NODE" ]; then
        printf "${GREEN}[+] Using automatic exit node.${RESET}\n"
        EXIT_NODE=""
        cat > /tmp/torrc << EOF
SocksPort 9050
DNSPort 9053
AutomapHostsOnResolve 1
EOF
    else
        EXIT_NODE=$(echo "$EXIT_NODE" | tr '[:lower:]' '[:upper:]')
        printf "${GREEN}[+] Exit node set to: ${EXIT_NODE}${RESET}\n"
        cat > /tmp/torrc << EOF
SocksPort 9050
DNSPort 9053
AutomapHostsOnResolve 1
ExitNodes {${EXIT_NODE}}
StrictNodes 1
GeoIPExcludeUnknown 1
EOF
    fi
}

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
            EXIT_NODE=""
            cat > /tmp/torrc << EOF
SocksPort 9050
DNSPort 9053
AutomapHostsOnResolve 1
EOF
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

# Fetch IP and location through Tor
fetch_info() {
    printf "${YELLOW}[+] Fetching connection info...${RESET}\n\n"

    LOCATION=$(curl -s \
        --socks5 127.0.0.1:9050 \
        --socks5-hostname 127.0.0.1:9050 \
        --max-time 20 \
        "http://ip-api.com/json/")

    IP=$(echo "$LOCATION"      | jq -r '.query')
    COUNTRY=$(echo "$LOCATION" | jq -r '.country')
    COUNTRY_CODE=$(echo "$LOCATION" | jq -r '.countryCode')
    REGION=$(echo "$LOCATION"  | jq -r '.regionName')
    CITY=$(echo "$LOCATION"    | jq -r '.city')

    if [ -z "$IP" ] || [ "$IP" = "null" ]; then
        printf "${RED}[!] Could not fetch info.${RESET}\n"
        exit 1
    fi

    # Verifica che il paese corrisponda a quello richiesto
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
    printf "${YELLOW}Press CTRL+C to disconnect${RESET}\n"
}
# Change Tor identity
change_identity() {
    printf "${YELLOW}[~] Changing identity...${RESET}\n"
    pkill -HUP -x tor 2>/dev/null
    sleep 3
    printf "${YELLOW}[~] Identity changed.${RESET}\n"
}

# Ask user whether to enable Kill Switch
choose_kill_switch() {
    printf "${YELLOW}[?] Enable Kill Switch? (disconnects immediately if Tor drops) [y/n]: ${RESET}"
    read -r KS_CHOICE
    KS_CHOICE=$(echo "$KS_CHOICE" | tr '[:upper:]' '[:lower:]')
    if [ "$KS_CHOICE" = "y" ]; then
        KILL_SWITCH=1
        printf "${GREEN}[+] Kill Switch will be enabled.${RESET}\n"
    else
        KILL_SWITCH=0
    fi
}

# Monitor Tor process and trigger cleanup if it dies
kill_switch_monitor() {
    while true; do
        sleep 5
        if ! pgrep -x tor > /dev/null; then
            printf "\n${RED}[!] Tor process died — Kill Switch activated!${RESET}\n"
            cleanup
        fi
    done &
    MONITOR_PID=$!
}

# Enable DNS leak protection — route system DNS through Tor
dns_protect_enable() {
    printf "${YELLOW}[+] Enabling DNS leak protection...${RESET}\n"
    : > /tmp/dns_backup.txt
    while IFS= read -r service; do
        [ -z "$service" ] && continue
        current_dns=$(networksetup -getdnsservers "$service" 2>/dev/null)
        if echo "$current_dns" | grep -q "There aren't"; then
            echo "${service}|EMPTY" >> /tmp/dns_backup.txt
        else
            dns_line=$(echo "$current_dns" | tr '\n' ' ')
            echo "${service}|${dns_line}" >> /tmp/dns_backup.txt
        fi
        networksetup -setdnsservers "$service" "127.0.0.1" 2>/dev/null
    done <<< "$(networksetup -listallnetworkservices 2>/dev/null | grep -v '^\*' | tail -n +2)"
    DNS_PROTECTED=1
    printf "${GREEN}[+] DNS leak protection active.${RESET}\n"
}

# Disable DNS leak protection — restore original DNS
dns_protect_disable() {
    if [ "$DNS_PROTECTED" -eq 1 ] && [ -f /tmp/dns_backup.txt ]; then
        while IFS='|' read -r service dns_list; do
            [ -z "$service" ] && continue
            if [ "$dns_list" = "EMPTY" ] || [ -z "$dns_list" ]; then
                networksetup -setdnsservers "$service" "Empty" 2>/dev/null
            else
                networksetup -setdnsservers "$service" $dns_list 2>/dev/null
            fi
        done < /tmp/dns_backup.txt
        rm -f /tmp/dns_backup.txt
        DNS_PROTECTED=0
    fi
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
    dns_protect_disable
    reset_proxy
    stop_tor
    printf "${GREEN}[+] Done. Goodbye.${RESET}\n"
    exit 0
}

trap cleanup INT TERM

main() {
    display_banner
    check_dependencies
    choose_rotation
    choose_kill_switch
    if [ "$ROTATE_IP" = "y" ]; then
        cat > /tmp/torrc << EOF
SocksPort 9050
DNSPort 9053
AutomapHostsOnResolve 1
EOF
    else
        choose_exit_node
    fi
    start_tor
    set_proxy
    dns_protect_enable
    [ "$KILL_SWITCH" -eq 1 ] && kill_switch_monitor
    fetch_info

    if [ "$ROTATE_IP" = "y" ]; then
        while true; do
            sleep "$ROTATE_INTERVAL"
            change_identity
            fetch_info
        done
    else
        while true; do sleep 1; done
    fi
}

main