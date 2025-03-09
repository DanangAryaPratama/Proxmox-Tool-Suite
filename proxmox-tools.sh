#!/bin/bash

# ANSI Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YW='\033[33m'
NC='\033[0m' # No Color

# Spinner function for visual feedback
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null; do
        printf " [%c]  " "$spinstr"
        spinstr=${spinstr#?}${spinstr%"${spinstr#?}"}
        sleep $delay
        printf "\r"
    done
    printf "    \r"
}

# Function to delete LXC containers
lxc_delete() {
    NODE=$(hostname)
    containers=$(pct list | tail -n +2 | awk '{print $0 " " $4}')
    if [ -z "$containers" ]; then
        whiptail --title "LXC Container Delete" --msgbox "No LXC containers available!" 10 60
        return 1
    fi
    menu_items=()
    FORMAT="%-10s %-15s %-10s"
    while read -r container; do
        container_id=$(echo $container | awk '{print $1}')
        container_name=$(echo $container | awk '{print $2}')
        container_status=$(echo $container | awk '{print $3}')
        formatted_line=$(printf "$FORMAT" "$container_name" "$container_status")
        menu_items+=("$container_id" "$formatted_line" "OFF")
    done <<< "$containers"
    CHOICES=$(whiptail --title "LXC Container Delete" --checklist "Select LXC containers to delete:" 25 60 13 "${menu_items[@]}" 3>&2 2>&1 1>&3)
    if [ -z "$CHOICES" ]; then
        whiptail --title "LXC Container Delete" --msgbox "No containers selected!" 10 60
        return 1
    fi
    read -p "Delete containers manually or automatically? (Default: manual) m/a: " DELETE_MODE
    DELETE_MODE=${DELETE_MODE:-m}
    selected_ids=$(echo "$CHOICES" | tr -d '"' | tr -s ' ' '\n')
    for container_id in $selected_ids; do
        status=$(pct status $container_id)
        if [ "$status" == "status: running" ]; then
            echo -e "${BLUE}[Info]${GREEN} Stopping container $container_id...${NC}"
            pct stop $container_id &
            sleep 5
            echo -e "${BLUE}[Info]${GREEN} Container $container_id stopped.${NC}"
        fi
        if [[ "$DELETE_MODE" == "a" ]]; then
            echo -e "${BLUE}[Info]${GREEN} Automatically deleting container $container_id...${NC}"
            pct destroy "$container_id" -f &
            pid=$!
            spinner $pid
            [ $? -eq 0 ] && echo "Container $container_id deleted." || whiptail --title "Error" --msgbox "Failed to delete container $container_id." 10 60
        else
            read -p "Delete container $container_id? (y/N): " CONFIRM
            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo -e "${BLUE}[Info]${GREEN} Deleting container $container_id...${NC}"
                pct destroy "$container_id" -f &
                pid=$!
                spinner $pid
                [ $? -eq 0 ] && echo "Container $container_id deleted." || whiptail --title "Error" --msgbox "Failed to delete container $container_id." 10 60
            else
                echo -e "${BLUE}[Info]${RED} Skipping container $container_id...${NC}"
            fi
        fi
    done
    echo -e "${GREEN}Deletion process completed.${NC}"
}

# Function to clean LXC containers
clean_lxcs() {
    NODE=$(hostname)
    EXCLUDE_MENU=()
    MSG_MAX_LENGTH=0
    while read -r TAG ITEM; do
        OFFSET=2
        ((${#ITEM} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#ITEM}+OFFSET
        EXCLUDE_MENU+=("$TAG" "$ITEM " "OFF")
    done < <(pct list | awk 'NR>1')
    excluded_containers=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Containers on $NODE" --checklist "\nSelect containers to skip from cleaning:\n" 16 $((MSG_MAX_LENGTH + 23)) 6 "${EXCLUDE_MENU[@]}" 3>&1 1>&2 2>&3 | tr -d '"') || return
    for container in $(pct list | awk '{if(NR>1) print $1}'); do
        if [[ " ${excluded_containers[@]} " =~ " $container " ]]; then
            echo -e "${BLUE}[Info]${GREEN} Skipping ${BLUE}$container${NC}"
            sleep 1
        else
            os=$(pct config "$container" | awk '/^ostype/ {print $2}')
            if [ "$os" != "debian" ] && [ "$os" != "ubuntu" ]; then
                echo -e "${BLUE}[Info]${GREEN} Skipping ${BLUE}$container${RED} is not Debian or Ubuntu${NC}"
                sleep 1
                continue
            fi
            status=$(pct status $container)
            template=$(pct config $container | grep -q "template:" && echo "true" || echo "false")
            if [ "$template" == "false" ] && [ "$status" == "status: stopped" ]; then
                echo -e "${BLUE}[Info]${GREEN} Starting${BLUE} $container${NC}"
                pct start $container
                sleep 5
                name=$(pct exec "$container" hostname)
                echo -e "${BLUE}[Info]${GREEN} Cleaning ${BLUE}$name${NC}"
                pct exec $container -- bash -c "apt-get -y --purge autoremove && apt-get -y autoclean && rm -rf /var/lib/apt/lists/* && apt-get update"
                echo -e "${BLUE}[Info]${GREEN} Shutting down${BLUE} $container${NC}"
                pct shutdown $container &
            elif [ "$status" == "status: running" ]; then
                name=$(pct exec "$container" hostname)
                echo -e "${BLUE}[Info]${GREEN} Cleaning ${BLUE}$name${NC}"
                pct exec $container -- bash -c "apt-get -y --purge autoremove && apt-get -y autoclean && rm -rf /var/lib/apt/lists/* && apt-get update"
            fi
        fi
    done
    wait
    echo -e "${GREEN}Finished, selected containers cleaned.${NC}"
}

# Function to trim LXC containers
fstrim_lxc() {
    ROOT_FS=$(df -Th "/" | awk 'NR==2 {print $2}')
    if [ "$ROOT_FS" != "ext4" ]; then
        echo -e "${RED}Root filesystem is not ext4. Exiting.${NC}"
        return 1
    fi
    NODE=$(hostname)
    EXCLUDE_MENU=()
    MSG_MAX_LENGTH=0
    while read -r TAG ITEM; do
        OFFSET=2
        ((${#ITEM} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#ITEM}+OFFSET
        EXCLUDE_MENU+=("$TAG" "$ITEM " "OFF")
    done < <(pct list | awk 'NR>1')
    excluded_containers=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Containers on $NODE" --checklist "\nSelect containers to skip from trimming:\n" 16 $((MSG_MAX_LENGTH + 23)) 6 "${EXCLUDE_MENU[@]}" 3>&1 1>&2 2>&3 | tr -d '"') || return
    for container in $(pct list | awk '{if(NR>1) print $1}'); do
        if [[ " ${excluded_containers} " =~ " $container " ]]; then
            echo -e "${BLUE}[Info]${GREEN} Skipping ${BLUE}$container${NC}"
            sleep 1
        else
            template=$(pct config "$container" | grep -q "template:" && echo "true" || echo "false")
            if [ "$template" == "true" ]; then
                echo -e "${BLUE}[Info]${GREEN} Skipping ${BLUE}$container${RED} is a template${NC}"
                sleep 1
                continue
            fi
            echo -e "${BLUE}[Info]${GREEN} Trimming ${BLUE}$container${NC}"
            before_trim=$(lvs | awk -F '[[:space:]]+' 'NR>1 && (/Data%|'"vm-$container"'/) {gsub(/%/, "", $7); print $7}')
            echo -e "${RED}Data before trim $before_trim%${NC}"
            pct fstrim "$container"
            after_trim=$(lvs | awk -F '[[:space:]]+' 'NR>1 && (/Data%|'"vm-$container"'/) {gsub(/%/, "", $7); print $7}')
            echo -e "${GREEN}Data after trim $after_trim%${NC}"
            sleep 1.5
        fi
    done
    echo -e "${GREEN}Finished, LXC containers trimmed.${NC}"
}

# Function to update LXC containers
update_lxcs() {
    NODE=$(hostname)
    EXCLUDE_MENU=()
    MSG_MAX_LENGTH=0
    while read -r TAG ITEM; do
        OFFSET=2
        ((${#ITEM} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#ITEM}+OFFSET
        EXCLUDE_MENU+=("$TAG" "$ITEM " "OFF")
    done < <(pct list | awk 'NR>1')
    excluded_containers=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Containers on $NODE" --checklist "\nSelect containers to skip from updates:\n" 16 $((MSG_MAX_LENGTH + 23)) 6 "${EXCLUDE_MENU[@]}" 3>&1 1>&2 2>&3 | tr -d '"') || return
    containers_needing_reboot=()
    for container in $(pct list | awk '{if(NR>1) print $1}'); do
        if [[ " ${excluded_containers[@]} " =~ " $container " ]]; then
            echo -e "${BLUE}[Info]${GREEN} Skipping ${BLUE}$container${NC}"
            sleep 1
        else
            status=$(pct status $container)
            template=$(pct config $container | grep -q "template:" && echo "true" || echo "false")
            if [ "$template" == "false" ] && [ "$status" == "status: stopped" ]; then
                echo -e "${BLUE}[Info]${GREEN} Starting${BLUE} $container${NC}"
                pct start $container
                sleep 5
                name=$(pct exec "$container" hostname)
                os=$(pct config "$container" | awk '/^ostype/ {print $2}')
                echo -e "${BLUE}[Info]${GREEN} Updating ${BLUE}$container${GREEN} : $name${NC}"
                case "$os" in
                    alpine) pct exec "$container" -- ash -c "apk update && apk upgrade" ;;
                    archlinux) pct exec "$container" -- bash -c "pacman -Syyu --noconfirm" ;;
                    fedora|rocky|centos|alma) pct exec "$container" -- bash -c "dnf -y update && dnf -y upgrade" ;;
                    ubuntu|debian|devuan) pct exec "$container" -- bash -c "apt-get update && apt-get -yq dist-upgrade" ;;
                    opensuse) pct exec "$container" -- bash -c "zypper ref && zypper --non-interactive dup" ;;
                esac
                echo -e "${BLUE}[Info]${GREEN} Shutting down${BLUE} $container${NC}"
                pct shutdown $container &
            elif [ "$status" == "status: running" ]; then
                name=$(pct exec "$container" hostname)
                os=$(pct config "$container" | awk '/^ostype/ {print $2}')
                echo -e "${BLUE}[Info]${GREEN} Updating ${BLUE}$container${GREEN} : $name${NC}"
                case "$os" in
                    alpine) pct exec "$container" -- ash -c "apk update && apk upgrade" ;;
                    archlinux) pct exec "$container" -- bash -c "pacman -Syyu --noconfirm" ;;
                    fedora|rocky|centos|alma) pct exec "$container" -- bash -c "dnf -y update && dnf -y upgrade" ;;
                    ubuntu|debian|devuan) pct exec "$container" -- bash -c "apt-get update && apt-get -yq dist-upgrade" ;;
                    opensuse) pct exec "$container" -- bash -c "zypper ref && zypper --non-interactive dup" ;;
                esac
            fi
            if pct exec "$container" -- [ -e "/var/run/reboot-required" ]; then
                container_hostname=$(pct exec "$container" hostname)
                containers_needing_reboot+=("$container ($container_hostname)")
            fi
        fi
    done
    wait
    echo -e "${GREEN}Containers updated successfully.${NC}"
    if [ "${#containers_needing_reboot[@]}" -gt 0 ]; then
        echo -e "${RED}Containers requiring reboot:${NC}"
        printf "%s\n" "${containers_needing_reboot[@]}"
    fi
}

# Function to clean old kernels
kernel_clean() {
    current_kernel=$(uname -r)
    available_kernels=$(dpkg --list | grep 'kernel-.*-pve' | awk '{print $2}' | grep -v "$current_kernel" | sort -V)
    if [ -z "$available_kernels" ]; then
        echo -e "${GREEN}No old kernels detected. Current kernel: $current_kernel${NC}"
        return 0
    fi
    echo -e "${YW}Available kernels for removal:${NC}"
    echo "$available_kernels" | nl -w 2 -s '. '
    echo -e "\n${YW}Select kernels to remove (comma-separated, e.g., 1,2):${NC}"
    read -r selected
    IFS=',' read -r -a selected_indices <<< "$selected"
    kernels_to_remove=()
    for index in "${selected_indices[@]}"; do
        kernel=$(echo "$available_kernels" | sed -n "${index}p")
        if [ -n "$kernel" ]; then
            kernels_to_remove+=("$kernel")
        fi
    done
    if [ ${#kernels_to_remove[@]} -eq 0 ]; then
        echo -e "${RED}No valid selection made. Exiting.${NC}"
        return 1
    fi
    echo -e "${YW}Kernels to be removed:${NC}"
    printf "%s\n" "${kernels_to_remove[@]}"
    read -rp "Proceed with removal? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "${RED}Aborted.${NC}"
        return 1
    fi
    for kernel in "${kernels_to_remove[@]}"; do
        echo -e "${YW}Removing $kernel...${NC}"
        if apt-get purge -y "$kernel" >/dev/null 2>&1; then
            echo -e "${GREEN}Successfully removed: $kernel${NC}"
        else
            echo -e "${RED}Failed to remove: $kernel. Check dependencies.${NC}"
        fi
    done
    echo -e "${YW}Cleaning up...${NC}"
    apt-get autoremove -y >/dev/null 2>&1 && update-grub >/dev/null 2>&1
    echo -e "${GREEN}Cleanup and GRUB update completed.${NC}"
}

# Function to configure bind mounts in LXC containers
configure_bind_mount() {
    # Configurable variables
    # Note: HOST_DIR must be adjusted based on your system's mount point (e.g., /mnt/multimedia, /mnt/ssd/storage, etc.)
    HOST_DIR="/mnt/multimedia"  # Change this to match your host's directory
    CONTAINER_DIR="/mnt/multimedia"
    MOUNT_LINE="mp0: ${HOST_DIR},mp=${CONTAINER_DIR},backup=0"

    # Validate host directory
    if [[ ! -d "$HOST_DIR" ]]; then
        echo -e "${RED}Error: Host directory $HOST_DIR does not exist.${NC}"
        return 1
    fi

    # Create INCLUDE_MENU to select containers
    NODE=$(hostname)
    INCLUDE_MENU=()
    MSG_MAX_LENGTH=0
    while read -r TAG ITEM; do
        OFFSET=2
        ((${#ITEM} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#ITEM}+OFFSET
        INCLUDE_MENU+=("$TAG" "$ITEM " "OFF")
    done < <(pct list | awk 'NR>1')
    included_containers=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Containers on $NODE" --checklist "\nSelect containers to configure bind mount:\n" 16 $((MSG_MAX_LENGTH + 23)) 6 "${INCLUDE_MENU[@]}" 3>&1 1>&2 2>&3 | tr -d '"') || return
    if [ -z "$included_containers" ]; then
        echo -e "${RED}No containers selected for bind mount configuration.${NC}"
        return 1
    fi

    # Sub-function to configure a single container
    configure_container() {
        local vmid=$1
        echo -e "${BLUE}----------------------------------------${NC}"
        echo -e "${BLUE}[Info]${GREEN} Configuring container $vmid...${NC}"

        STATUS=$(pct status $vmid 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Error: Container $vmid does not exist.${NC}"
            return 1
        fi

        if [[ "$STATUS" == *"running"* ]]; then
            echo -e "${BLUE}[Info]${GREEN} Stopping container $vmid...${NC}"
            pct stop $vmid
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}Error: Failed to stop container $vmid.${NC}"
                return 1
            fi
        fi

        CONFIG_FILE="/etc/pve/lxc/${vmid}.conf"
        BACKUP_FILE="${CONFIG_FILE}.bak_$(date +%F_%T)"
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Error: Failed to backup configuration for container $vmid.${NC}"
            return 1
        fi
        echo -e "${BLUE}[Info]${GREEN} Configuration file backed up to ${BACKUP_FILE}${NC}"

        if grep -q "^mp0:" "$CONFIG_FILE"; then
            echo -e "${BLUE}[Info]${GREEN} mp0 entry exists, updating...${NC}"
            sed -i "s|^mp0:.*|$MOUNT_LINE|" "$CONFIG_FILE"
        else
            echo -e "${BLUE}[Info]${GREEN} mp0 entry does not exist, adding...${NC}"
            echo "$MOUNT_LINE" >> "$CONFIG_FILE"
        fi

        pct start $vmid
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Error: Failed to start container $vmid.${NC}"
            return 1
        fi
        sleep 5

        echo -e "${BLUE}[Info]${GREEN} Verifying mount in container $vmid...${NC}"
        pct exec $vmid -- df -h | grep "$CONTAINER_DIR" || {
            echo -e "${RED}Error: Mount point $CONTAINER_DIR not found in container $vmid.${NC}"
            return 1
        }
        echo -e "${GREEN}Configuration for container $vmid completed.${NC}"
    }

    # Process selected containers
    for vmid in $included_containers; do
        configure_container $vmid
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Failed to configure container $vmid.${NC}"
        fi
    done
    echo -e "${GREEN}Bind mount configuration completed for selected containers.${NC}"
}

# Function to display the menu
show_menu() {
    clear
    echo -e "${BLUE}=======================================${NC}"
    echo -e "${GREEN}       🛠️  Proxmox Tool Suite  🛠️${NC}"
    echo -e "${BLUE}=======================================${NC}"
    echo -e "Tools for Proxmox management\n"
    echo -e "${GREEN}Select an option:${NC}"
    echo -e "${BLUE}--- LXC Management ---${NC}"
    echo -e "  ${BLUE}1)${NC} 🚫 Delete LXC containers"
    echo -e "  ${BLUE}2)${NC} 🔄 Update LXC containers"
    echo -e "  ${BLUE}3)${NC} 🧹 Clean LXC containers"
    echo -e "  ${BLUE}4)${NC} 💾 Run fstrim on LXC containers"
    echo -e "  ${BLUE}5)${NC} 🔗 Configure bind mount on LXC containers"
    echo -e "${BLUE}--- System Maintenance ---${NC}"
    echo -e "  ${BLUE}6)${NC} 📥 Update package list (apt update)"
    echo -e "  ${BLUE}7)${NC} ⬆️ Update full system (apt upgrade)"
    echo -e "  ${BLUE}8)${NC} 🗑️ Clean system (autoremove and autoclean)"
    echo -e "  ${BLUE}9)${NC} ⚙️ Clean old kernels"
    echo -e "${BLUE}--- Other Options ---${NC}"
    echo -e "  ${BLUE}0)${NC} 🚪 Exit"
    echo -e "${BLUE}=======================================${NC}"
    read -p "Option: " option
    echo ""
    return "$option"
}

# Main loop
while true; do
    show_menu
    option=$?
    case $option in
        1) 
            echo -e "${GREEN}Running LXC container deletion...${NC}"
            lxc_delete
            ;;
        2) 
            echo -e "${GREEN}Updating LXC containers...${NC}"
            update_lxcs
            ;;
        3) 
            echo -e "${GREEN}Cleaning LXC containers...${NC}"
            clean_lxcs
            ;;
        4) 
            echo -e "${GREEN}Running fstrim on LXC containers...${NC}"
            fstrim_lxc
            ;;
        5) 
            echo -e "${GREEN}Configuring bind mount on LXC containers...${NC}"
            configure_bind_mount
            ;;
        6) 
            echo -e "${GREEN}Updating package list...${NC}"
            apt update
            ;;
        7) 
            echo -e "${GREEN}Updating full system...${NC}"
            apt update && apt upgrade -y
            ;;
        8) 
            echo -e "${GREEN}Cleaning system...${NC}"
            apt autoremove -y && apt autoclean
            ;;
        9) 
            echo -e "${GREEN}Cleaning old kernels...${NC}"
            kernel_clean
            ;;
        0) 
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *) 
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
    sleep 2  # Pause before returning to menu
done
