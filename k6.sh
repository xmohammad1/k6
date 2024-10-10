#!/bin/bash

# Color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to install K6 if not installed
install_k6_if_needed() {
    if ! command -v k6 &> /dev/null; then
        echo -e "${YELLOW}K6 is not installed. Installing K6...${NC}"
        sudo gpg -k > /dev/null 2>&1
        sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69 > /dev/null 2>&1
        echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list > /dev/null
        sudo apt-get update > /dev/null 2>&1
        sudo apt-get install k6 -y > /dev/null 2>&1

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
    if systemctl list-units --type=service --all | grep -q "$1.service"; then
        return 0
    else
        echo -e "${RED}Service '$1' does not exist.${NC}"
        return 1
    fi
}

# Function to create and modify K6 processes
create_k6_script_and_service() {
    clear
    # Install K6 if not already installed
    install_k6_if_needed
    # Ask user for inputs with validation
    while true; do
        read -p "Enter number of VUs: " vus
        validate_integer $vus && break
    done

    while true; do
        read -p "Enter duration (e.g., 30s, 1m, 1h): " duration
        validate_duration $duration && break
    done

    while true; do
        read -p "Enter target URL: " url
        validate_url $url && break
    done

    read -p "Enter a name for the K6 service: " service_name
    service_name="${service_name%.service}"
    # Check if service already exists
    if service_exists $service_name; then
        echo -e "${RED}A service with the name $service_name already exists. Please choose a different name.${NC}"
        return
    else
        echo -e "${GREEN}Creating a new service with the name: $service_name${NC}"
    fi

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
}

# Function to stop an existing K6 service
stop_k6_service() {
    clear
    read -p "Enter the name of the service you want to stop: " service_name
    service_name="${service_name%.service}"
    # Validate if service exists before stopping
    if service_exists $service_name; then
        systemctl stop $service_name.service > /dev/null 2>&1
        systemctl disable $service_name.service > /dev/null 2>&1
        sudo systemctl reset-failed $service_name.service > /dev/null 2>&1
        rm -rf /etc/systemd/system/$service_name.service
        rm -rf /root/$service_name.js
        systemctl daemon-reload > /dev/null 2>&1

        if [ $? -ne 0 ]; then
            echo -e "${RED}Error: Failed to stop or disable the service.${NC}"
            return 1
        fi
        echo -e "${GREEN}K6 service $service_name stopped and disabled.${NC}"
    fi
}

# Function to list all K6 services
list_k6_services() {
    clear
    # List only units matching 'K6 Load Test Service' and remove empty lines
    services=$(systemctl list-units --type=service --all --no-pager | grep 'K6 Load Test Service')

    if [ -z "$services" ]; then
        echo -e "${BLUE}|---------------------------------------------------------------|${NC}"
        echo "${RED}|                         No active service found.              |${NC}"
        echo -e "${BLUE}|---------------------------------------------------------------|${NC}"
    else
        echo -e "${BLUE}|---------------------------------------------------------------|${NC}"
        echo -e "${BLUE}|${NC}   Service Name           ${BLUE}|${NC}   Status       ${BLUE}|${NC}   Active/Inactive ${BLUE}|${NC}"
        echo -e "${BLUE}|---------------------------------------------------------------|${NC}"

        echo "$services" | while read -r line; do
            # Remove leading special character, then parse using awk
            line=$(echo "$line" | sed 's/● //')
            service_name=$(echo "$line" | awk '{print $1}')
            service_status=$(echo "$line" | awk '{print $4}')
            is_active=$(systemctl is-active "$service_name")

            # Print the formatted output
            printf "${BLUE}|${NC}   %-23s${BLUE}|${NC}   %-13s${BLUE}|${NC}   %-16s${BLUE}|${NC}\n" "$service_name" "$service_status" "$is_active"
            echo -e "${BLUE}|---------------------------------------------------------------|${NC}"
        done
    fi
}

# Main menu
while true; do
    clear
    echo -e "${BLUE}Select an option:${NC}"
    echo "1. Create a new K6 script and service"
    echo "2. Remove an existing K6 service"
    echo "3. List all K6 services"
    echo "4. Exit"
    read -p "Enter your choice (1/2/3/4): " choice

    case $choice in
        1)
            create_k6_script_and_service
            read -p "Press Enter to continue"
            ;;
        2)
            stop_k6_service
            read -p "Press Enter to continue"
            ;;
        3)
            list_k6_services
            read -p "Press Enter to continue"
            ;;
        4)
            echo -e "${GREEN}Exiting.${NC}"
            break
            ;;
        *)
            echo -e "${RED}Invalid option. Please select 1, 2, 3, or 4.${NC}"
            ;;
    esac
done
