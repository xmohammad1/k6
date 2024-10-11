#!/bin/bash

# Color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color
logo() {
    echo -e "${CYAN}*****************************************${NC}"
    echo -e "${CYAN}*${NC}                                       ${CYAN}*${NC}"
    echo -e "${CYAN}*${NC}          ${GREEN}M U H A M M A D${NC}              ${CYAN}*${NC}"
    echo -e "${CYAN}*${NC}                                       ${CYAN}*${NC}"
    echo -e "${CYAN}*****************************************${NC}"
}
# Function to display spinner
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}
# Function to install K6 if not installed
install_k6_if_needed() {
    if ! command -v k6 &> /dev/null; then
        echo -e "${YELLOW}K6 is not installed. Installing K6...${NC}"
        (
            sudo gpg -k > /dev/null 2>&1
            sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69 > /dev/null 2>&1
            echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list > /dev/null
            sudo apt-get update > /dev/null 2>&1
            sudo apt-get install k6 -y > /dev/null 2>&1
        ) &
        spinner $!
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error: Failed to install K6. Please install it manually and try again.${NC}"
            exit 1
        fi
        echo -e "${GREEN}K6 installed successfully.${NC}"
    fi
}
# Function to validate if a number is an integer
validate_integer() {
    if ! [[ "$1" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: '$1' is not a valid number.${NC}"
        return 1
    fi
    return 0
}
# Function to validate duration format
validate_duration() {
    if ! [[ "$1" =~ ^[0-9]+(s|m|h|d)$ ]]; then
        echo -e "${RED}Error: '$1' is not a valid duration. Use formats like 30s, 1m, 2h, or 1d.${NC}"
        return 1
    fi
    return 0
}
# Function to validate URL
validate_url() {
    if ! [[ "$1" =~ ^http(s)?:// ]]; then
        echo -e "${RED}Error: '$1' is not a valid URL. It must start with http:// or https://.${NC}"
        return 1
    fi
    return 0
}
# Function to validate if a service exists
service_exists() {
    if systemctl status "$1.service" &> /dev/null; then
        return 0
    else
        echo -e "${RED}Service '$1' does not exist.${NC}"
        return 1
    fi
}
# Function to check if input contains spaces
validate_no_spaces() {
    if [[ "$1" =~ [[:space:]] ]]; then
        echo -e "${RED}Error: Input cannot contain spaces.${NC}"
        return 1
    fi
    return 0
}
# Function to convert duration to seconds
duration_to_seconds() {
    local duration=$1
    local seconds=0
    if [[ $duration =~ ([0-9]+)s ]]; then
        seconds=$((seconds + ${BASH_REMATCH[1]}))
    fi
    if [[ $duration =~ ([0-9]+)m ]]; then
        seconds=$((seconds + ${BASH_REMATCH[1]} * 60))
    fi
    if [[ $duration =~ ([0-9]+)h ]]; then
        seconds=$((seconds + ${BASH_REMATCH[1]} * 3600))
    fi
    if [[ $duration =~ ([0-9]+)d ]]; then
        seconds=$((seconds + ${BASH_REMATCH[1]} * 86400))
    fi
    echo $seconds
}
# Function to create and modify K6 processes
create_k6_script_and_service() {
    # Install K6 if not already installed
    install_k6_if_needed
    # Ask user for inputs with validation
    echo -e "${BLUE}=== Create New K6 Load Test ===${NC}\n"
    while true; do
        echo -ne "Enter ${BOLD}Number${NC} of Virtual Users: "
        read vus
        if ! validate_no_spaces "$vus"; then
            continue
        fi
        validate_integer $vus && break
    done

    while true; do
        echo -ne "Enter ${BOLD}Duration${NC} (e.g. 1m, 1h, 1d): "
        read duration
        if ! validate_no_spaces "$duration"; then
            continue
        fi
        validate_duration $duration && break
    done

    while true; do
        echo -ne "Enter target ${BOLD}URL${NC}: "
        read url
        if ! validate_no_spaces "$url"; then
            continue
        fi
        validate_url $url && break
    done

    while true; do
        echo -ne "Enter a ${BOLD}Name${NC} for the K6 service: "
        read service_name
        if ! validate_no_spaces "$service_name"; then
            continue
        fi
        service_name="${service_name%.service}"
        if [ -z "$service_name" ]; then
            echo -e "${RED}Service name cannot be empty. Please enter a valid service name.${NC}"
            continue
        fi
        if service_exists $service_name &>/dev/null; then
            echo -e "${RED}A service with the name $service_name already exists. Please choose a different name.${NC}"
        else
            echo -e "${GREEN}Creating a new service with the name: $service_name${NC}"
            break
        fi
    done
    # Create the K6 script
    k6_script_path="/root/$service_name.js"
    echo -e "${GREEN}Creating K6 script at $k6_script_path${NC}"

    cat <<EOF > $k6_script_path
import http from 'k6/http';

export let options = {
    vus: $vus,
    duration: '$duration',
};

export default function () {
    http.get('$url');
}
EOF

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to create K6 script.${NC}"
        return 1
    fi

    # Create the systemd service file
    service_file="/etc/systemd/system/$service_name.service"
    echo -e "${GREEN}Creating systemd service at $service_file${NC}"

    cat <<EOF > $service_file
[Unit]
Description=K6 Load Test Service for $service_name.js
After=network.target

[Service]
ExecStart=/usr/bin/k6 run --address localhost:0 $k6_script_path
Restart=always
User=root
WorkingDirectory=/root

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to create systemd service.${NC}"
        return 1
    fi

    # Reload systemd, enable and start the service
    systemctl daemon-reload > /dev/null 2>&1
    systemctl enable $service_name.service > /dev/null 2>&1
    systemctl start $service_name.service > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to start the service.${NC}"
        return 1
    fi

    echo -e "${GREEN}K6 service $service_name started and enabled.${NC}"
    # Schedule service stop after the specified duration using systemd-run
    seconds=$(duration_to_seconds "$duration")    
    systemd-run --quiet --on-active="$seconds" /bin/sh -c "systemctl stop $service_name.service > /dev/null 2>&1 && systemctl disable $service_name.service > /dev/null 2>&1 && rm -f $service_file > /dev/null 2>&1 && rm -f $k6_script_path > /dev/null 2>&1 && systemctl daemon-reload > /dev/null 2>&1"
    echo -e "${GREEN}Service $service_name scheduled to stop and disable after $duration.${NC}"
}
# Function to stop an existing K6 service
stop_k6_service() {
    local services
    local service_name
    local service_number
    echo -e "\n${BLUE}=== Stop K6 Load Test ===${NC}"
    services=$(systemctl list-units --type=service --all --no-pager | grep 'K6 Load Test Service')
    if [ -z "$services" ]; then
        return 1
    fi

    while true; do
        echo -ne "Enter the ${BOLD}Number${NC} of the K6 service to stop: "
        read service_number
        if ! validate_integer "$service_number"; then
            continue
        fi

        service_count=$(echo "$services" | wc -l)
        if [ "$service_number" -lt 1 ] || [ "$service_number" -gt "$service_count" ]; then
            echo -e "${RED}Invalid service number. Please enter a number between 1 and $service_count.${NC}"
            continue
        fi

        service_name=$(echo "$services" | sed -n "${service_number}p" | awk '{print $1}')
        service_name="${service_name%.service}"
        break
    done

    # Stop, disable, and remove the service and associated files
    systemctl stop "$service_name.service" > /dev/null 2>&1
    systemctl disable "$service_name.service" > /dev/null 2>&1
    systemctl reset-failed "$service_name.service" > /dev/null 2>&1
    rm -f "/etc/systemd/system/$service_name.service"
    rm -f "/root/$service_name.js"
    systemctl daemon-reload > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to stop or disable the service.${NC}"
        return 1
    fi

    echo -e "${GREEN}K6 service '$service_name' stopped and disabled successfully.${NC}"
    return 0
}
# Function to list all K6 services
list_k6_services() {
    echo -e "${BLUE}=== Active K6 Load Tests ===${NC}\n"
    # List only units matching 'K6 Load Test Service' and remove empty lines
    services=$(systemctl list-units --type=service --all --no-pager | grep 'K6 Load Test Service')

    if [ -z "$services" ]; then
        echo -e "${BLUE}|---------------------------------------------------------------|${NC}"
        echo -e "${BLUE}|${NC}${RED}                         No active service found.              ${NC}${BLUE}|${NC}"
        echo -e "${BLUE}|---------------------------------------------------------------|${NC}"
    else
        echo -e "${BLUE}|----------------------------------------------------------------------|${NC}"
        echo -e "${BLUE}|${NC} No. ${BLUE}|${NC}   Service Name           ${BLUE}|${NC}   Status       ${BLUE}|${NC}   Active/Inactive  ${BLUE}|${NC}"
        echo -e "${BLUE}|----------------------------------------------------------------------|${NC}"

        counter=1
        echo "$services" | while read -r line; do
            # Remove leading special character, parse using awk, and remove ".service" from service name
            line=$(echo "$line" | sed 's/● //')
            service_name=$(echo "$line" | awk '{print $1}' | sed 's/\.service$//')
            service_status=$(echo "$line" | awk '{print $4}')
            is_active=$(systemctl is-active "$service_name.service")

            # Print the formatted output with service number
            printf "${BLUE}|${NC}  ${MAGENTA}%-3s${BLUE}|${NC}   %-23s${BLUE}|${NC}   %-13s${BLUE}|${NC}   %-17s${BLUE}|${NC}\n" "$counter" "$service_name" "$service_status" "$is_active"
            echo -e "${BLUE}|----------------------------------------------------------------------|${NC}"
            
            counter=$((counter + 1))
        done
    fi
}
main_menu() {
    while true; do
        clear
        logo
        echo -e "${BLUE}Select an option:${NC}"
        echo -e "${CYAN}1)${NC} Create a new K6 script and service"
        echo -e "${CYAN}2)${NC} Remove an existing K6 service"
        echo -e "${CYAN}3)${NC} List all K6 services"
        echo -e "${CYAN}4)${NC} Exit"
        echo -e "${BLUE}------------------------------------${NC}"
        read -p "Enter your choice (1-4): " choice

        case $choice in
            1)
                clear
                create_k6_script_and_service
                press_enter
                ;;
            2)
                clear
                list_k6_services
                stop_k6_service
                press_enter
                ;;
            3)
                clear
                list_k6_services
                press_enter
                ;;
            4)
                echo -e "${GREEN}Thank you for using the K6 Load Testing Management Tool. Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please select 1, 2, 3, or 4.${NC}"
                press_enter
                ;;
        esac
    done
}
press_enter() {
    read -p "Press Enter to continue..."
}
main_menu
