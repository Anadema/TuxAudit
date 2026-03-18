#!/bin/bash
# Cyber Linux Audit Tool — TuxAudit
# Copyright 2026 BlueTeam
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
########################################################################
#                                                                      #
#        TuxAudit v1.0 / Linux Configuration Audit                     #
#        Inspired by PowerAudit (Windows) — Linux port                 #
#                                                                      #
#  Supported OS :                                                      #
#    [1] Raspberry Pi OS  (Debian 12 Bookworm / 13 Trixie)            #
#    [2] Debian           (11 Bullseye / 12 Bookworm)                 #
#    [3] Ubuntu           (22.04 Jammy / 24.04 Noble)                 #
#    [4] RHEL / CentOS    (8 / 9)                                      #
#    [5] Fedora           (39 / 40)                                    #
#                                                                      #
########################################################################

# ---------------------------------------------------------------------------
#  COLORS & FORMATTING
# ---------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DCYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
DGRAY='\033[1;30m'
DYELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'   # No Color / Reset

# ---------------------------------------------------------------------------
#  GLOBAL VARIABLES
# ---------------------------------------------------------------------------

HOSTNAME_VAL=$(hostname)
DATE_VAL=$(date +"%Y-%m-%d")
HOUR_VAL=$(date +"%H:%M:%S")
REPORT_DATE=$(date +"%Y-%m-%d_%H-%M")
LAST_REPORT_PATH=""

# OS detection variables (populated by detect_os)
OS_FAMILY=""      # debian | rhel
OS_NAME=""        # raspbian | debian | ubuntu | rhel | fedora
OS_VERSION=""     # e.g. 13, 22.04, 9
OS_CODENAME=""    # trixie, bookworm, jammy...
OS_PRETTY=""      # Full human-readable name
OS_CONFIRMED=0    # 1 = auto-detected and confirmed, 2 = manually chosen

# ---------------------------------------------------------------------------
#  ROOT CHECK
# ---------------------------------------------------------------------------

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo ""
        echo -e "  ${RED}[ERROR] This script must be run as root (or with sudo).${NC}"
        echo -e "  ${YELLOW}Please run: sudo bash tuxaudit.sh${NC}"
        echo ""
        exit 1
    fi
}

# ---------------------------------------------------------------------------
#  UTILITY FUNCTIONS
# ---------------------------------------------------------------------------

section_header() {
    local title="$1"
    local line
    line=$(printf '%0.s-' {1..70})
    echo ""
    echo -e "  ${DCYAN}${line}${NC}"
    echo -e "  ${WHITE}>> ${title}${NC}"
    echo -e "  ${DCYAN}${line}${NC}"
    echo ""
}

error_msg() {
    echo -e "  ${RED}[ERROR] $1${NC}"
}

progress_bar() {
    local current=$1
    local total=$2
    local label="${3:-}"
    local width=50
    local pct=$(( current * 100 / total ))
    local filled=$(( width * current / total ))
    local empty=$(( width - filled ))
    local bar
    bar=$(printf '%0.s#' $(seq 1 $filled))$(printf '%0.s.' $(seq 1 $empty))
    printf "\r  [${CYAN}%-${width}s${NC}] %3d%% - %-40s" "$bar" "$pct" "$label"
}

pause() {
    echo ""
    read -rp "  Press [Enter] to return to the menu..." _
}

cmd_or_na() {
    # Run a command; if it fails or is missing, print N/A
    local cmd="$1"
    if command -v "${cmd%% *}" &>/dev/null; then
        eval "$cmd" 2>/dev/null || echo "N/A"
    else
        echo "N/A (command not found: ${cmd%% *})"
    fi
}

# ---------------------------------------------------------------------------
#  OS AUTO-DETECTION
# ---------------------------------------------------------------------------

detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        return 1
    fi

    # Source the file safely
    local id=""
    local version_id=""
    local codename=""
    local pretty=""

    id=$(grep "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
    version_id=$(grep "^VERSION_ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
    codename=$(grep "^VERSION_CODENAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
    pretty=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')

    OS_VERSION="$version_id"
    OS_CODENAME="$codename"
    OS_PRETTY="$pretty"

    case "$id" in
        raspbian|debian)
            # Distinguish Raspberry Pi OS from plain Debian
            if [[ -f /proc/device-tree/model ]] && grep -qi "raspberry" /proc/device-tree/model 2>/dev/null; then
                OS_NAME="raspbian"
                OS_FAMILY="debian"
            else
                OS_NAME="debian"
                OS_FAMILY="debian"
            fi
            ;;
        ubuntu)
            OS_NAME="ubuntu"
            OS_FAMILY="debian"
            ;;
        rhel|centos|almalinux|rocky)
            OS_NAME="rhel"
            OS_FAMILY="rhel"
            ;;
        fedora)
            OS_NAME="fedora"
            OS_FAMILY="rhel"
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

# ---------------------------------------------------------------------------
#  OS SELECTION MENU
# ---------------------------------------------------------------------------

os_selection_menu() {
    clear
    echo ""
    echo -e "  ${DCYAN}TuxAudit v1.0${NC}  ${GRAY}·${NC}  ${WHITE}OS Selection${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${GRAY}Supported operating systems:${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} ${WHITE}Raspberry Pi OS${NC}  ${GRAY}(Debian 12 Bookworm / 13 Trixie)${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}Debian${NC}           ${GRAY}(11 Bullseye / 12 Bookworm)${NC}"
    echo -e "  ${CYAN}[3]${NC} ${WHITE}Ubuntu${NC}           ${GRAY}(22.04 Jammy / 24.04 Noble)${NC}"
    echo -e "  ${CYAN}[4]${NC} ${WHITE}RHEL / CentOS${NC}    ${GRAY}(8 / 9)${NC}"
    echo -e "  ${CYAN}[5]${NC} ${WHITE}Fedora${NC}           ${GRAY}(39 / 40)${NC}"
    echo ""
    echo -e "  ${CYAN}[Q]${NC} Quit"
    echo ""

    while true; do
        read -rp "  $(echo -e "${WHITE}Your choice:${NC} ")" os_choice
        case "$os_choice" in
            1)
                OS_NAME="raspbian"; OS_FAMILY="debian"
                OS_PRETTY="Raspberry Pi OS (manual)"
                OS_CONFIRMED=2; break ;;
            2)
                OS_NAME="debian"; OS_FAMILY="debian"
                OS_PRETTY="Debian (manual)"
                OS_CONFIRMED=2; break ;;
            3)
                OS_NAME="ubuntu"; OS_FAMILY="debian"
                OS_PRETTY="Ubuntu (manual)"
                OS_CONFIRMED=2; break ;;
            4)
                OS_NAME="rhel"; OS_FAMILY="rhel"
                OS_PRETTY="RHEL / CentOS (manual)"
                OS_CONFIRMED=2; break ;;
            5)
                OS_NAME="fedora"; OS_FAMILY="rhel"
                OS_PRETTY="Fedora (manual)"
                OS_CONFIRMED=2; break ;;
            [Qq]) echo ""; echo -e "  ${CYAN}Goodbye!${NC}"; echo ""; exit 0 ;;
            *) echo -e "  ${RED}Invalid choice.${NC}" ;;
        esac
    done
}

# ---------------------------------------------------------------------------
#  OS DETECTION BANNER (called at startup)
# ---------------------------------------------------------------------------

os_detection_banner() {
    clear
    echo ""
    echo -e "  ${DCYAN}TuxAudit v1.0${NC}  ${GRAY}·${NC}  ${WHITE}Linux Configuration Audit${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${GRAY}Date  ${NC} ${WHITE}${DATE_VAL}  ${HOUR_VAL}${NC}"
    echo -e "  ${GRAY}Host  ${NC} ${WHITE}${HOSTNAME_VAL}${NC}"
    echo ""

    if detect_os; then
        echo -e "  ${GREEN}[✔] OS detected automatically:${NC}"
        echo -e "      ${WHITE}${OS_PRETTY}${NC}"
        echo -e "      ${GRAY}Family: ${OS_FAMILY} | Version: ${OS_VERSION} | Codename: ${OS_CODENAME}${NC}"
        echo ""

        # Check if the detected version is supported
        local supported=0
        case "$OS_NAME" in
            raspbian)  [[ "$OS_VERSION" == "12" || "$OS_VERSION" == "13" ]] && supported=1 ;;
            debian)    [[ "$OS_VERSION" == "11" || "$OS_VERSION" == "12" ]] && supported=1 ;;
            ubuntu)    [[ "$OS_VERSION" == "22.04" || "$OS_VERSION" == "24.04" ]] && supported=1 ;;
            rhel)      [[ "${OS_VERSION%%.*}" == "8" || "${OS_VERSION%%.*}" == "9" ]] && supported=1 ;;
            fedora)    [[ "$OS_VERSION" == "39" || "$OS_VERSION" == "40" ]] && supported=1 ;;
        esac

        if [[ $supported -eq 0 ]]; then
            echo -e "  ${YELLOW}[!] Warning: version ${OS_VERSION} is not in the tested list.${NC}"
            echo -e "      ${GRAY}Commands may not work correctly on this version.${NC}"
            echo ""
        fi

        OS_CONFIRMED=1
        echo -e "  ${GRAY}Press [Enter] to confirm, or [M] to select OS manually.${NC}"
        read -rp "  " confirm_choice
        if [[ "${confirm_choice,,}" == "m" ]]; then
            os_selection_menu
        fi
    else
        echo -e "  ${YELLOW}[!] Unable to auto-detect OS.${NC}"
        echo ""
        echo -e "  ${GRAY}Press [Enter] to select OS manually.${NC}"
        read -rp "  " _
        os_selection_menu
    fi
}

# ---------------------------------------------------------------------------
#  PACKAGE MANAGER HELPERS (by OS family)
# ---------------------------------------------------------------------------

pkg_list_installed() {
    case "$OS_FAMILY" in
        debian) dpkg -l 2>/dev/null | grep "^ii" ;;
        rhel)   rpm -qa --qf "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n" 2>/dev/null ;;
    esac
}

pkg_list_upgradable() {
    case "$OS_FAMILY" in
        debian) apt list --upgradable 2>/dev/null | grep -v "Listing" ;;
        rhel)   dnf check-update 2>/dev/null || yum check-update 2>/dev/null ;;
    esac
}

svc_list_enabled() {
    systemctl list-unit-files --type=service --state=enabled 2>/dev/null \
        || service --status-all 2>/dev/null
}

svc_list_running() {
    systemctl list-units --type=service --state=running 2>/dev/null \
        || service --status-all 2>/dev/null | grep "+"
}

firewall_status() {
    case "$OS_FAMILY" in
        debian)
            if command -v ufw &>/dev/null; then
                ufw status verbose 2>/dev/null
            else
                iptables -L -n -v 2>/dev/null
            fi
            ;;
        rhel)
            if command -v firewall-cmd &>/dev/null; then
                firewall-cmd --list-all 2>/dev/null
            else
                iptables -L -n -v 2>/dev/null
            fi
            ;;
    esac
}

# ---------------------------------------------------------------------------
#  AUDIT MODULES — Raspberry Pi / Debian family
# ---------------------------------------------------------------------------
# Each module is a function named module_XX()
# At the end of each module: pause
# ---------------------------------------------------------------------------

# --- 01 : OS Information ---------------------------------------------------
module_01() {
    section_header "01 — SYSTEM INFORMATION"
    echo -e "  ${DGRAY}Conseil: [INFO] Check OS version and kernel. An outdated kernel exposes${NC}"
    echo -e "  ${DGRAY}known CVEs (e.g. Dirty COW, PolKit, sudo heap overflow). Verify EOL status.${NC}"
    echo -e "  ${DGRAY}Long uptime (>30d) may indicate pending updates. [THREAT: Local privilege escalation]${NC}"
    echo ""

    local kernel arch uptime_val ram_total ram_free cpu_model
    kernel=$(uname -r)
    arch=$(uname -m)
    ram_total=$(grep MemTotal /proc/meminfo | awk '{printf "%.1f GB", $2/1024/1024}')
    ram_free=$(grep MemAvailable /proc/meminfo | awk '{printf "%.1f GB", $2/1024/1024}')
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ //')
    uptime_val=$(uptime -p 2>/dev/null || uptime)

    # Raspberry Pi specific: board model
    local board="N/A"
    if [[ -f /proc/device-tree/model ]]; then
        board=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
    fi

    printf "  ${DGRAY}%-28s${NC}: ${WHITE}%s${NC}\n" "Hostname"       "$HOSTNAME_VAL"
    printf "  ${DGRAY}%-28s${NC}: ${WHITE}%s${NC}\n" "OS"             "$OS_PRETTY"
    printf "  ${DGRAY}%-28s${NC}: ${WHITE}%s${NC}\n" "Kernel"         "$kernel"
    printf "  ${DGRAY}%-28s${NC}: ${WHITE}%s${NC}\n" "Architecture"   "$arch"
    printf "  ${DGRAY}%-28s${NC}: ${WHITE}%s${NC}\n" "CPU"            "$cpu_model"
    printf "  ${DGRAY}%-28s${NC}: ${WHITE}%s${NC}\n" "RAM Total"      "$ram_total"
    printf "  ${DGRAY}%-28s${NC}: ${WHITE}%s${NC}\n" "RAM Available"  "$ram_free"
    printf "  ${DGRAY}%-28s${NC}: ${WHITE}%s${NC}\n" "Uptime"         "$uptime_val"
    [[ "$board" != "N/A" ]] && \
    printf "  ${DGRAY}%-28s${NC}: ${GREEN}%s${NC}\n" "Board (Pi)"     "$board"
    echo ""

    # Disk usage
    echo -e "  ${DYELLOW}---- DISKS -------------------------------------------------------${NC}"
    echo ""
    df -h --output=source,size,used,avail,pcent,target 2>/dev/null | grep -v tmpfs | grep -v udev | \
    while IFS= read -r line; do
        local pct_val
        pct_val=$(echo "$line" | awk '{print $5}' | tr -d '%')
        if [[ "$pct_val" =~ ^[0-9]+$ ]]; then
            local col="${GREEN}"
            (( pct_val > 75 )) && col="${YELLOW}"
            (( pct_val > 90 )) && col="${RED}"
            echo -e "  ${col}${line}${NC}"
        else
            echo -e "  ${DGRAY}${line}${NC}"
        fi
    done

    pause
}

# --- 02 : Users & Groups ---------------------------------------------------
module_02() {
    section_header "02 — USERS & GROUPS"
    echo -e "  ${DGRAY}Conseil: [CRITICAL] Check for accounts with UID=0 other than root (backdoor).${NC}"
    echo -e "  ${DGRAY}Accounts with empty passwords or no password hash are critical risks.${NC}"
    echo -e "  ${DGRAY}Suspicious shell for service accounts. [THREAT: Backdoor, privilege escalation]${NC}"
    echo ""

    echo -e "  ${DYELLOW}---- LOCAL USERS (from /etc/passwd) ---------------------------${NC}"
    echo ""
    while IFS=: read -r username _ uid gid comment home shell; do
        local col="${GRAY}"
        local flags=""
        [[ "$uid" -eq 0 ]] && col="${RED}" && flags=" ${RED}[UID=0 !]${NC}"
        [[ "$uid" -ge 1000 && "$uid" -lt 65534 ]] && col="${WHITE}"
        [[ "$shell" == "/bin/bash" || "$shell" == "/bin/sh" || "$shell" == "/bin/zsh" ]] && \
            [[ "$uid" -ge 1000 ]] && flags+=" ${GREEN}[login shell]${NC}"
        printf "  ${col}%-20s${NC} uid=%-6s gid=%-6s home=%-25s shell=%s%s\n" \
            "$username" "$uid" "$gid" "$home" "$shell" "$flags"
    done < /etc/passwd

    echo ""
    echo -e "  ${DYELLOW}---- SUDO / WHEEL MEMBERS --------------------------------------${NC}"
    echo ""
    local sudo_members=""
    if getent group sudo &>/dev/null; then
        sudo_members=$(getent group sudo | cut -d: -f4)
        echo -e "  ${CYAN}sudo group   :${NC} ${WHITE}${sudo_members:-<empty>}${NC}"
    fi
    if getent group wheel &>/dev/null; then
        local wheel_members
        wheel_members=$(getent group wheel | cut -d: -f4)
        echo -e "  ${CYAN}wheel group  :${NC} ${WHITE}${wheel_members:-<empty>}${NC}"
    fi

    echo ""
    echo -e "  ${DYELLOW}---- SUDOERS (main rules) --------------------------------------${NC}"
    echo ""
    grep -v "^#" /etc/sudoers 2>/dev/null | grep -v "^$" | \
        sed 's/^/  /' | head -30
    if [[ -d /etc/sudoers.d ]]; then
        for f in /etc/sudoers.d/*; do
            [[ -f "$f" ]] || continue
            echo -e "\n  ${CYAN}--- $f ---${NC}"
            grep -v "^#" "$f" 2>/dev/null | grep -v "^$" | sed 's/^/  /' | head -10
        done
    fi

    echo ""
    echo -e "  ${DYELLOW}---- ACCOUNTS WITH EMPTY PASSWORDS ----------------------------${NC}"
    echo ""
    local empty_pw
    empty_pw=$(awk -F: '($2 == "" || $2 == "!" ) { print $1 }' /etc/shadow 2>/dev/null)
    if [[ -n "$empty_pw" ]]; then
        echo -e "  ${RED}[!] Empty/locked passwords:${NC} $empty_pw"
    else
        echo -e "  ${GREEN}[✔] No accounts with empty passwords found.${NC}"
    fi

    pause
}

# --- 03 : Process List -----------------------------------------------------
module_03() {
    section_header "03 — PROCESS LIST (Top CPU)"
    echo -e "  ${DGRAY}Conseil: [IMPORTANT] Check for processes running from /tmp, /dev/shm,${NC}"
    echo -e "  ${DGRAY}/var/tmp or with random names. High CPU with no visible path = miner.${NC}"
    echo -e "  ${DGRAY}[THREAT: Crypto-miner, RAT, rootkit, fileless malware]${NC}"
    echo ""

    echo -e "  ${CYAN}%-8s %-30s %-8s %-8s %-6s %s${NC}" \
        "PID" "COMMAND" "%CPU" "%MEM" "USER" "PATH"
    echo -e "  ${DGRAY}$(printf '%0.s-' {1..80})${NC}"

    ps aux --sort=-%cpu 2>/dev/null | head -30 | tail -n +2 | \
    while read -r user pid cpu mem vsz rss tty stat start time command; do
        local col="${GRAY}"
        local path_hint=""
        # Highlight suspicious paths
        if echo "$command" | grep -qE "^(/tmp|/dev/shm|/var/tmp|/run/user)"; then
            col="${RED}"; path_hint=" ${RED}[SUSPICIOUS PATH]${NC}"
        fi
        printf "  ${col}%-8s %-30s %-8s %-8s %-6s${NC}%s\n" \
            "$pid" "${command:0:30}" "$cpu" "$mem" "$user" "$path_hint"
    done

    pause
}

# --- 04 : Network Interfaces -----------------------------------------------
module_04() {
    section_header "04 — NETWORK INTERFACES"
    echo -e "  ${DGRAY}Conseil: [IMPORTANT] Unexpected interfaces (vpn, tun, tap) may indicate${NC}"
    echo -e "  ${DGRAY}rogue tunnels or C2 channels. Promiscuous mode = possible sniffer.${NC}"
    echo -e "  ${DGRAY}[THREAT: Data exfiltration, pivoting, C2 tunnel]${NC}"
    echo ""

    if command -v ip &>/dev/null; then
        ip -c addr show 2>/dev/null | sed 's/^/  /'
        echo ""
        echo -e "  ${DYELLOW}---- ROUTING TABLE -----------------------------------------${NC}"
        echo ""
        ip route show 2>/dev/null | sed 's/^/  /'
    else
        ifconfig -a 2>/dev/null | sed 's/^/  /'
        echo ""
        route -n 2>/dev/null | sed 's/^/  /'
    fi

    echo ""
    echo -e "  ${DYELLOW}---- PROMISCUOUS MODE CHECK --------------------------------${NC}"
    echo ""
    local promisc_ifaces=""
    while IFS= read -r iface; do
        local flags
        flags=$(ip link show "$iface" 2>/dev/null | grep -o "PROMISC")
        if [[ "$flags" == "PROMISC" ]]; then
            promisc_ifaces+="$iface "
        fi
    done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1)

    if [[ -n "$promisc_ifaces" ]]; then
        echo -e "  ${RED}[!] PROMISCUOUS interfaces detected: ${promisc_ifaces}${NC}"
    else
        echo -e "  ${GREEN}[✔] No promiscuous interfaces detected.${NC}"
    fi

    pause
}

# --- 05 : Open Ports & Connections -----------------------------------------
module_05() {
    section_header "05 — OPEN PORTS & CONNECTIONS"
    echo -e "  ${DGRAY}Conseil: [CRITICAL] Unknown listening port = potential backdoor or C2.${NC}"
    echo -e "  ${DGRAY}Port 0.0.0.0 (all interfaces) is more exposed than 127.0.0.1.${NC}"
    echo -e "  ${DGRAY}[THREAT: Backdoor, C2 listener, lateral movement, exposed service]${NC}"
    echo ""

    echo -e "  ${DYELLOW}---- LISTENING PORTS (TCP/UDP) ------------------------------${NC}"
    echo ""
    if command -v ss &>/dev/null; then
        ss -tlnpu 2>/dev/null | sed 's/^/  /'
    elif command -v netstat &>/dev/null; then
        netstat -tlnpu 2>/dev/null | sed 's/^/  /'
    else
        error_msg "Neither ss nor netstat found."
    fi

    echo ""
    echo -e "  ${DYELLOW}---- ESTABLISHED CONNECTIONS --------------------------------${NC}"
    echo ""
    if command -v ss &>/dev/null; then
        ss -tnpu state established 2>/dev/null | sed 's/^/  /'
    elif command -v netstat &>/dev/null; then
        netstat -tnpu 2>/dev/null | grep ESTABLISHED | sed 's/^/  /'
    fi

    pause
}

# --- 06 : Firewall Status --------------------------------------------------
module_06() {
    section_header "06 — FIREWALL STATUS"
    echo -e "  ${DGRAY}Conseil: [CRITICAL] A machine without a firewall is fully exposed on the network.${NC}"
    echo -e "  ${DGRAY}Default ACCEPT policy = all ports reachable. Verify INPUT/OUTPUT/FORWARD.${NC}"
    echo -e "  ${DGRAY}[THREAT: Direct network exploitation, lateral movement, exfiltration]${NC}"
    echo ""

    firewall_status | sed 's/^/  /'
    echo ""

    # Also check iptables raw
    echo -e "  ${DYELLOW}---- iptables (raw) ----------------------------------------${NC}"
    echo ""
    iptables -L -n -v 2>/dev/null | head -60 | sed 's/^/  /'

    pause
}

# --- 07 : SSH Configuration ------------------------------------------------
module_07() {
    section_header "07 — SSH CONFIGURATION"
    echo -e "  ${DGRAY}Conseil: [CRITICAL] PermitRootLogin yes = direct root access risk.${NC}"
    echo -e "  ${DGRAY}PasswordAuthentication yes = brute-force possible. Check AllowUsers.${NC}"
    echo -e "  ${DGRAY}[THREAT: Brute-force, unauthorized root access, lateral movement]${NC}"
    echo ""

    local sshd_conf="/etc/ssh/sshd_config"
    if [[ -f "$sshd_conf" ]]; then
        local critical_keys=(
            "PermitRootLogin"
            "PasswordAuthentication"
            "PubkeyAuthentication"
            "AuthorizedKeysFile"
            "PermitEmptyPasswords"
            "AllowUsers"
            "DenyUsers"
            "AllowGroups"
            "Port"
            "ListenAddress"
            "X11Forwarding"
            "MaxAuthTries"
            "LoginGraceTime"
            "Protocol"
        )
        for key in "${critical_keys[@]}"; do
            local val
            val=$(grep -i "^${key}" "$sshd_conf" 2>/dev/null | head -1 | awk '{print $2}')
            if [[ -n "$val" ]]; then
                local col="${GREEN}"
                # Highlight dangerous values
                [[ "$key" == "PermitRootLogin" && "$val" != "no" ]] && col="${RED}"
                [[ "$key" == "PasswordAuthentication" && "$val" == "yes" ]] && col="${YELLOW}"
                [[ "$key" == "PermitEmptyPasswords" && "$val" == "yes" ]] && col="${RED}"
                printf "  ${DGRAY}%-30s${NC}: ${col}%s${NC}\n" "$key" "$val"
            else
                printf "  ${DGRAY}%-30s${NC}: ${GRAY}(not set / default)${NC}\n" "$key"
            fi
        done

        echo ""
        echo -e "  ${DYELLOW}---- SSH authorized_keys (all users) -----------------------${NC}"
        echo ""
        while IFS=: read -r user _ uid _; do
            (( uid >= 1000 && uid < 65534 )) || continue
            local home_dir
            home_dir=$(getent passwd "$user" | cut -d: -f6)
            local ak="${home_dir}/.ssh/authorized_keys"
            if [[ -f "$ak" ]]; then
                local count
                count=$(wc -l < "$ak" 2>/dev/null)
                echo -e "  ${CYAN}${user}${NC}: ${WHITE}${count} key(s)${NC}  → ${GRAY}${ak}${NC}"
                head -3 "$ak" 2>/dev/null | sed "s/^/    /"
            fi
        done < /etc/passwd

    else
        error_msg "sshd_config not found at ${sshd_conf}"
    fi

    pause
}

# --- 08 : Cron Jobs --------------------------------------------------------
module_08() {
    section_header "08 — SCHEDULED TASKS (CRON)"
    echo -e "  ${DGRAY}Conseil: [CRITICAL] Malware often persists via cron. Check for entries${NC}"
    echo -e "  ${DGRAY}running from /tmp, curl/wget pipes, base64 commands.${NC}"
    echo -e "  ${DGRAY}[THREAT: Backdoor persistence, miner scheduling, reverse shell]${NC}"
    echo ""

    local cron_dirs=(
        "/etc/crontab"
        "/etc/cron.d"
        "/etc/cron.hourly"
        "/etc/cron.daily"
        "/etc/cron.weekly"
        "/etc/cron.monthly"
        "/var/spool/cron/crontabs"
    )

    for item in "${cron_dirs[@]}"; do
        if [[ -f "$item" ]]; then
            echo -e "  ${CYAN}--- ${item} ---${NC}"
            grep -v "^#" "$item" 2>/dev/null | grep -v "^$" | \
            while IFS= read -r line; do
                local col="${GRAY}"
                echo "$line" | grep -qiE "(curl|wget|bash|sh|base64|/tmp|/dev/shm)" && col="${RED}"
                echo -e "  ${col}${line}${NC}"
            done
            echo ""
        elif [[ -d "$item" ]]; then
            echo -e "  ${CYAN}--- ${item}/ ---${NC}"
            for f in "${item}"/*; do
                [[ -f "$f" ]] || continue
                echo -e "  ${DGRAY}  > ${f}${NC}"
                grep -v "^#" "$f" 2>/dev/null | grep -v "^$" | \
                while IFS= read -r line; do
                    local col="${GRAY}"
                    echo "$line" | grep -qiE "(curl|wget|bash|sh|base64|/tmp|/dev/shm)" && col="${RED}"
                    echo -e "    ${col}${line}${NC}"
                done
            done
            echo ""
        fi
    done

    # User crontabs
    echo -e "  ${DYELLOW}---- USER CRONTABS -----------------------------------------${NC}"
    echo ""
    while IFS=: read -r user _ uid _; do
        (( uid >= 1000 && uid < 65534 )) || continue
        local ctab
        ctab=$(crontab -l -u "$user" 2>/dev/null)
        if [[ -n "$ctab" ]]; then
            echo -e "  ${CYAN}User: ${user}${NC}"
            echo "$ctab" | grep -v "^#" | grep -v "^$" | \
            while IFS= read -r line; do
                local col="${GRAY}"
                echo "$line" | grep -qiE "(curl|wget|bash|base64|/tmp|/dev/shm)" && col="${RED}"
                echo -e "  ${col}  ${line}${NC}"
            done
            echo ""
        fi
    done < /etc/passwd

    pause
}

# --- 09 : SUID/SGID Files --------------------------------------------------
module_09() {
    section_header "09 — SUID / SGID FILES"
    echo -e "  ${DGRAY}Conseil: [CRITICAL] SUID files run as root regardless of who executes them.${NC}"
    echo -e "  ${DGRAY}Unknown SUID binaries in unusual paths = classic privilege escalation vector.${NC}"
    echo -e "  ${DGRAY}[THREAT: Local privilege escalation, GTFOBins exploitation]${NC}"
    echo ""

    echo -e "  ${YELLOW}[!] Searching for SUID/SGID binaries (may take a moment)...${NC}"
    echo ""

    # Known safe SUID binaries (whitelist reference)
    local known_suid=(
        "/usr/bin/sudo" "/usr/bin/passwd" "/usr/bin/su"
        "/usr/bin/mount" "/usr/bin/umount" "/usr/bin/ping"
        "/usr/bin/newgrp" "/usr/bin/chfn" "/usr/bin/chsh"
        "/usr/bin/gpasswd" "/usr/bin/expiry" "/usr/bin/chage"
        "/usr/bin/wall" "/usr/bin/write" "/usr/bin/ssh-agent"
        "/usr/lib/openssh/ssh-keysign"
        "/usr/lib/dbus-1.0/dbus-daemon-launch-helper"
        "/usr/sbin/unix_chkpwd" "/usr/sbin/pam_extrausers_chkpwd"
        "/bin/su" "/bin/mount" "/bin/umount" "/bin/ping"
        "/sbin/unix_chkpwd"
    )

    echo -e "  ${DYELLOW}HOST SYSTEM${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo ""
    local host_count=0
    local unusual_host=0

    find / -path /proc -prune -o -path /sys -prune -o \
           -path /var/lib/docker -prune -o \
           -path /var/lib/lxc -prune -o \
           -path /var/lib/containerd -prune -o \
           \( -perm -4000 -o -perm -2000 \) -type f -print 2>/dev/null | \
    while IFS= read -r f; do
        local col="${CYAN}"
        local flag=""
        local is_known=0
        for k in "${known_suid[@]}"; do
            [[ "$f" == "$k" ]] && is_known=1 && break
        done
        if [[ $is_known -eq 0 ]]; then
            col="${RED}"; flag="  <-- UNUSUAL"
        fi
        echo -e "  ${col}${f}${flag}${NC}"
    done

    echo ""
    echo -e "  ${DYELLOW}DOCKER / CONTAINER LAYERS${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo -e "  ${GRAY}  (SUID inside container image layers — normal, not a host risk)${NC}"
    echo ""

    local docker_count=0
    for docker_root in /var/lib/docker/overlay2 /var/lib/lxc /var/lib/containerd; do
        [[ -d "$docker_root" ]] || continue
        find "$docker_root" \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | \
        while IFS= read -r f; do
            echo -e "  ${GRAY}${f}${NC}"
        done
    done

    local docker_suid_count
    docker_suid_count=$(find /var/lib/docker /var/lib/lxc /var/lib/containerd \
        \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | wc -l)
    if [[ $docker_suid_count -gt 0 ]]; then
        echo -e "  ${GRAY}[i] ${docker_suid_count} SUID/SGID files in container layers — expected, not flagged.${NC}"
    else
        echo -e "  ${GRAY}No container layers found.${NC}"
    fi

    pause
}

# --- 10 : Installed Packages -----------------------------------------------
module_10() {
    section_header "10 — INSTALLED PACKAGES"
    echo -e "  ${DGRAY}Conseil: [INFO] Look for unusual tools (nmap, netcat, socat, metasploit,${NC}"
    echo -e "  ${DGRAY}mimikatz equivalents, john, hashcat). Attackers often install recon tools.${NC}"
    echo -e "  ${DGRAY}[THREAT: Attacker tooling, lateral movement tools, crypto-miner deps]${NC}"
    echo ""

    # Suspicious package names to highlight
    local suspicious_pkgs=(
        "nmap" "netcat" "nc" "socat" "hydra" "john" "hashcat"
        "aircrack" "wireshark" "tcpdump" "masscan" "nikto"
        "sqlmap" "metasploit" "armitage" "beef" "nbtscan"
        "xmrig" "cpuminer" "minerd"
    )

    echo -e "  ${DYELLOW}---- Checking for suspicious/pentest packages ---------------${NC}"
    echo ""
    local found_any=0
    for pkg in "${suspicious_pkgs[@]}"; do
        case "$OS_FAMILY" in
            debian)
                if dpkg -l "$pkg" &>/dev/null 2>&1 | grep -q "^ii"; then
                    echo -e "  ${RED}[!] Found: ${pkg}${NC}"
                    found_any=1
                fi
                ;;
            rhel)
                if rpm -q "$pkg" &>/dev/null; then
                    echo -e "  ${RED}[!] Found: ${pkg}${NC}"
                    found_any=1
                fi
                ;;
        esac
    done
    [[ $found_any -eq 0 ]] && echo -e "  ${GREEN}[✔] No suspicious packages detected.${NC}"

    echo ""
    echo -e "  ${DYELLOW}---- Last 20 installed packages (by date) -------------------${NC}"
    echo ""
    case "$OS_FAMILY" in
        debian)
            grep " install " /var/log/dpkg.log 2>/dev/null | tail -20 | sed 's/^/  /'
            ;;
        rhel)
            rpm -qa --qf "%{INSTALLTIME:date}  %{NAME}-%{VERSION}\n" 2>/dev/null | \
                sort -r | head -20 | sed 's/^/  /'
            ;;
    esac

    pause
}

# --- 11 : Services ---------------------------------------------------------
module_11() {
    section_header "11 — SERVICES (Enabled & Running)"
    echo -e "  ${DGRAY}Conseil: [IMPORTANT] Unnecessary running services increase attack surface.${NC}"
    echo -e "  ${DGRAY}Check for services running from /tmp or with unusual names.${NC}"
    echo -e "  ${DGRAY}[THREAT: Backdoor service, persistence, unnecessary exposure]${NC}"
    echo ""

    echo -e "  ${DYELLOW}---- RUNNING SERVICES --------------------------------------${NC}"
    echo ""
    svc_list_running | sed 's/^/  /'

    echo ""
    echo -e "  ${DYELLOW}---- ENABLED SERVICES (autostart) --------------------------${NC}"
    echo ""
    svc_list_enabled | sed 's/^/  /'

    pause
}

# --- 12 : System Logs Summary ----------------------------------------------
module_12() {
    section_header "12 — SYSTEM LOGS (Security Summary)"
    echo -e "  ${DGRAY}Conseil: [CRITICAL] Multiple failed SSH logins = brute-force attempt.${NC}"
    echo -e "  ${DGRAY}sudo usage from unexpected users is suspicious. Check for auth errors.${NC}"
    echo -e "  ${DGRAY}[THREAT: Brute-force, unauthorized escalation, intrusion traces]${NC}"
    echo ""

    echo -e "  ${DYELLOW}---- Failed SSH logins (last 20) ----------------------------${NC}"
    echo ""
    if command -v journalctl &>/dev/null; then
        journalctl -u ssh -u sshd --no-pager -n 100 2>/dev/null | \
            grep -i "failed\|invalid\|refused" | tail -20 | sed 's/^/  /'
    fi
    grep -i "failed password\|invalid user" /var/log/auth.log 2>/dev/null | \
        tail -20 | sed 's/^/  /'
    grep -i "failed password\|invalid user" /var/log/secure 2>/dev/null | \
        tail -20 | sed 's/^/  /'

    echo ""
    echo -e "  ${DYELLOW}---- sudo usage (last 20) ----------------------------------${NC}"
    echo ""
    grep "sudo" /var/log/auth.log 2>/dev/null | grep -i "command\|COMMAND" | \
        tail -20 | sed 's/^/  /'
    grep "sudo" /var/log/secure 2>/dev/null | grep -i "COMMAND" | \
        tail -20 | sed 's/^/  /'

    echo ""
    echo -e "  ${DYELLOW}---- Last logins (last) ------------------------------------${NC}"
    echo ""
    last -20 2>/dev/null | sed 's/^/  /'

    pause
}

# --- 13 : Wi-Fi (Raspberry Pi / Debian) ------------------------------------
module_13() {
    section_header "13 — WI-FI CONFIGURATION"
    echo -e "  ${DGRAY}Conseil: [IMPORTANT] Saved Wi-Fi profiles may contain cleartext PSK.${NC}"
    echo -e "  ${DGRAY}Rogue AP or evil-twin attacks are possible on open networks.${NC}"
    echo -e "  ${DGRAY}[THREAT: Wi-Fi credential theft, evil twin, rogue AP]${NC}"
    echo ""

    if command -v nmcli &>/dev/null; then
        echo -e "  ${DYELLOW}---- NetworkManager Wi-Fi profiles -------------------------${NC}"
        echo ""
        nmcli -t -f NAME,TYPE connection show 2>/dev/null | grep wifi | \
        while IFS=: read -r name type; do
            echo -e "  ${CYAN}Profile: ${WHITE}${name}${NC}"
            # Show PSK if readable (requires root)
            local psk
            psk=$(nmcli -s -g 802-11-wireless-security.psk connection show "$name" 2>/dev/null)
            if [[ -n "$psk" ]]; then
                echo -e "    ${YELLOW}PSK: ${psk}${NC}"
            fi
        done
        echo ""
        echo -e "  ${DYELLOW}---- Available networks (scan) -----------------------------${NC}"
        echo ""
        nmcli device wifi list 2>/dev/null | head -20 | sed 's/^/  /'
    elif command -v wpa_cli &>/dev/null; then
        wpa_cli list_networks 2>/dev/null | sed 's/^/  /'
    else
        echo -e "  ${GRAY}nmcli / wpa_cli not available.${NC}"
    fi

    # wpa_supplicant config files (contain PSK)
    echo ""
    echo -e "  ${DYELLOW}---- wpa_supplicant config files ----------------------------${NC}"
    echo ""
    for f in /etc/wpa_supplicant/wpa_supplicant.conf \
              /etc/wpa_supplicant/wpa_supplicant-wlan*.conf; do
        [[ -f "$f" ]] || continue
        echo -e "  ${CYAN}${f}${NC}"
        grep -v "^#" "$f" 2>/dev/null | grep -v "^$" | \
        while IFS= read -r line; do
            local col="${GRAY}"
            echo "$line" | grep -qi "psk\|password" && col="${YELLOW}"
            echo -e "  ${col}  ${line}${NC}"
        done
        echo ""
    done

    pause
}

# --- 14 : NTP / Time -------------------------------------------------------
module_14() {
    section_header "14 — TIME SOURCE (NTP)"
    echo -e "  ${DGRAY}Conseil: [INFO] Time drift > 5 min may indicate log tampering.${NC}"
    echo -e "  ${DGRAY}Verify NTP source is a trusted server. Critical for SIEM correlation.${NC}"
    echo -e "  ${DGRAY}[THREAT: Anti-forensics, log falsification]${NC}"
    echo ""

    printf "  ${DGRAY}%-28s${NC}: ${WHITE}%s${NC}\n" "Current date/time" "$(date)"
    printf "  ${DGRAY}%-28s${NC}: ${WHITE}%s${NC}\n" "Hardware clock (hwclock)" "$(hwclock 2>/dev/null || echo 'N/A')"
    echo ""

    if command -v timedatectl &>/dev/null; then
        timedatectl status 2>/dev/null | sed 's/^/  /'
    fi

    echo ""
    echo -e "  ${DYELLOW}---- NTP Service status ------------------------------------${NC}"
    echo ""
    if command -v chronyc &>/dev/null; then
        echo -e "  ${CYAN}chronyc tracking:${NC}"
        chronyc tracking 2>/dev/null | sed 's/^/  /'
        echo ""
        echo -e "  ${CYAN}chronyc sources:${NC}"
        chronyc sources 2>/dev/null | head -10 | sed 's/^/  /'
    elif command -v ntpq &>/dev/null; then
        echo -e "  ${CYAN}ntpq -p:${NC}"
        ntpq -p 2>/dev/null | sed 's/^/  /'
    else
        echo -e "  ${GRAY}chronyc / ntpq not available.${NC}"
    fi

    pause
}

# --- 15 : Kernel & Boot Security -------------------------------------------
module_15() {
    section_header "15 — KERNEL & BOOT SECURITY"
    echo -e "  ${DGRAY}Conseil: [CRITICAL] Check ASLR, dmesg restrictions, ptrace scope.${NC}"
    echo -e "  ${DGRAY}Raspberry Pi: verify boot config for SSH forced at boot.${NC}"
    echo -e "  ${DGRAY}[THREAT: Kernel exploits, memory attacks, boot-time persistence]${NC}"
    echo ""

    echo -e "  ${DYELLOW}---- Kernel security parameters (sysctl) -------------------${NC}"
    echo ""
    local sysctl_checks=(
        "kernel.randomize_va_space"     # ASLR: 2=full
        "kernel.dmesg_restrict"         # 1 = restrict dmesg to root
        "kernel.kptr_restrict"          # 2 = hide kernel pointers
        "kernel.perf_event_paranoid"    # >= 2
        "kernel.yama.ptrace_scope"      # 1 = restricted ptrace
        "net.ipv4.ip_forward"           # 0 = no routing
        "net.ipv4.conf.all.rp_filter"   # 1 = spoofing protection
        "net.ipv4.conf.all.accept_redirects"
        "net.ipv4.conf.all.send_redirects"
        "net.ipv4.tcp_syncookies"       # 1 = SYN flood protection
    )

    for param in "${sysctl_checks[@]}"; do
        local val
        val=$(sysctl -n "$param" 2>/dev/null)
        if [[ -n "$val" ]]; then
            local col="${GREEN}"
            # Highlight potentially dangerous values
            [[ "$param" == "kernel.randomize_va_space" && "$val" -lt 2 ]] && col="${RED}"
            [[ "$param" == "net.ipv4.ip_forward" && "$val" -eq 1 ]] && col="${YELLOW}"
            [[ "$param" == "net.ipv4.conf.all.accept_redirects" && "$val" -eq 1 ]] && col="${YELLOW}"
            printf "  ${DGRAY}%-45s${NC}: ${col}%s${NC}\n" "$param" "$val"
        fi
    done

    echo ""
    echo -e "  ${DYELLOW}---- Raspberry Pi boot config (/boot/config.txt) -----------${NC}"
    echo ""
    if [[ -f /boot/config.txt ]]; then
        grep -v "^#" /boot/config.txt 2>/dev/null | grep -v "^$" | sed 's/^/  /'
    elif [[ -f /boot/firmware/config.txt ]]; then
        grep -v "^#" /boot/firmware/config.txt 2>/dev/null | grep -v "^$" | sed 's/^/  /'
    else
        echo -e "  ${GRAY}/boot/config.txt not found (not a Pi?).${NC}"
    fi

    echo ""
    echo -e "  ${DYELLOW}---- GRUB / Boot parameters --------------------------------${NC}"
    echo ""
    grep -v "^#" /etc/default/grub 2>/dev/null | grep -v "^$" | sed 's/^/  /'
    cat /proc/cmdline 2>/dev/null | sed 's/^/  Current kernel cmdline: /'

    pause
}

# --- 16 : Bash History & Suspicious Commands ----------------------------
module_16() {
    section_header "16 — BASH HISTORY & SUSPICIOUS COMMANDS"
    echo -e "  ${DGRAY}Conseil: [CRITICAL] History reveals attacker post-exploitation steps.${NC}"
    echo -e "  ${DGRAY}Commands like wget|curl piped to bash, base64 -d, /dev/tcp are C2 IOCs.${NC}"
    echo -e "  ${DGRAY}[THREAT: Lateral movement traces, C2 download, credential harvesting]${NC}"
    echo ""

    # Suspicious patterns to highlight
    local SUSP_PAT='wget|curl.*bash|base64 -d|/dev/tcp|nc -e|python.*socket|perl.*socket|chmod.*777|/tmp/.*\.sh|\.\/[a-z0-9]{6,}|dd if=|mkfifo|socat'

    echo -e "  ${DYELLOW}---- root history --------------------------------------------------${NC}"
    echo ""
    for hfile in /root/.bash_history /root/.zsh_history /root/.sh_history; do
        [[ -f "$hfile" ]] || continue
        echo -e "  ${CYAN}${hfile}${NC} ($(wc -l < "$hfile") lines)"
        grep -v "^#" "$hfile" 2>/dev/null | tail -30 | \
        while IFS= read -r line; do
            local col="${GRAY}"
            echo "$line" | grep -qiE "$SUSP_PAT" && col="${RED}"
            echo -e "  ${col}  ${line}${NC}"
        done
        echo ""
    done

    echo -e "  ${DYELLOW}---- All user histories --------------------------------------------${NC}"
    echo ""
    while IFS=: read -r user _ uid _ _ home _; do
        (( uid >= 1000 && uid < 65534 )) || continue
        for hfile in "${home}/.bash_history" "${home}/.zsh_history"; do
            [[ -f "$hfile" ]] || continue
            local suspicious_count
            suspicious_count=$(grep -ciE "$SUSP_PAT" "$hfile" 2>/dev/null || echo 0)
            local col="${CYAN}"
            [[ $suspicious_count -gt 0 ]] && col="${RED}"
            echo -e "  ${col}${user}${NC} → ${hfile} (${col}${suspicious_count} suspicious${NC} / $(wc -l < "$hfile") total)"
            if [[ $suspicious_count -gt 0 ]]; then
                grep -iE "$SUSP_PAT" "$hfile" 2>/dev/null | head -10 | \
                    sed "s/^/    ${RED}[!]${NC} /"
            fi
            echo ""
        done
    done < /etc/passwd

    echo -e "  ${DYELLOW}---- /tmp and /dev/shm suspicious files ----------------------------${NC}"
    echo ""
    find /tmp /dev/shm /var/tmp -type f 2>/dev/null | \
    while IFS= read -r f; do
        local col="${YELLOW}"
        file "$f" 2>/dev/null | grep -qiE "script|elf|executable" && col="${RED}"
        echo -e "  ${col}$(ls -lah "$f" 2>/dev/null)${NC}"
    done
    local tmp_count
    tmp_count=$(find /tmp /dev/shm /var/tmp -type f 2>/dev/null | wc -l)
    [[ $tmp_count -eq 0 ]] && echo -e "  ${GREEN}[✔] No files in /tmp, /dev/shm, /var/tmp.${NC}"

    echo ""
    echo -e "  ${DYELLOW}---- lsof: open deleted files (rootkit indicator) ------------------${NC}"
    echo ""
    lsof 2>/dev/null | grep "deleted" | grep -v "^COMMAND" | head -20 | sed 's/^/  /'
    local del_count
    del_count=$(lsof 2>/dev/null | grep -c "deleted" || echo 0)
    [[ $del_count -eq 0 ]] && echo -e "  ${GREEN}[✔] No deleted-but-open files detected.${NC}" || \
        echo -e "  ${YELLOW}[!] ${del_count} deleted-but-open file(s) — possible rootkit/malware activity.${NC}"

    pause
}

# --- 17 : Kernel Modules & Rootkit Indicators ---------------------------
module_17() {
    section_header "17 — KERNEL MODULES & ROOTKIT INDICATORS"
    echo -e "  ${DGRAY}Conseil: [CRITICAL] Unknown kernel modules may be rootkits.${NC}"
    echo -e "  ${DGRAY}chkrootkit/rkhunter detect known rootkit signatures and file tampering.${NC}"
    echo -e "  ${DGRAY}[THREAT: Kernel rootkit, persistence, stealth backdoor]${NC}"
    echo ""

    echo -e "  ${DYELLOW}---- Loaded kernel modules (lsmod) ----------------------------------${NC}"
    echo ""
    lsmod 2>/dev/null | sed 's/^/  /'

    echo ""
    echo -e "  ${DYELLOW}---- Recently loaded modules (dmesg) --------------------------------${NC}"
    echo ""
    dmesg 2>/dev/null | grep -i "module\|insmod\|rmmod\|loading" | tail -20 | sed 's/^/  /'

    echo ""
    echo -e "  ${DYELLOW}---- dmesg kernel anomalies (last 30) ------------------------------${NC}"
    echo ""
    dmesg 2>/dev/null | grep -iE "error|warn|fail|oom|segfault|exploit|attack|overflow" | \
        tail -30 | \
    while IFS= read -r line; do
        local col="${GRAY}"
        echo "$line" | grep -qiE "exploit|attack|overflow|rootkit" && col="${RED}"
        echo "$line" | grep -qiE "error|fail|segfault|oom" && col="${YELLOW}"
        echo -e "  ${col}${line}${NC}"
    done

    echo ""
    echo -e "  ${DYELLOW}---- chkrootkit --------------------------------------------------${NC}"
    echo ""
    if command -v chkrootkit &>/dev/null; then
        chkrootkit 2>/dev/null | grep -v "^$\|not found\|not tested" | \
        while IFS= read -r line; do
            local col="${GRAY}"
            echo "$line" | grep -qiE "INFECTED|suspicious|Warning" && col="${RED}"
            echo "$line" | grep -qi "not infected\|nothing found\|no suspect" && col="${GREEN}"
            echo -e "  ${col}${line}${NC}"
        done
    else
        echo -e "  ${YELLOW}[!] chkrootkit not installed.${NC}"
        echo -e "  ${GRAY}    Install: apt install chkrootkit${NC}"
    fi

    echo ""
    echo -e "  ${DYELLOW}---- rkhunter ---------------------------------------------------- ${NC}"
    echo ""
    if command -v rkhunter &>/dev/null; then
        rkhunter --check --skip-keypress --rwo 2>/dev/null | \
        while IFS= read -r line; do
            local col="${GRAY}"
            echo "$line" | grep -qiE "Warning|Infected|Found" && col="${RED}"
            echo "$line" | grep -qi "OK\|Not found\|None" && col="${GREEN}"
            echo -e "  ${col}${line}${NC}"
        done
    else
        echo -e "  ${YELLOW}[!] rkhunter not installed.${NC}"
        echo -e "  ${GRAY}    Install: apt install rkhunter${NC}"
    fi

    pause
}

# --- 18 : File Integrity ------------------------------------------------
module_18() {
    section_header "18 — FILE INTEGRITY"
    echo -e "  ${DGRAY}Conseil: [CRITICAL] Modified system binaries = classic post-compromise tampering.${NC}"
    echo -e "  ${DGRAY}debsums/RPM verify checksums against package DB. AIDE detects any change.${NC}"
    echo -e "  ${DGRAY}[THREAT: Backdoored binaries, persistence, rootkit installation]${NC}"
    echo ""

    echo -e "  ${DYELLOW}---- debsums (Debian/Ubuntu/Pi) ------------------------------------${NC}"
    echo ""
    if command -v debsums &>/dev/null; then
        local failed_count
        failed_count=$(debsums -s 2>/dev/null | wc -l)
        if [[ $failed_count -gt 0 ]]; then
            echo -e "  ${RED}[!] ${failed_count} package checksum failure(s) detected:${NC}"
            debsums -s 2>/dev/null | head -20 | sed 's/^/  /'
        else
            echo -e "  ${GREEN}[✔] All package checksums OK (debsums).${NC}"
        fi
    else
        echo -e "  ${YELLOW}[!] debsums not installed.${NC}"
        echo -e "  ${GRAY}    Install: apt install debsums${NC}"
    fi

    echo ""
    echo -e "  ${DYELLOW}---- rpm -Va (RHEL/Fedora) -----------------------------------------${NC}"
    echo ""
    if command -v rpm &>/dev/null; then
        local rpm_fails
        rpm_fails=$(rpm -Va 2>/dev/null | grep -v "^$" | wc -l)
        if [[ $rpm_fails -gt 0 ]]; then
            echo -e "  ${RED}[!] ${rpm_fails} RPM verification failure(s):${NC}"
            rpm -Va 2>/dev/null | head -20 | sed 's/^/  /'
        else
            echo -e "  ${GREEN}[✔] All RPM checksums OK.${NC}"
        fi
    else
        echo -e "  ${GRAY}rpm not available (not a RHEL system).${NC}"
    fi

    echo ""
    echo -e "  ${DYELLOW}---- AIDE (Advanced Intrusion Detection Environment) ---------------${NC}"
    echo ""
    if command -v aide &>/dev/null; then
        echo -e "  ${CYAN}Running AIDE check (may take a moment)...${NC}"
        aide --check 2>/dev/null | tail -30 | \
        while IFS= read -r line; do
            local col="${GRAY}"
            echo "$line" | grep -qiE "changed|added|removed" && col="${RED}"
            echo "$line" | grep -qi "okay\|no changes" && col="${GREEN}"
            echo -e "  ${col}${line}${NC}"
        done
    else
        echo -e "  ${YELLOW}[!] AIDE not installed.${NC}"
        echo -e "  ${GRAY}    Install: apt install aide && aideinit${NC}"
    fi

    echo ""
    echo -e "  ${DYELLOW}---- Recently modified system files (last 24h) ---------------------${NC}"
    echo ""
    find /bin /sbin /usr/bin /usr/sbin /lib /lib64 /usr/lib \
        -type f -newer /proc/1/exe 2>/dev/null | head -20 | \
    while IFS= read -r f; do
        echo -e "  ${RED}[!] ${f}${NC}  $(ls -lah "$f" 2>/dev/null | awk '{print $6,$7,$8}')"
    done
    local recent_count
    recent_count=$(find /bin /sbin /usr/bin /usr/sbin -type f -newer /proc/1/exe 2>/dev/null | wc -l)
    [[ $recent_count -eq 0 ]] && echo -e "  ${GREEN}[✔] No recently modified system binaries.${NC}"

    pause
}

# --- 19 : Web Stack Audit (Apache / Nginx / PHP) ------------------------
module_19() {
    section_header "19 — WEB STACK AUDIT (Apache / Nginx / PHP)"
    echo -e "  ${DGRAY}Conseil: [CRITICAL] Web servers are primary initial access vectors.${NC}"
    echo -e "  ${DGRAY}eval/base64_decode in PHP = webshell. Recent files in /var/www = backdoor.${NC}"
    echo -e "  ${DGRAY}[THREAT: Webshell, RCE, file inclusion, PHP backdoor]${NC}"
    echo ""

    # --- Apache ---
    echo -e "  ${DYELLOW}---- Apache2 ------------------------------------------------------${NC}"
    echo ""
    if pgrep -x apache2 &>/dev/null || pgrep -x httpd &>/dev/null; then
        echo -e "  ${GREEN}[✔] Apache is running.${NC}"
        apachectl -S 2>/dev/null | head -20 | sed 's/^/  /' || \
            httpd -S 2>/dev/null | head -20 | sed 's/^/  /'
        echo ""
        echo -e "  ${CYAN}Document roots:${NC}"
        grep -rh "DocumentRoot" /etc/apache2/ /etc/httpd/ 2>/dev/null | \
            grep -v "^#" | sort -u | sed 's/^/    /'
    else
        echo -e "  ${GRAY}Apache not running.${NC}"
    fi

    echo ""
    # --- Nginx ---
    echo -e "  ${DYELLOW}---- Nginx --------------------------------------------------------${NC}"
    echo ""
    if pgrep -x nginx &>/dev/null; then
        echo -e "  ${GREEN}[✔] Nginx is running.${NC}"
        nginx -T 2>/dev/null | grep -E "root|server_name|listen" | \
            grep -v "^#" | head -20 | sed 's/^/    /'
    else
        echo -e "  ${GRAY}Nginx not running.${NC}"
    fi

    echo ""
    # --- PHP ---
    echo -e "  ${DYELLOW}---- PHP ----------------------------------------------------------${NC}"
    echo ""
    if command -v php &>/dev/null; then
        local php_ver
        php_ver=$(php -v 2>/dev/null | head -1)
        echo -e "  ${CYAN}Version:${NC} ${WHITE}${php_ver}${NC}"
        echo ""
        echo -e "  ${CYAN}Dangerous functions (disable_functions):${NC}"
        php -i 2>/dev/null | grep "disable_functions" | sed 's/^/    /'
        echo ""
        echo -e "  ${CYAN}allow_url_fopen / allow_url_include (RFI risk):${NC}"
        find /etc/php -name "php.ini" 2>/dev/null | while IFS= read -r ini; do
            local uf ui
            uf=$(grep "^allow_url_fopen"    "$ini" 2>/dev/null | tail -1)
            ui=$(grep "^allow_url_include"  "$ini" 2>/dev/null | tail -1)
            [[ -n "$uf" || -n "$ui" ]] || continue
            echo -e "    ${CYAN}${ini}${NC}"
            local col="${GREEN}"
            echo "$uf" | grep -qi "On" && col="${RED}"
            [[ -n "$uf" ]] && echo -e "      ${col}${uf}${NC}"
            col="${GREEN}"
            echo "$ui" | grep -qi "On" && col="${RED}"
            [[ -n "$ui" ]] && echo -e "      ${col}${ui}${NC}"
        done
    else
        echo -e "  ${GRAY}PHP not installed.${NC}"
    fi

    echo ""
    # --- Webshell detection ---
    echo -e "  ${DYELLOW}---- Webshell detection in /var/www ---------------------------------${NC}"
    echo ""
    local webroot="/var/www"
    if [[ -d "$webroot" ]]; then
        # eval( in PHP
        local eval_count
        eval_count=$(grep -rl "eval(" "$webroot" 2>/dev/null | wc -l)
        if [[ $eval_count -gt 0 ]]; then
            echo -e "  ${RED}[!] eval() found in ${eval_count} file(s):${NC}"
            grep -rl "eval(" "$webroot" 2>/dev/null | head -10 | sed 's/^/    /'
        else
            echo -e "  ${GREEN}[✔] No eval() found.${NC}"
        fi

        # base64_decode
        local b64_count
        b64_count=$(grep -rl "base64_decode" "$webroot" 2>/dev/null | wc -l)
        if [[ $b64_count -gt 0 ]]; then
            echo -e "  ${RED}[!] base64_decode() found in ${b64_count} file(s):${NC}"
            grep -rl "base64_decode" "$webroot" 2>/dev/null | head -10 | sed 's/^/    /'
        else
            echo -e "  ${GREEN}[✔] No base64_decode() found.${NC}"
        fi

        # system/exec/passthru in PHP
        local exec_count
        exec_count=$(grep -rlE '\b(system|passthru|shell_exec|popen)\s*\(' "$webroot" 2>/dev/null | wc -l)
        if [[ $exec_count -gt 0 ]]; then
            echo -e "  ${RED}[!] Shell exec functions found in ${exec_count} file(s):${NC}"
            grep -rlE '\b(system|passthru|shell_exec|popen)\s*\(' "$webroot" 2>/dev/null | head -10 | sed 's/^/    /'
        else
            echo -e "  ${GREEN}[✔] No shell execution functions found.${NC}"
        fi

        echo ""
        echo -e "  ${DYELLOW}---- Files modified in last 48h in /var/www ----------------------${NC}"
        echo ""
        find "$webroot" -type f -mtime -2 2>/dev/null | head -20 | \
        while IFS= read -r f; do
            echo -e "  ${YELLOW}$(ls -lah "$f" 2>/dev/null)${NC}"
        done
        local recent_web
        recent_web=$(find "$webroot" -type f -mtime -2 2>/dev/null | wc -l)
        [[ $recent_web -eq 0 ]] && echo -e "  ${GREEN}[✔] No files modified in last 48h.${NC}"
    else
        echo -e "  ${GRAY}/var/www not found — web server not configured.${NC}"
    fi

    echo ""
    # --- Web logs ---
    echo -e "  ${DYELLOW}---- Web access logs (last 20 lines) --------------------------------${NC}"
    echo ""
    for logfile in /var/log/apache2/access.log /var/log/nginx/access.log \
                   /var/log/httpd/access_log; do
        [[ -f "$logfile" ]] || continue
        echo -e "  ${CYAN}${logfile}:${NC}"
        tail -20 "$logfile" 2>/dev/null | \
        while IFS= read -r line; do
            local col="${GRAY}"
            echo "$line" | grep -qiE "\.php\?|cmd=|exec=|shell|/etc/passwd|/bin/bash|union.*select|<script" && col="${RED}"
            echo "$line" | grep -qE '" 4[0-9]{2} |" 5[0-9]{2} ' && col="${YELLOW}"
            echo -e "  ${col}${line}${NC}"
        done
        echo ""
    done

    pause
}

# --- 20 : Database Audit (MySQL / PostgreSQL) ---------------------------
module_20() {
    section_header "20 — DATABASE AUDIT (MySQL / PostgreSQL)"
    echo -e "  ${DGRAY}Conseil: [CRITICAL] Databases exposed on 0.0.0.0 are network-reachable.${NC}"
    echo -e "  ${DGRAY}root@% (any host) with no password = full data compromise.${NC}"
    echo -e "  ${DGRAY}[THREAT: Data exfiltration, credential theft, SQL injection pivot]${NC}"
    echo ""

    # --- MySQL / MariaDB ---
    echo -e "  ${DYELLOW}---- MySQL / MariaDB -----------------------------------------------${NC}"
    echo ""
    if pgrep -x mysqld &>/dev/null || pgrep -x mariadbd &>/dev/null; then
        echo -e "  ${GREEN}[✔] MySQL/MariaDB is running.${NC}"
        echo ""

        # bind-address check
        echo -e "  ${CYAN}bind-address:${NC}"
        grep -rh "bind-address\|bind_address" /etc/mysql/ /etc/my.cnf \
            /etc/my.cnf.d/ 2>/dev/null | grep -v "^#" | \
        while IFS= read -r line; do
            local col="${GREEN}"
            echo "$line" | grep -q "0\.0\.0\.0\|*" && col="${RED}"
            echo -e "    ${col}${line}${NC}"
        done

        echo ""
        echo -e "  ${CYAN}MySQL port exposure:${NC}"
        ss -tlnp 2>/dev/null | grep ":3306" | \
        while IFS= read -r line; do
            local col="${GREEN}"
            echo "$line" | grep -q "0\.0\.0\.0\|:::" && col="${RED}"
            echo -e "    ${col}${line}${NC}"
        done

        echo ""
        echo -e "  ${CYAN}MySQL user accounts (requires auth):${NC}"
        # Try socket auth first (root on Debian/Ubuntu)
        mysql -u root --connect-timeout=3 \
            -e "SELECT user,host,authentication_string!='' as has_password FROM mysql.user;" \
            2>/dev/null | \
        while IFS= read -r line; do
            local col="${GRAY}"
            echo "$line" | grep -qE "	%|0$" && col="${RED}"
            echo -e "    ${col}${line}${NC}"
        done || echo -e "    ${YELLOW}(requires MySQL root password)${NC}"

        echo ""
        echo -e "  ${CYAN}MySQL error log (last 10):${NC}"
        for logf in /var/log/mysql/error.log /var/log/mysqld.log; do
            [[ -f "$logf" ]] && tail -10 "$logf" 2>/dev/null | sed 's/^/    /'
        done
    else
        echo -e "  ${GRAY}MySQL/MariaDB not running.${NC}"
    fi

    echo ""
    # --- PostgreSQL ---
    echo -e "  ${DYELLOW}---- PostgreSQL ----------------------------------------------------${NC}"
    echo ""
    if pgrep -x postgres &>/dev/null; then
        echo -e "  ${GREEN}[✔] PostgreSQL is running.${NC}"
        echo ""

        echo -e "  ${CYAN}PostgreSQL port exposure:${NC}"
        ss -tlnp 2>/dev/null | grep ":5432" | \
        while IFS= read -r line; do
            local col="${GREEN}"
            echo "$line" | grep -q "0\.0\.0\.0\|:::" && col="${RED}"
            echo -e "    ${col}${line}${NC}"
        done

        echo ""
        echo -e "  ${CYAN}pg_hba.conf (authentication rules):${NC}"
        find /etc/postgresql -name "pg_hba.conf" 2>/dev/null | while IFS= read -r f; do
            echo -e "    ${CYAN}${f}${NC}"
            grep -v "^#\|^$" "$f" 2>/dev/null | \
            while IFS= read -r line; do
                local col="${GRAY}"
                echo "$line" | grep -qi "trust\|all.*all" && col="${RED}"
                echo -e "    ${col}${line}${NC}"
            done
        done

        echo ""
        echo -e "  ${CYAN}PostgreSQL roles (requires peer auth as postgres):${NC}"
        su -c "psql -c '\du'" postgres 2>/dev/null | sed 's/^/    /' || \
            echo -e "    ${YELLOW}(requires postgres OS user access)${NC}"
    else
        echo -e "  ${GRAY}PostgreSQL not running.${NC}"
    fi

    pause
}

# --- 21 : Docker & Kubernetes ------------------------------------------
module_21() {
    section_header "21 — CONTAINER AUDIT (Docker / Kubernetes)"
    echo -e "  ${DGRAY}Conseil: [CRITICAL] Privileged containers can escape to host root.${NC}"
    echo -e "  ${DGRAY}Exposed docker socket = full host compromise. K8s secrets in plaintext.${NC}"
    echo -e "  ${DGRAY}[THREAT: Container escape, privilege escalation, secret theft]${NC}"
    echo ""

    # --- Docker ---
    echo -e "  ${DYELLOW}---- Docker -------------------------------------------------------${NC}"
    echo ""
    if command -v docker &>/dev/null; then
        echo -e "  ${CYAN}Docker version:${NC} $(docker --version 2>/dev/null)"
        echo ""

        # Docker socket exposure
        if [[ -S /var/run/docker.sock ]]; then
            local sock_perms
            sock_perms=$(stat -c "%a %G" /var/run/docker.sock 2>/dev/null)
            echo -e "  ${CYAN}Docker socket:${NC} /var/run/docker.sock  ${YELLOW}[${sock_perms}]${NC}"
            ls -la /var/run/docker.sock 2>/dev/null | sed 's/^/    /'
        fi

        echo ""
        echo -e "  ${CYAN}Running containers:${NC}"
        docker ps 2>/dev/null | sed 's/^/  /' || echo -e "  ${GRAY}(no access)${NC}"

        echo ""
        echo -e "  ${CYAN}All containers (including stopped):${NC}"
        docker ps -a 2>/dev/null | sed 's/^/  /'

        echo ""
        echo -e "  ${CYAN}Images:${NC}"
        docker images 2>/dev/null | sed 's/^/  /'

        echo ""
        echo -e "  ${CYAN}Privileged / host-network containers:${NC}"
        docker ps -q 2>/dev/null | while IFS= read -r cid; do
            local priv net_mode name
            priv=$(docker inspect --format '{{.HostConfig.Privileged}}' "$cid" 2>/dev/null)
            net_mode=$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$cid" 2>/dev/null)
            name=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | tr -d '/')
            local col="${GRAY}"
            local flags=""
            [[ "$priv" == "true" ]] && col="${RED}" && flags+=" [PRIVILEGED]"
            [[ "$net_mode" == "host" ]] && col="${YELLOW}" && flags+=" [host-network]"
            [[ -n "$flags" ]] && echo -e "  ${col}${name}${flags}${NC}"
        done

        echo ""
        echo -e "  ${CYAN}Docker daemon config:${NC}"
        if [[ -f /etc/docker/daemon.json ]]; then
            cat /etc/docker/daemon.json 2>/dev/null | sed 's/^/    /'
        else
            echo -e "  ${GRAY}  /etc/docker/daemon.json not found (using defaults).${NC}"
        fi

        echo ""
        echo -e "  ${CYAN}Volumes (sensitive data):${NC}"
        ls -la /var/lib/docker/volumes 2>/dev/null | head -20 | sed 's/^/    /'
    else
        echo -e "  ${GRAY}Docker not installed.${NC}"
    fi

    echo ""
    # --- Kubernetes ---
    echo -e "  ${DYELLOW}---- Kubernetes (kubectl) ------------------------------------------${NC}"
    echo ""
    if command -v kubectl &>/dev/null; then
        echo -e "  ${CYAN}Pods (all namespaces):${NC}"
        kubectl get pods --all-namespaces 2>/dev/null | head -20 | sed 's/^/  /'
        echo ""
        echo -e "  ${CYAN}Services (exposed):${NC}"
        kubectl get svc --all-namespaces 2>/dev/null | grep -v "ClusterIP" | head -15 | sed 's/^/  /'
        echo ""
        echo -e "  ${CYAN}Secrets (all namespaces):${NC}"
        kubectl get secrets --all-namespaces 2>/dev/null | head -20 | \
        while IFS= read -r line; do
            local col="${GRAY}"
            echo "$line" | grep -qi "password\|token\|credential\|key\|secret" && col="${RED}"
            echo -e "  ${col}${line}${NC}"
        done
    else
        echo -e "  ${GRAY}kubectl not installed.${NC}"
    fi

    pause
}

# --- 22 : File Services Audit (FTP / Samba / NFS / Postfix) ------------
module_22() {
    section_header "22 — FILE & MAIL SERVICES (FTP / Samba / NFS / Postfix)"
    echo -e "  ${DGRAY}Conseil: [IMPORTANT] Anonymous FTP/SMB = unauthenticated access.${NC}"
    echo -e "  ${DGRAY}NFS world-export / open relay Postfix = data exposure or spam pivot.${NC}"
    echo -e "  ${DGRAY}[THREAT: Unauthenticated access, data exfiltration, open relay]${NC}"
    echo ""

    # --- FTP ---
    echo -e "  ${DYELLOW}---- FTP (vsftpd / proftpd) ----------------------------------------${NC}"
    echo ""
    if pgrep -xE "vsftpd|proftpd|pure-ftpd" &>/dev/null; then
        echo -e "  ${GREEN}[✔] FTP service is running.${NC}"
        echo ""
        for ftpconf in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf /etc/proftpd/proftpd.conf; do
            [[ -f "$ftpconf" ]] || continue
            echo -e "  ${CYAN}${ftpconf}:${NC}"
            grep -v "^#\|^$" "$ftpconf" 2>/dev/null | \
            while IFS= read -r line; do
                local col="${GRAY}"
                echo "$line" | grep -qi "anonymous_enable=YES\|anon_upload_enable=YES" && col="${RED}"
                echo -e "    ${col}${line}${NC}"
            done
            echo ""
        done
        local anon_ftp
        anon_ftp=$(grep -rhi "anonymous_enable=YES" /etc/vsftpd* /etc/proftpd* 2>/dev/null | wc -l)
        [[ $anon_ftp -gt 0 ]] && \
            echo -e "  ${RED}[!] Anonymous FTP is ENABLED — unauthenticated access possible!${NC}" || \
            echo -e "  ${GREEN}[✔] Anonymous FTP is disabled.${NC}"
    else
        echo -e "  ${GRAY}No FTP service running.${NC}"
    fi

    echo ""
    # --- Samba ---
    echo -e "  ${DYELLOW}---- Samba (SMB) ---------------------------------------------------${NC}"
    echo ""
    if pgrep -x smbd &>/dev/null; then
        echo -e "  ${GREEN}[✔] Samba is running.${NC}"
        echo ""
        echo -e "  ${CYAN}Active SMB sessions:${NC}"
        smbstatus 2>/dev/null | head -20 | sed 's/^/  /'
        echo ""
        echo -e "  ${CYAN}smb.conf (key settings):${NC}"
        if [[ -f /etc/samba/smb.conf ]]; then
            grep -v "^#\|^;\|^$" /etc/samba/smb.conf 2>/dev/null | \
            while IFS= read -r line; do
                local col="${GRAY}"
                echo "$line" | grep -qi "guest ok = yes\|public = yes" && col="${RED}"
                echo -e "    ${col}${line}${NC}"
            done
        fi
        local guest_smb
        guest_smb=$(grep -i "guest ok = yes\|public = yes" /etc/samba/smb.conf 2>/dev/null | wc -l)
        [[ $guest_smb -gt 0 ]] && \
            echo -e "  ${RED}[!] Samba guest/public shares detected!${NC}" || \
            echo -e "  ${GREEN}[✔] No guest Samba shares.${NC}"
    else
        echo -e "  ${GRAY}Samba not running.${NC}"
    fi

    echo ""
    # --- NFS ---
    echo -e "  ${DYELLOW}---- NFS -----------------------------------------------------------${NC}"
    echo ""
    if [[ -f /etc/exports ]] || pgrep -x nfsd &>/dev/null; then
        echo -e "  ${GREEN}[✔] NFS configured.${NC}"
        echo ""
        echo -e "  ${CYAN}/etc/exports:${NC}"
        grep -v "^#\|^$" /etc/exports 2>/dev/null | \
        while IFS= read -r line; do
            local col="${GRAY}"
            echo "$line" | grep -qE "\*\(|no_root_squash|world" && col="${RED}"
            echo -e "    ${col}${line}${NC}"
        done
        echo ""
        echo -e "  ${CYAN}Active NFS exports:${NC}"
        showmount -e localhost 2>/dev/null | sed 's/^/  /' || \
            exportfs -v 2>/dev/null | head -10 | sed 's/^/  /'
        local world_nfs
        world_nfs=$(grep -E "\*\(|no_root_squash" /etc/exports 2>/dev/null | wc -l)
        [[ $world_nfs -gt 0 ]] && \
            echo -e "  ${RED}[!] World-accessible or no_root_squash NFS exports detected!${NC}" || \
            echo -e "  ${GREEN}[✔] NFS exports appear restricted.${NC}"
    else
        echo -e "  ${GRAY}NFS not configured.${NC}"
    fi

    echo ""
    # --- Postfix ---
    echo -e "  ${DYELLOW}---- Postfix (mail) ------------------------------------------------${NC}"
    echo ""
    if pgrep -x master &>/dev/null && command -v postconf &>/dev/null; then
        echo -e "  ${GREEN}[✔] Postfix is running.${NC}"
        echo ""
        echo -e "  ${CYAN}Key postfix settings:${NC}"
        local relay_host mynetworks inet_int
        relay_host=$(postconf -h relayhost 2>/dev/null)
        mynetworks=$(postconf -h mynetworks 2>/dev/null)
        inet_int=$(postconf -h inet_interfaces 2>/dev/null)
        printf "    ${DGRAY}%-30s${NC}: ${WHITE}%s${NC}\n" "relayhost"      "${relay_host:-<none>}"
        printf "    ${DGRAY}%-30s${NC}: ${WHITE}%s${NC}\n" "mynetworks"     "${mynetworks}"
        printf "    ${DGRAY}%-30s${NC}: ${WHITE}%s${NC}\n" "inet_interfaces" "${inet_int}"
        echo ""
        echo "$inet_int" | grep -qi "all" && \
            echo -e "  ${RED}[!] Postfix listening on ALL interfaces — check for open relay!${NC}" || \
            echo -e "  ${GREEN}[✔] Postfix bound to loopback/specific interface.${NC}"

        echo ""
        echo -e "  ${CYAN}Open relay test (via postconf):${NC}"
        local smtpd_rec
        smtpd_rec=$(postconf -h smtpd_recipient_restrictions 2>/dev/null)
        echo -e "    ${GRAY}smtpd_recipient_restrictions:${NC} ${WHITE}${smtpd_rec}${NC}"
        echo "$smtpd_rec" | grep -qi "permit_all\|reject" || \
            echo -e "  ${YELLOW}[!] No explicit reject in recipient restrictions — verify open relay.${NC}"
    else
        echo -e "  ${GRAY}Postfix not running.${NC}"
    fi

    pause
}

# --- 23 : Network Recon (ARP / DNS / Hosts) ----------------------------
module_23() {
    section_header "23 — NETWORK RECON (ARP / DNS / Hosts)"
    echo -e "  ${DGRAY}Conseil: [IMPORTANT] Modified /etc/hosts = DNS spoofing.${NC}"
    echo -e "  ${DGRAY}Rogue DNS resolver = traffic hijacking. Suspicious ARP = MITM.${NC}"
    echo -e "  ${DGRAY}[THREAT: DNS spoofing, ARP poisoning, MITM, traffic redirection]${NC}"
    echo ""

    echo -e "  ${DYELLOW}---- /etc/hosts ----------------------------------------------------${NC}"
    echo ""
    grep -v "^#\|^$\|^127\.\|^::1\|^ff" /etc/hosts 2>/dev/null | \
    while IFS= read -r line; do
        local col="${YELLOW}"
        echo -e "  ${col}[custom]${NC} ${line}"
    done
    local custom_hosts
    custom_hosts=$(grep -cv "^#\|^$\|^127\.\|^::1\|^ff" /etc/hosts 2>/dev/null || echo 0)
    [[ $custom_hosts -eq 0 ]] && echo -e "  ${GREEN}[✔] No custom /etc/hosts entries.${NC}" || \
        echo -e "  ${YELLOW}[!] ${custom_hosts} custom host entries — verify for DNS spoofing.${NC}"

    echo ""
    echo -e "  ${DYELLOW}---- /etc/resolv.conf ---------------------------------------------${NC}"
    echo ""
    grep -v "^#\|^$" /etc/resolv.conf 2>/dev/null | \
    while IFS= read -r line; do
        local col="${GRAY}"
        # Flag non-standard DNS servers
        echo "$line" | grep -qvE "nameserver (8\.8\.[0-9]|1\.1\.1\.|9\.9\.9\.|127\.|192\.168\.|10\.|172\.)" && \
            echo "$line" | grep -q "nameserver" && col="${YELLOW}"
        echo -e "  ${col}${line}${NC}"
    done
    echo ""
    if command -v resolvectl &>/dev/null; then
        echo -e "  ${CYAN}systemd-resolved status:${NC}"
        resolvectl status 2>/dev/null | grep -E "DNS|DNSSEC|Server" | head -10 | sed 's/^/    /'
    fi

    echo ""
    echo -e "  ${DYELLOW}---- ARP table ----------------------------------------------------${NC}"
    echo ""
    if command -v arp &>/dev/null; then
        arp -a 2>/dev/null | sed 's/^/  /'
    else
        ip neigh show 2>/dev/null | sed 's/^/  /'
    fi

    echo ""
    echo -e "  ${DYELLOW}---- Duplicate MAC addresses (ARP poisoning indicator) -------------${NC}"
    echo ""
    local arp_output
    arp_output=$(arp -a 2>/dev/null || ip neigh show 2>/dev/null)
    local dup_macs
    dup_macs=$(echo "$arp_output" | grep -oE "([0-9a-f]{2}:){5}[0-9a-f]{2}" | \
               sort | uniq -d)
    if [[ -n "$dup_macs" ]]; then
        echo -e "  ${RED}[!] Duplicate MAC address detected (possible ARP poisoning):${NC}"
        echo "$dup_macs" | sed 's/^/    /'
    else
        echo -e "  ${GREEN}[✔] No duplicate MACs in ARP table.${NC}"
    fi

    echo ""
    echo -e "  ${DYELLOW}---- fail2ban status ----------------------------------------------${NC}"
    echo ""
    if command -v fail2ban-client &>/dev/null; then
        fail2ban-client status 2>/dev/null | sed 's/^/  /'
        echo ""
        # Per-jail status for ssh
        fail2ban-client status sshd 2>/dev/null | sed 's/^/  /' || \
        fail2ban-client status ssh  2>/dev/null | sed 's/^/  /'
    else
        echo -e "  ${YELLOW}[!] fail2ban not installed.${NC}"
        echo -e "  ${GRAY}    Install: apt install fail2ban${NC}"
    fi

    pause
}

# ---------------------------------------------------------------------------
#  AUDIT MODULES — RHEL/Fedora family (stubs — future work)
# ---------------------------------------------------------------------------

module_rhel_selinux() {
    section_header "SELINUX STATUS (RHEL/Fedora)"
    echo -e "  ${DGRAY}Conseil: SELinux enforcing = strong MAC protection.${NC}"
    echo -e "  ${DGRAY}Permissive or Disabled = SELinux provides no protection.${NC}"
    echo ""
    if command -v sestatus &>/dev/null; then
        sestatus 2>/dev/null | sed 's/^/  /'
    else
        error_msg "sestatus not found."
    fi
    pause
}

module_rhel_dnf_history() {
    section_header "DNF/YUM HISTORY (RHEL/Fedora)"
    echo ""
    if command -v dnf &>/dev/null; then
        dnf history list 2>/dev/null | head -30 | sed 's/^/  /'
    elif command -v yum &>/dev/null; then
        yum history list 2>/dev/null | head -30 | sed 's/^/  /'
    else
        error_msg "dnf/yum not found."
    fi
    pause
}

# ---------------------------------------------------------------------------
#  QUICK OVERVIEW (Dashboard)
# ---------------------------------------------------------------------------

show_dashboard() {
    clear
    echo ""
    echo -e "  ${DCYAN}TuxAudit v1.0${NC}  ${GRAY}·${NC}  ${WHITE}Quick Overview${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo ""

    # System
    echo -e "  ${DYELLOW}SYSTEM${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo ""
    local kernel arch uptime_val cpu_model ram_total ram_free board
    kernel=$(uname -r)
    arch=$(uname -m)
    uptime_val=$(uptime -p 2>/dev/null || uptime)
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ //')
    ram_total=$(grep MemTotal /proc/meminfo | awk '{printf "%.1f GB", $2/1024/1024}')
    ram_free=$(grep MemAvailable /proc/meminfo | awk '{printf "%.1f GB", $2/1024/1024}')
    board="N/A"
    [[ -f /proc/device-tree/model ]] && board=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)

    printf "    ${DGRAY}Hostname     :${NC} ${WHITE}%s${NC}\n" "$HOSTNAME_VAL"
    printf "    ${DGRAY}OS           :${NC} ${WHITE}%s${NC}\n" "$OS_PRETTY"
    printf "    ${DGRAY}Kernel       :${NC} ${WHITE}%s  (%s)${NC}\n" "$kernel" "$arch"
    printf "    ${DGRAY}CPU          :${NC} ${WHITE}%s${NC}\n" "$cpu_model"
    printf "    ${DGRAY}RAM          :${NC} ${WHITE}%s total / %s free${NC}\n" "$ram_total" "$ram_free"
    printf "    ${DGRAY}Uptime       :${NC} ${WHITE}%s${NC}\n" "$uptime_val"
    [[ "$board" != "N/A" ]] && \
    printf "    ${DGRAY}Pi Board     :${NC} ${GREEN}%s${NC}\n" "$board"

    # Disks (compact)
    echo ""
    echo -e "  ${DYELLOW}DISKS${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo ""
    df -h --output=source,size,used,pcent,target 2>/dev/null | grep -v tmpfs | grep -v udev | \
    while IFS= read -r line; do
        local pct_val
        pct_val=$(echo "$line" | awk '{print $4}' | tr -d '%')
        if [[ "$pct_val" =~ ^[0-9]+$ ]]; then
            local col="${GREEN}"
            (( pct_val > 75 )) && col="${YELLOW}"
            (( pct_val > 90 )) && col="${RED}"
            echo -e "    ${col}${line}${NC}"
        fi
    done

    # Accounts (compact)
    echo ""
    echo -e "  ${DYELLOW}LOCAL ACCOUNTS${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo ""
    while IFS=: read -r user _ uid _ _ home shell; do
        (( uid >= 1000 && uid < 65534 )) || [[ "$uid" -eq 0 ]] || continue
        local col="${GRAY}"
        local tag=""
        [[ "$uid" -eq 0 ]] && col="${RED}" && tag=" [root]"
        (( uid >= 1000 )) && col="${WHITE}"
        printf "    ${col}%-20s${NC} uid=%-6s shell=%-20s%s\n" "$user" "$uid" "$shell" "$tag"
    done < /etc/passwd

    # Last report
    echo ""
    echo -e "  ${DYELLOW}LAST REPORT${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo ""
    if [[ -n "$LAST_REPORT_PATH" && -f "$LAST_REPORT_PATH" ]]; then
        echo -e "    ${CYAN}${LAST_REPORT_PATH}${NC}"
    else
        echo -e "    ${GRAY}No HTML report generated yet.${NC}"
    fi

    echo ""
    read -rp "  Press [Enter] to return to the menu..." _
}

# ---------------------------------------------------------------------------
#  FULL AUDIT (run all modules sequentially)
# ---------------------------------------------------------------------------

run_full_audit() {
    clear
    echo ""
    echo -e "  ${DCYAN}TuxAudit v1.0${NC}  ${GRAY}·${NC}  ${WHITE}Full Audit${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo -e "  ${GRAY}Host  ${NC} ${WHITE}${HOSTNAME_VAL}${NC}  ${GRAY}·${NC}  ${WHITE}${OS_NAME} ${OS_VERSION}${NC}"
    echo ""
    echo -e "  ${GRAY}All 23 modules will run and scroll before you.${NC}"
    echo -e "  ${GRAY}Output is captured simultaneously for the HTML report.${NC}"
    echo ""

    local modules=(01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23)
    local total=${#modules[@]}
    local count=0
    local tmpfile

    # Override pause so it doesn't block during full audit
    local _orig_pause
    pause() { :; }

    for m in "${modules[@]}"; do
        (( count++ ))
        local mod_name
        mod_name=$(echo "${MODULE_META[$m]:-}" | cut -d'|' -f1)

        # ── Module banner ──────────────────────────────────────────────
        echo ""
        echo -e "  ${DCYAN}────────────────────────────────────${NC}"
        printf  "  ${WHITE}[%02d/%02d]${NC}  ${CYAN}%s${NC}\n" "$count" "$total" "${mod_name:-Module $m}"
        echo -e "  ${DCYAN}────────────────────────────────────${NC}"

        # ── Run module: capture to file first, then display ────────────
        # Process substitution (tee >(...)) has a race: bash continues before
        # the subshell finishes writing. We write to file first, display after.
        tmpfile=$(mktemp)
        "module_${m}" 2>/dev/null > "$tmpfile"

        # Display the raw output (with colours) to the terminal
        cat "$tmpfile"

        # Store cleaned version in REPORT_DATA (strip ANSI + decorative lines)
        REPORT_DATA["$m"]=$(sed 's/\x1B\[[0-9;]*[mK]//g' "$tmpfile" \
            | grep -v '^\s*$' \
            | grep -v '^  >> ' \
            | grep -v '^  -\{10,\}' \
            | grep -v '^\s*Press \[Enter\]' \
            | grep -v '^  Conseil:')

        rm -f "$tmpfile"
    done

    # Restore real pause
    pause() {
        echo ""
        read -rp "  Press [Enter] to return to the menu..." _
    }

    # ── All modules done ───────────────────────────────────────────────
    echo ""
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo -e "  ${GREEN}✔  All ${total} modules completed${NC}"
    echo ""

    # ── Auto-generate HTML report ──────────────────────────────────────
    echo -e "  ${YELLOW}[...] Generating HTML report...${NC}"
    echo ""

    local report_path="/tmp/tuxaudit_${HOSTNAME_VAL}_$(date +"%Y-%m-%d_%H-%M").html"
    generate_html_report "$report_path" 2>/dev/null

    if [[ -f "$report_path" ]]; then
        local fsize
        fsize=$(du -sh "$report_path" 2>/dev/null | cut -f1)
        LAST_REPORT_PATH="$report_path"
        echo -e "  ${DCYAN}────────────────────────────────────${NC}"
        echo -e "  ${GREEN}✔  HTML Report generated${NC}"
        echo ""
        echo -e "  ${CYAN}Path ${NC} ${WHITE}${report_path}${NC}"
        echo -e "  ${CYAN}Size ${NC} ${WHITE}${fsize}${NC}"
        echo -e "  ${CYAN}Score${NC} ${WHITE}${SCORE_MAP[GLOBAL]:-?}/10${NC}"
        echo ""
        echo -e "  ${GRAY}Open from another machine:${NC}"
        echo -e "  ${YELLOW}python3 -m http.server 8080 --directory /tmp${NC}"
        echo -e "  ${GRAY}http://$(hostname -I | awk '{print $1}'):8080/$(basename "$report_path")${NC}"
        echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    else
        echo -e "  ${RED}[!] Report generation failed.${NC}"
    fi

    echo ""
    read -rp "  Press [Enter] to return to the menu..." _
}


# ---------------------------------------------------------------------------
#  HTML REPORT ENGINE
# ---------------------------------------------------------------------------
# Global associative array to store captured output per module
declare -A REPORT_DATA   # key=module_id, value=raw text output
declare -A MODULE_META   # metadata: "name|shortname|category|anchor|advice_level|advice"

# Register module metadata (called once at init)
register_modules() {
    MODULE_META["01"]="OS Information|OS-INFO|System|os-info|INFO|Check OS version and kernel. An outdated kernel exposes known CVEs (Dirty COW, PolKit, sudo heap overflow). Verify EOL status. Long uptime (>30d) may indicate pending updates."
    MODULE_META["02"]="Users & Groups|USERS|Security|users|CRITICAL|Check for accounts with UID=0 other than root (backdoor). Accounts with empty passwords are critical risks. Watch for suspicious shells on service accounts."
    MODULE_META["03"]="Process List|PROC|Processes|processes|IMPORTANT|Check for processes running from /tmp, /dev/shm, /var/tmp or with random names. High CPU with no visible path = crypto-miner. [THREAT: Miner, RAT, rootkit, fileless malware]"
    MODULE_META["04"]="Network Interfaces|NET-IF|Network|netif|IMPORTANT|Unexpected interfaces (vpn, tun, tap) may indicate rogue tunnels or C2 channels. Promiscuous mode = possible sniffer. [THREAT: Exfiltration, pivoting, C2 tunnel]"
    MODULE_META["05"]="Open Ports & Connections|PORTS|Network|ports|CRITICAL|Unknown listening port = potential backdoor or C2. Port 0.0.0.0 (all interfaces) is more exposed than 127.0.0.1. [THREAT: Backdoor, C2 listener, lateral movement]"
    MODULE_META["06"]="Firewall Status|FIREWALL|Security|firewall|CRITICAL|A machine without a firewall is fully exposed. Default ACCEPT policy = all ports reachable. Verify INPUT/OUTPUT/FORWARD chains. [THREAT: Direct network exploitation]"
    MODULE_META["07"]="SSH Configuration|SSH|Security|ssh|CRITICAL|PermitRootLogin yes = direct root access risk. PasswordAuthentication yes = brute-force possible. Check AllowUsers and authorized_keys carefully."
    MODULE_META["08"]="Scheduled Tasks (Cron)|CRON|Security|cron|CRITICAL|Malware often persists via cron. Check for entries running from /tmp, curl/wget pipes, base64 commands. [THREAT: Backdoor persistence, miner scheduling, reverse shell]"
    MODULE_META["09"]="SUID / SGID Files|SUID|Security|suid|CRITICAL|SUID files run as root regardless of who executes them. Unknown SUID binaries in unusual paths = classic privilege escalation. [THREAT: GTFOBins, local privesc]"
    MODULE_META["10"]="Installed Packages|PKGS|Packages|packages|IMPORTANT|Look for unusual tools (nmap, netcat, socat, hydra, hashcat). Attackers often install recon tools after initial access. [THREAT: Attacker tooling, lateral movement]"
    MODULE_META["11"]="Services|SERVICES|Packages|services|IMPORTANT|Unnecessary running services increase attack surface. Check for services running from /tmp or with unusual names. [THREAT: Backdoor service, persistence]"
    MODULE_META["12"]="System Logs|LOGS|Security|logs|CRITICAL|Multiple failed SSH logins = brute-force attempt. sudo usage from unexpected users is suspicious. [THREAT: Brute-force, unauthorized escalation, intrusion traces]"
    MODULE_META["13"]="Wi-Fi Configuration|WIFI|Network|wifi|IMPORTANT|Saved Wi-Fi profiles may contain cleartext PSK. Rogue AP / evil-twin attacks are possible on open networks. [THREAT: Wi-Fi credential theft, evil twin]"
    MODULE_META["14"]="Time Source (NTP)|NTP|Network|ntp|INFO|Time drift > 5 min may indicate log tampering. Verify NTP source is a trusted server. Critical for SIEM correlation. [THREAT: Anti-forensics, log falsification]"
    MODULE_META["15"]="Kernel & Boot Security|KERNEL|System|kernel|CRITICAL|Check ASLR (randomize_va_space=2), dmesg restrictions, ptrace scope. Raspberry Pi: verify boot config. [THREAT: Kernel exploits, memory attacks, boot-time persistence]"
    MODULE_META["16"]="Bash History & IOCs|HISTORY|Forensics|history|CRITICAL|History reveals attacker post-exploitation steps. wget/curl piped to bash, base64 -d, /dev/tcp are C2 indicators. Files in /tmp and deleted-but-open FDs = rootkit/malware. [THREAT: C2 download, credential harvesting, fileless persistence]"
    MODULE_META["17"]="Kernel Modules & Rootkits|ROOTKIT|Forensics|rootkit|CRITICAL|Unknown kernel modules may be rootkits. chkrootkit/rkhunter detect known signatures and file tampering. dmesg anomalies reveal kernel-level attacks. [THREAT: Kernel rootkit, stealth backdoor, persistence]"
    MODULE_META["18"]="File Integrity|INTEGRITY|Forensics|integrity|CRITICAL|Modified system binaries = classic post-compromise indicator. debsums/rpm -Va verify checksums. Recently modified binaries in /bin /usr/bin are critical. [THREAT: Backdoored binaries, rootkit installation, supply chain]"
    MODULE_META["19"]="Web Stack Audit|WEB|Services|web|CRITICAL|eval()/base64_decode() in PHP = webshell. Files modified in last 48h in /var/www = backdoor. allow_url_include=On enables RFI. [THREAT: Webshell, RCE, PHP backdoor, file inclusion]"
    MODULE_META["20"]="Database Audit|DATABASE|Services|database|CRITICAL|DB exposed on 0.0.0.0 = network-accessible. root@% with no password = full compromise. pg_hba 'trust' = passwordless access. [THREAT: Data exfiltration, SQL injection pivot, credential theft]"
    MODULE_META["21"]="Container Audit|CONTAINERS|Services|containers|CRITICAL|Privileged containers can escape to host root. Exposed docker socket = full host compromise. K8s secrets stored in plaintext. [THREAT: Container escape, privilege escalation, secret exfiltration]"
    MODULE_META["22"]="File & Mail Services|FILESVCS|Services|filesvcs|IMPORTANT|Anonymous FTP/SMB = unauthenticated access. NFS world-export / no_root_squash = root access. Open relay Postfix = spam pivot. [THREAT: Unauthenticated access, data exfiltration, open relay]"
    MODULE_META["23"]="Network Recon|NET-RECON|Network|netrecon|IMPORTANT|Modified /etc/hosts = DNS spoofing. Rogue resolver = traffic hijacking. Duplicate MACs = ARP poisoning. fail2ban absent = no brute-force protection. [THREAT: DNS spoofing, ARP poisoning, MITM]"
}

# html_escape: escape special HTML chars
html_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    printf '%s' "$s"
}

# capture_module: run a module, capture its output into REPORT_DATA
# Strips ANSI codes and purely decorative lines (headers, conseil blocks, separators, pause prompts)
# All real command output (data lines) is preserved.
capture_module() {
    local id="$1"
    local output
    output=$(TERM=dumb "module_${id}" 2>/dev/null \
        | sed 's/\x1B\[[0-9;]*[mK]//g' \
        | grep -v '^\s*$' \
        | grep -v '^  >> ' \
        | grep -v '^  -\{10,\}' \
        | grep -v '^\s*Press \[Enter\]' \
        | grep -v '^  Conseil:' \
        | grep -v '^\s*\[CRITICAL\]\|\[IMPORTANT\]\|\[INFO\]\|\[THREAT' \
    )
    REPORT_DATA["$id"]="$output"
}

# ---------------------------------------------------------------------------
#  SECURITY SCORING ENGINE
# ---------------------------------------------------------------------------

# Returns a score 0-10 for a domain, plus detected issues
# Usage: compute_score <module_id> <output_text>
# Scores are stored in SCORE_MAP[domain] and ISSUES_MAP[domain]
declare -A SCORE_MAP
declare -A ISSUES_MAP

compute_security_scores() {
    # Reset
    SCORE_MAP=()
    ISSUES_MAP=()

    # ---- SSH (mod 07) ----
    local ssh_score=10
    local ssh_issues=""
    if [[ -n "${REPORT_DATA[07]}" ]]; then
        echo "${REPORT_DATA[07]}" | grep -qi "PermitRootLogin.*yes" && \
            ssh_score=$((ssh_score - 4)) && ssh_issues+="PermitRootLogin is enabled; "
        echo "${REPORT_DATA[07]}" | grep -qi "PasswordAuthentication.*yes" && \
            ssh_score=$((ssh_score - 2)) && ssh_issues+="PasswordAuthentication enabled; "
        echo "${REPORT_DATA[07]}" | grep -qi "PermitEmptyPasswords.*yes" && \
            ssh_score=$((ssh_score - 4)) && ssh_issues+="PermitEmptyPasswords enabled; "
        echo "${REPORT_DATA[07]}" | grep -qi "X11Forwarding.*yes" && \
            ssh_score=$((ssh_score - 1)) && ssh_issues+="X11Forwarding enabled; "
    fi
    [[ $ssh_score -lt 0 ]] && ssh_score=0
    SCORE_MAP["SSH"]=$ssh_score
    ISSUES_MAP["SSH"]="$ssh_issues"

    # ---- Firewall (mod 06) ----
    local fw_score=10
    local fw_issues=""
    if [[ -n "${REPORT_DATA[06]}" ]]; then
        echo "${REPORT_DATA[06]}" | grep -qi "Status: inactive\|Chain INPUT.*ACCEPT\|policy ACCEPT" && \
            fw_score=$((fw_score - 5)) && fw_issues+="Firewall inactive or permissive policy; "
        echo "${REPORT_DATA[06]}" | grep -qi "0 references\|no rules" && \
            fw_score=$((fw_score - 2)) && fw_issues+="No firewall rules defined; "
    fi
    [[ $fw_score -lt 0 ]] && fw_score=0
    SCORE_MAP["Firewall"]=$fw_score
    ISSUES_MAP["Firewall"]="$fw_issues"

    # ---- Users (mod 02) ----
    local usr_score=10
    local usr_issues=""
    if [[ -n "${REPORT_DATA[02]}" ]]; then
        echo "${REPORT_DATA[02]}" | grep -qi "Empty/locked passwords\|UID=0 !" && \
            usr_score=$((usr_score - 4)) && usr_issues+="Suspicious accounts or empty passwords; "
        # Count sudoers
        local sudo_count
        sudo_count=$(echo "${REPORT_DATA[02]}" | grep -c "NOPASSWD" 2>/dev/null || echo 0)
        [[ $sudo_count -gt 2 ]] && usr_score=$((usr_score - 2)) && \
            usr_issues+="${sudo_count} NOPASSWD sudo entries; "
    fi
    [[ $usr_score -lt 0 ]] && usr_score=0
    SCORE_MAP["Users"]=$usr_score
    ISSUES_MAP["Users"]="$usr_issues"

    # ---- Cron (mod 08) ----
    local cron_score=10
    local cron_issues=""
    if [[ -n "${REPORT_DATA[08]}" ]]; then
        echo "${REPORT_DATA[08]}" | grep -qiE "curl|wget|base64|/tmp|/dev/shm" && \
            cron_score=$((cron_score - 5)) && cron_issues+="Suspicious cron entries (curl/wget/base64/tmp); "
    fi
    [[ $cron_score -lt 0 ]] && cron_score=0
    SCORE_MAP["Cron"]=$cron_score
    ISSUES_MAP["Cron"]="$cron_issues"

    # ---- Kernel (mod 15) ----
    local kern_score=10
    local kern_issues=""
    if [[ -n "${REPORT_DATA[15]}" ]]; then
        echo "${REPORT_DATA[15]}" | grep -q "randomize_va_space.*0\|randomize_va_space.*1" && \
            kern_score=$((kern_score - 3)) && kern_issues+="ASLR not fully enabled (should be 2); "
        echo "${REPORT_DATA[15]}" | grep -q "ip_forward.*1" && \
            kern_score=$((kern_score - 1)) && kern_issues+="IP forwarding enabled; "
        echo "${REPORT_DATA[15]}" | grep -q "accept_redirects.*1" && \
            kern_score=$((kern_score - 2)) && kern_issues+="ICMP redirects accepted; "
    fi
    [[ $kern_score -lt 0 ]] && kern_score=0
    SCORE_MAP["Kernel"]=$kern_score
    ISSUES_MAP["Kernel"]="$kern_issues"

    # ---- SUID (mod 09) ----
    local suid_score=10
    local suid_issues=""
    if [[ -n "${REPORT_DATA[09]}" ]]; then
        local unusual_count
        unusual_count=$(echo "${REPORT_DATA[09]}" | grep -c "UNUSUAL" 2>/dev/null || echo 0)
        if [[ $unusual_count -gt 0 ]]; then
            suid_score=$((10 - unusual_count * 2))
            [[ $suid_score -lt 0 ]] && suid_score=0
            suid_issues+="${unusual_count} unusual SUID/SGID binaries; "
        fi
    fi
    SCORE_MAP["SUID"]=$suid_score
    ISSUES_MAP["SUID"]="$suid_issues"

    # ---- Network (mod 04+05) ----
    local net_score=10
    local net_issues=""
    if [[ -n "${REPORT_DATA[04]}" ]]; then
        echo "${REPORT_DATA[04]}" | grep -qi "PROMISC" && \
            net_score=$((net_score - 3)) && net_issues+="Promiscuous interface detected; "
    fi
    if [[ -n "${REPORT_DATA[05]}" ]]; then
        local listen_count
        listen_count=$(echo "${REPORT_DATA[05]}" | grep -c "0\.0\.0\.0\|::" 2>/dev/null || echo 0)
        [[ $listen_count -gt 10 ]] && net_score=$((net_score - 2)) && \
            net_issues+="${listen_count} services listening on all interfaces; "
    fi
    [[ $net_score -lt 0 ]] && net_score=0
    SCORE_MAP["Network"]=$net_score
    ISSUES_MAP["Network"]="$net_issues"

    # ---- Logs (mod 12) ----
    local log_score=10
    local log_issues=""
    if [[ -n "${REPORT_DATA[12]}" ]]; then
        local fail_count
        fail_count=$(echo "${REPORT_DATA[12]}" | grep -ci "failed\|invalid" 2>/dev/null || echo 0)
        [[ $fail_count -gt 20 ]] && log_score=$((log_score - 3)) && \
            log_issues+="High number of auth failures (${fail_count}); "
        [[ $fail_count -gt 100 ]] && log_score=$((log_score - 3)) && \
            log_issues+="Possible brute-force attack in progress; "
    fi
    [[ $log_score -lt 0 ]] && log_score=0
    SCORE_MAP["Logs"]=$log_score
    ISSUES_MAP["Logs"]="$log_issues"

    # ---- Packages (mod 10) ----
    local pkg_score=10
    local pkg_issues=""
    if [[ -n "${REPORT_DATA[10]}" ]]; then
        echo "${REPORT_DATA[10]}" | grep -qi "\[!\] Found:" && \
            pkg_score=$((pkg_score - 4)) && pkg_issues+="Suspicious/pentest tools installed; "
    fi
    SCORE_MAP["Packages"]=$pkg_score
    ISSUES_MAP["Packages"]="$pkg_issues"

    # ---- History / IOCs (mod 16) ----
    local hist_score=10
    local hist_issues=""
    if [[ -n "${REPORT_DATA[16]}" ]]; then
        echo "${REPORT_DATA[16]}" | grep -qi "suspicious\|INFECTED\|\[!\]" && \
            hist_score=$((hist_score - 4)) && hist_issues+="Suspicious commands in history; "
        echo "${REPORT_DATA[16]}" | grep -qi "deleted.*file\|rootkit" && \
            hist_score=$((hist_score - 3)) && hist_issues+="Deleted-but-open files detected; "
        local tmp_files
        tmp_files=$(echo "${REPORT_DATA[16]}" | grep -c "/tmp\|/dev/shm" 2>/dev/null || echo 0)
        [[ $tmp_files -gt 3 ]] && hist_score=$((hist_score - 2)) && \
            hist_issues+="Files in /tmp or /dev/shm; "
    fi
    [[ $hist_score -lt 0 ]] && hist_score=0
    SCORE_MAP["History"]=$hist_score
    ISSUES_MAP["History"]="$hist_issues"

    # ---- File Integrity (mod 18) ----
    local integ_score=10
    local integ_issues=""
    if [[ -n "${REPORT_DATA[18]}" ]]; then
        echo "${REPORT_DATA[18]}" | grep -qi "failure\|FAILED\|changed\|modified" && \
            integ_score=$((integ_score - 5)) && integ_issues+="File integrity check failures; "
        echo "${REPORT_DATA[18]}" | grep -qi "\[!\].*recently" && \
            integ_score=$((integ_score - 3)) && integ_issues+="Recently modified system binaries; "
    fi
    [[ $integ_score -lt 0 ]] && integ_score=0
    SCORE_MAP["Integrity"]=$integ_score
    ISSUES_MAP["Integrity"]="$integ_issues"

    # ---- Web (mod 19) ----
    local web_score=10
    local web_issues=""
    if [[ -n "${REPORT_DATA[19]}" ]]; then
        echo "${REPORT_DATA[19]}" | grep -qi "eval().*found\|base64_decode.*found\|shell exec.*found" && \
            web_score=$((web_score - 5)) && web_issues+="Webshell indicators detected; "
        echo "${REPORT_DATA[19]}" | grep -qi "allow_url_include.*On" && \
            web_score=$((web_score - 2)) && web_issues+="PHP allow_url_include enabled (RFI); "
    fi
    [[ $web_score -lt 0 ]] && web_score=0
    SCORE_MAP["Web"]=$web_score
    ISSUES_MAP["Web"]="$web_issues"

    # ---- Database (mod 20) ----
    local db_score=10
    local db_issues=""
    if [[ -n "${REPORT_DATA[20]}" ]]; then
        echo "${REPORT_DATA[20]}" | grep -qi "0\.0\.0\.0\|:::" && \
            db_score=$((db_score - 4)) && db_issues+="Database exposed on all interfaces; "
        echo "${REPORT_DATA[20]}" | grep -qi "trust\|@%\|has_password.*0" && \
            db_score=$((db_score - 3)) && db_issues+="Passwordless or wildcard DB accounts; "
    fi
    [[ $db_score -lt 0 ]] && db_score=0
    SCORE_MAP["Database"]=$db_score
    ISSUES_MAP["Database"]="$db_issues"

    # ---- Containers (mod 21) ----
    local cont_score=10
    local cont_issues=""
    if [[ -n "${REPORT_DATA[21]}" ]]; then
        echo "${REPORT_DATA[21]}" | grep -qi "\[PRIVILEGED\]" && \
            cont_score=$((cont_score - 4)) && cont_issues+="Privileged containers running; "
        echo "${REPORT_DATA[21]}" | grep -qi "host-network" && \
            cont_score=$((cont_score - 2)) && cont_issues+="Host-network containers detected; "
    fi
    [[ $cont_score -lt 0 ]] && cont_score=0
    SCORE_MAP["Containers"]=$cont_score
    ISSUES_MAP["Containers"]="$cont_issues"

    # ---- File Services (mod 22) ----
    local svc_score=10
    local svc_issues=""
    if [[ -n "${REPORT_DATA[22]}" ]]; then
        echo "${REPORT_DATA[22]}" | grep -qi "Anonymous FTP is ENABLED\|guest.*ENABLED\|world-accessible\|no_root_squash" && \
            svc_score=$((svc_score - 4)) && svc_issues+="Unauthenticated service access detected; "
        echo "${REPORT_DATA[22]}" | grep -qi "open relay\|listening on ALL" && \
            svc_score=$((svc_score - 3)) && svc_issues+="Possible mail open relay; "
    fi
    [[ $svc_score -lt 0 ]] && svc_score=0
    SCORE_MAP["Services"]=$svc_score
    ISSUES_MAP["Services"]="$svc_issues"

    # =========================================================================
    # GLOBAL SCORE — CVSS-inspired weighted formula with punitive ceilings
    # Identical logic to PowerAudit's Compute-SecurityScore:
    #
    #   Risk(domain)  = (weight/4) * ((10 - score) / 10)
    #                   ^impact        ^exploitability
    #   raw_score     = 10 - (sum_risk / sum_impact) * 10
    #   coverage      = min(1.0, nb_domains / 15)
    #   pre_ceiling   = raw_score * coverage + 5.0 * (1 - coverage)
    #   global_score  = min(ceiling, pre_ceiling)   rounded to 1 decimal
    #
    # Punitive ceilings — a single critical failure caps the whole score:
    #   weight>=4 AND score<=2  → ceiling 3.9  (disaster → Critical certain)
    #   weight>=4 AND score<=4  → ceiling 4.9  (critical failure → Critical)
    #   weight>=4 AND score<=6  → ceiling 6.4  (partial critical → Warning)
    #   weight>=3 AND score<=2  → ceiling 4.9  (major failure → Critical)
    #   weight>=3 AND score<=4  → ceiling 5.9  (important failure → Warning)
    # =========================================================================

    # Domain weights (mirrors PowerAudit: 4=critical, 3=important, 2=moderate, 1=minor)
    declare -A WEIGHT_MAP=(
        ["SSH"]=4
        ["Firewall"]=4
        ["Users"]=3
        ["Cron"]=3
        ["Kernel"]=3
        ["SUID"]=3
        ["Network"]=2
        ["Logs"]=3
        ["Packages"]=2
        ["History"]=3
        ["Integrity"]=4
        ["Web"]=4
        ["Database"]=4
        ["Containers"]=3
        ["Services"]=2
    )

    local total_risk=0      # accumulator (as float*1000 to avoid bc dependency)
    local total_impact=0    # accumulator (float*1000)
    local ceiling=100       # *10 representation: 100 = 10.0

    for domain in "${!SCORE_MAP[@]}"; do
        [[ "$domain" == "GLOBAL" ]] && continue
        local score="${SCORE_MAP[$domain]}"
        local weight="${WEIGHT_MAP[$domain]:-2}"

        # impact = weight/4  → *1000: weight*250
        local impact=$(( weight * 250 ))
        # exploitability = (10-score)/10 → *1000: (10-score)*100
        local exploit=$(( (10 - score) * 100 ))
        # domain_risk = impact * exploit / 1000000 → keep in *1000000 units
        local domain_risk=$(( impact * exploit ))   # units: 1e-6

        total_risk=$(( total_risk + domain_risk ))
        total_impact=$(( total_impact + impact ))

        # Punitive ceilings
        if   [[ $weight -ge 4 && $score -le 2 ]]; then [[ 39 -lt $ceiling ]] && ceiling=39
        elif [[ $weight -ge 4 && $score -le 4 ]]; then [[ 49 -lt $ceiling ]] && ceiling=49
        elif [[ $weight -ge 4 && $score -le 6 ]]; then [[ 64 -lt $ceiling ]] && ceiling=64
        elif [[ $weight -ge 3 && $score -le 2 ]]; then [[ 49 -lt $ceiling ]] && ceiling=49
        elif [[ $weight -ge 3 && $score -le 4 ]]; then [[ 59 -lt $ceiling ]] && ceiling=59
        fi
    done

    local global_score
    if [[ $total_impact -gt 0 ]]; then
        # avg_risk_1e6 = total_risk / (total_impact/1000)  [stay in integer]
        # raw_score = 10 - avg_risk*10 — computed via awk for float precision
        local nb_domains=${#WEIGHT_MAP[@]}
        global_score=$(awk -v tr="$total_risk" -v ti="$total_impact" \
                           -v ceil="$ceiling"  -v nd="$nb_domains" '
        BEGIN {
            avg_risk  = (tr / 1e6) / (ti / 1e3)   # both in their base units
            raw       = 10 - avg_risk * 10
            coverage  = (nd < 15) ? nd/15.0 : 1.0
            pre       = raw * coverage + 5.0 * (1 - coverage)
            ceil_f    = ceil / 10.0
            g         = (pre < ceil_f) ? pre : ceil_f
            if (g < 0) g = 0
            printf "%.1f", g
        }')
    else
        global_score="5.0"
    fi

    SCORE_MAP["GLOBAL"]=$global_score
}

# ---------------------------------------------------------------------------
#  REMEDIATION PLAN BUILDER
# ---------------------------------------------------------------------------

declare -a REMEDIATION_ACTIONS  # each entry: "prio|category|title|detail|command|ref|anchor"

add_remediation() {
    local prio="$1" cat="$2" title="$3" detail="$4" cmd="$5" ref="$6" anchor="$7"
    # Use ASCII Unit Separator (0x1F) as field delimiter — safe against | in bash commands
    local SEP=$'\x1f'
    REMEDIATION_ACTIONS+=("${prio}${SEP}${cat}${SEP}${title}${SEP}${detail}${SEP}${cmd}${SEP}${ref}${SEP}${anchor}")
}

generate_remediations() {
    REMEDIATION_ACTIONS=()

    # SSH
    if echo "${REPORT_DATA[07]:-}" | grep -qi "PermitRootLogin.*yes"; then
        add_remediation 1 "SSH" "Disable PermitRootLogin" \
            "Direct root SSH access is a critical risk. Disable it and use a named account with sudo." \
            "sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart sshd" \
            "CIS Benchmark SSH" "ssh"
    fi
    if echo "${REPORT_DATA[07]:-}" | grep -qi "PasswordAuthentication.*yes"; then
        add_remediation 1 "SSH" "Enforce SSH key authentication only" \
            "Password-based SSH is vulnerable to brute-force. Switch to public key authentication." \
            "sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && systemctl restart sshd" \
            "CIS Benchmark SSH" "ssh"
    fi
    if echo "${REPORT_DATA[07]:-}" | grep -qi "PermitEmptyPasswords.*yes"; then
        add_remediation 1 "SSH" "Disable PermitEmptyPasswords" \
            "Accounts with empty passwords via SSH is a critical vulnerability." \
            "sed -i 's/^PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config && systemctl restart sshd" \
            "CIS Benchmark" "ssh"
    fi

    # Firewall
    if echo "${REPORT_DATA[06]:-}" | grep -qi "Status: inactive"; then
        add_remediation 1 "Firewall" "Enable and configure UFW firewall" \
            "The firewall is currently inactive. All ports are exposed to the network." \
            "ufw default deny incoming && ufw default allow outgoing && ufw allow ssh && ufw enable" \
            "CIS Linux Benchmark" "firewall"
    fi

    # Users
    if echo "${REPORT_DATA[02]:-}" | grep -qi "Empty/locked passwords"; then
        add_remediation 1 "Users" "Remove empty password accounts" \
            "Accounts with empty passwords allow passwordless local login — a critical risk." \
            "# Identify: awk -F: '(\$2==\"\") {print \$1}' /etc/shadow\n# Force password change: passwd -e <username>" \
            "CIS Benchmark" "users"
    fi
    if echo "${REPORT_DATA[02]:-}" | grep -qi "UID=0 !"; then
        add_remediation 1 "Users" "Remove non-root accounts with UID=0" \
            "Any account with UID=0 has full root privileges. Only the root account should have UID=0." \
            "# Identify: awk -F: '(\$3==0 && \$1!=\"root\") {print \$1}' /etc/passwd\n# Remove: userdel <username>" \
            "MITRE T1078" "users"
    fi

    # Cron
    if echo "${REPORT_DATA[08]:-}" | grep -qiE "curl|wget|base64|/tmp|/dev/shm"; then
        add_remediation 1 "Persistence" "Investigate suspicious cron entries" \
            "Cron entries running curl/wget/base64 or from /tmp are a strong indicator of malware persistence." \
            "# List all cron jobs:\ncrontab -l && ls -la /etc/cron* /var/spool/cron/crontabs/\n# Remove suspicious entry: crontab -e" \
            "MITRE T1053.003" "cron"
    fi

    # Kernel
    if echo "${REPORT_DATA[15]:-}" | grep -q "randomize_va_space.*[01]$"; then
        add_remediation 2 "Kernel" "Enable full ASLR (randomize_va_space=2)" \
            "ASLR is not fully enabled. Full ASLR makes memory exploitation significantly harder." \
            "echo 2 > /proc/sys/kernel/randomize_va_space\necho 'kernel.randomize_va_space=2' >> /etc/sysctl.conf" \
            "CIS Linux Benchmark / NIST SP 800-123" "kernel"
    fi
    if echo "${REPORT_DATA[15]:-}" | grep -q "accept_redirects.*1"; then
        add_remediation 2 "Network" "Disable ICMP redirect acceptance" \
            "Accepting ICMP redirects allows an attacker to manipulate routing tables (MITM)." \
            "sysctl -w net.ipv4.conf.all.accept_redirects=0\necho 'net.ipv4.conf.all.accept_redirects=0' >> /etc/sysctl.conf" \
            "CIS Benchmark" "kernel"
    fi

    # SUID
    if echo "${REPORT_DATA[09]:-}" | grep -qi "UNUSUAL"; then
        add_remediation 2 "Security" "Investigate unusual SUID/SGID binaries" \
            "Unknown SUID binaries are a primary privilege escalation vector. Verify or remove them." \
            "# Remove SUID bit:\nchmod u-s /path/to/binary\n# Or remove the file if unnecessary" \
            "MITRE T1548.001 / GTFOBins" "suid"
    fi

    # Packages
    if echo "${REPORT_DATA[10]:-}" | grep -qi "\[!\] Found:"; then
        add_remediation 2 "Packages" "Remove attacker/pentest tools" \
            "Pentest tools (nmap, netcat, hydra...) found on a production system indicate possible compromise or policy violation." \
            "# Debian/Ubuntu: apt remove --purge <package>\n# RHEL/Fedora: dnf remove <package>" \
            "MITRE T1588" "packages"
    fi

    # Logs
    if [[ -n "${REPORT_DATA[12]:-}" ]]; then
        local fail_count
        fail_count=$(echo "${REPORT_DATA[12]}" | grep -ci "failed\|invalid" 2>/dev/null || echo 0)
        if [[ $fail_count -gt 20 ]]; then
            add_remediation 1 "Forensics" "Investigate brute-force SSH attempts (${fail_count} failures)" \
                "High number of authentication failures detected. Identify source IPs and block with fail2ban or firewall." \
                "# Install fail2ban:\napt install fail2ban -y\n# Or block manually:\niptables -A INPUT -s <IP> -j DROP" \
                "MITRE T1110" "logs"
        fi
    fi

    # General hardening (prio 3)
    add_remediation 3 "Hardening" "Install and configure fail2ban" \
        "fail2ban automatically blocks IPs after repeated authentication failures." \
        "apt install fail2ban -y && systemctl enable fail2ban && systemctl start fail2ban" \
        "CIS Benchmark" "ssh"
    add_remediation 3 "Hardening" "Enable automatic security updates" \
        "Ensure the system receives security patches automatically." \
        "apt install unattended-upgrades -y && dpkg-reconfigure unattended-upgrades" \
        "CIS Benchmark" "packages"
    add_remediation 3 "Hardening" "Restrict /tmp with noexec mount option" \
        "Mounting /tmp with noexec prevents malware from executing scripts placed there." \
        "# Add to /etc/fstab:\ntmpfs /tmp tmpfs defaults,noexec,nosuid,nodev 0 0\nmount -o remount /tmp" \
        "CIS Linux Benchmark" "os-info"

    # History / IOCs
    if echo "${REPORT_DATA[16]:-}" | grep -qi "suspicious\|\[!\]"; then
        add_remediation 1 "Forensics" "Investigate suspicious shell history entries" \
            "Suspicious commands (curl/wget piped to bash, base64, /dev/tcp) were found in shell history — hallmarks of initial access or C2 activity." \
            "# Review all histories:\nfind /root /home -name '.bash_history' -exec cat {} \;\n# Isolate machine if active compromise suspected" \
            "MITRE T1059.004" "history"
    fi
    if echo "${REPORT_DATA[16]:-}" | grep -qi "deleted.*file"; then
        add_remediation 1 "Forensics" "Investigate deleted-but-open files" \
            "Processes holding open deleted files are a strong rootkit/malware indicator." \
            "# List deleted-but-open files:\nlsof | grep deleted\n# Identify the process and investigate: ls -la /proc/<PID>/exe" \
            "MITRE T1036" "history"
    fi

    # File Integrity
    if echo "${REPORT_DATA[18]:-}" | grep -qi "failure\|FAILED\|changed"; then
        add_remediation 1 "Integrity" "Investigate package checksum failures" \
            "Checksums of installed package files do not match — this indicates files have been tampered with after installation." \
            "# Re-check manually:\ndebsums -c\n# Reinstall suspect package:\napt install --reinstall <package>" \
            "MITRE T1565.001" "integrity"
    fi

    # Web
    if echo "${REPORT_DATA[19]:-}" | grep -qi "eval().*found\|base64_decode.*found\|shell exec.*found"; then
        add_remediation 1 "Web" "Remove webshell files from web root" \
            "PHP files containing eval(), base64_decode(), system() or shell_exec() are webshell indicators. These grant remote code execution to attackers." \
            "# Find and review:\ngrep -rl 'eval\\|base64_decode\\|shell_exec' /var/www\n# Remove after confirmation:\nrm -f /path/to/suspicious.php" \
            "MITRE T1505.003" "web"
    fi
    if echo "${REPORT_DATA[19]:-}" | grep -qi "allow_url_include.*On"; then
        add_remediation 1 "Web" "Disable PHP allow_url_include" \
            "allow_url_include=On enables Remote File Inclusion (RFI) attacks — an attacker can include a remote PHP file for RCE." \
            "# Edit php.ini:\nsed -i 's/allow_url_include = On/allow_url_include = Off/' /etc/php/*/php.ini\nphp-fpm reload || apachectl restart" \
            "OWASP RFI / CIS PHP" "web"
    fi

    # Database
    if echo "${REPORT_DATA[20]:-}" | grep -qi "0\.0\.0\.0\|:::"; then
        add_remediation 1 "Database" "Restrict database binding to localhost" \
            "Database is listening on all interfaces — it is reachable from the network without firewall protection." \
            "# MySQL: edit /etc/mysql/my.cnf\nbind-address = 127.0.0.1\nsystemctl restart mysql\n# PostgreSQL: edit postgresql.conf\nlisten_addresses = 'localhost'" \
            "CIS MySQL/PostgreSQL Benchmark" "database"
    fi

    # Containers
    if echo "${REPORT_DATA[21]:-}" | grep -qi "\[PRIVILEGED\]"; then
        add_remediation 1 "Containers" "Remove privileged flag from containers" \
            "Privileged containers have unrestricted access to the host kernel and can easily escape to root on the host." \
            "# Inspect:\ndocker inspect <container> | grep Privileged\n# Recreate without --privileged flag" \
            "MITRE T1611 / CIS Docker Benchmark" "containers"
    fi

    # File Services
    if echo "${REPORT_DATA[22]:-}" | grep -qi "Anonymous FTP is ENABLED"; then
        add_remediation 1 "Services" "Disable anonymous FTP access" \
            "Anonymous FTP allows unauthenticated users to access the server — a critical misconfiguration." \
            "# Edit /etc/vsftpd.conf:\nsed -i 's/anonymous_enable=YES/anonymous_enable=NO/' /etc/vsftpd.conf\nsystemctl restart vsftpd" \
            "CIS FTP Benchmark" "filesvcs"
    fi
    if echo "${REPORT_DATA[22]:-}" | grep -qi "no_root_squash\|world-accessible"; then
        add_remediation 1 "Services" "Fix insecure NFS exports" \
            "NFS exports with no_root_squash or world (*) access allow remote root access to exported directories." \
            "# Edit /etc/exports:\n# Replace: /data *(rw,no_root_squash)\n# With: /data 192.168.1.0/24(rw,root_squash)\nexportfs -ra" \
            "CIS NFS Benchmark" "filesvcs"
    fi
}

# ---------------------------------------------------------------------------
#  MITRE ATT&CK LINUX MATRIX — HTML Generation
# ---------------------------------------------------------------------------
# Tactics: 13 columns (same as PowerAudit)
# Techniques: Linux-specific, mapped from audit module outputs
# Levels: 0=grey(not triggered) 1=possible(yellow) 2=high(orange) 3=critical(red)
# ---------------------------------------------------------------------------

generate_mitre_matrix() {

    # ---- Derive boolean flags from captured module outputs ------------------
    # Each flag is 0 or 1

    local d07="${REPORT_DATA[07]:-}"
    local d06="${REPORT_DATA[06]:-}"
    local d02="${REPORT_DATA[02]:-}"
    local d08="${REPORT_DATA[08]:-}"
    local d09="${REPORT_DATA[09]:-}"
    local d12="${REPORT_DATA[12]:-}"
    local d15="${REPORT_DATA[15]:-}"
    local d16="${REPORT_DATA[16]:-}"
    local d17="${REPORT_DATA[17]:-}"
    local d18="${REPORT_DATA[18]:-}"
    local d19="${REPORT_DATA[19]:-}"
    local d20="${REPORT_DATA[20]:-}"
    local d21="${REPORT_DATA[21]:-}"
    local d22="${REPORT_DATA[22]:-}"
    local d23="${REPORT_DATA[23]:-}"
    local d04="${REPORT_DATA[04]:-}"
    local d05="${REPORT_DATA[05]:-}"

    # Helper: returns 1 if pattern found in string, else 0
    flag_match() { echo "$1" | grep -qiE "$2" && echo 1 || echo 0; }
    flag_min()   { local a=$1 b=$2; echo $(( a < b ? a : b )); }
    flag_add()   { local s=$(( $1 + $2 )); echo $(( s > 3 ? 3 : s )); }
    flag_bool2() { echo $(( $1 * 2 > 3 ? 3 : $1 * 2 )); }
    flag_bool3() { echo $(( $1 * 3 > 3 ? 3 : $1 * 3 )); }

    # --- Authentication / Accounts ---
    local F_PermitRoot;     F_PermitRoot=$(flag_match    "$d07" "PermitRootLogin.*yes")
    local F_PasswordAuth;   F_PasswordAuth=$(flag_match  "$d07" "PasswordAuthentication.*yes")
    local F_EmptyPasswords; F_EmptyPasswords=$(flag_match "$d07" "PermitEmptyPasswords.*yes")
    local F_NoFail2ban;     F_NoFail2ban=$(flag_match    "$d23" "fail2ban.*not installed|fail2ban: not")
    local F_WeakAccounts;   F_WeakAccounts=$(flag_match  "$d02" "Empty.*password|UID=0 !")
    local F_SudoNoPasswd;   F_SudoNoPasswd=$(flag_match  "$d02" "NOPASSWD")
    local F_AuthKeys;       F_AuthKeys=$(flag_match      "$d07" "[0-9]+ key\(s\)")

    # --- Execution ---
    local F_SuspCron;       F_SuspCron=$(flag_match      "$d08" "curl|wget|bash|base64|/tmp|/dev/shm")
    local F_SuspHistory;    F_SuspHistory=$(flag_match   "$d16" "\[!\] suspicious")
    local F_WebShell;       F_WebShell=$(flag_match      "$d19" "eval\(\).*found|base64_decode.*found|shell_exec.*found")
    local F_SuspProc;       F_SuspProc=$(flag_match      "$d16" "SUSPICIOUS PATH|/tmp/\.|/dev/shm")
    local F_DockerSocket;   F_DockerSocket=$(flag_match  "$d21" "docker\.sock")

    # --- Persistence ---
    local F_SuspCronPersist; F_SuspCronPersist=$(flag_match "$d08" "curl|wget|bash|base64|/tmp|@reboot")
    local F_SuspSUID;       F_SuspSUID=$(flag_match      "$d09" "UNUSUAL")
    local F_TmpFiles;       F_TmpFiles=$(flag_match      "$d16" "Files in /tmp|/tmp/\.|/dev/shm")
    local F_HostsModified;  F_HostsModified=$(flag_match "$d23" "custom.*hosts|Custom /etc/hosts")
    local F_SSHKey;         F_SSHKey=$(flag_match        "$d07" "[0-9]+ key\(s\)")
    local F_WebPersist;     F_WebPersist=$(flag_match    "$d19" "eval\(\).*found|shell\.php|cmd\.php")

    # --- Privilege Escalation ---
    local F_ASLR;           F_ASLR=$(flag_match          "$d15" "randomize_va_space.*[01]$")
    local F_KernelCVE;      F_KernelCVE=$(flag_match     "$d17" "INFECTED|exploit.*detected|rootkit")
    local F_SudoMisconfig;  F_SudoMisconfig=$(flag_match "$d02" "NOPASSWD.*/bin/bash|NOPASSWD.*ALL")
    local F_SuspSUIDprivesc;F_SuspSUIDprivesc=$(flag_match "$d09" "UNUSUAL")
    local F_DockerPrivesc;  F_DockerPrivesc=$(flag_match "$d21" "PRIVILEGED")
    local F_IntegrityFail;  F_IntegrityFail=$(flag_match "$d18" "FAILED|failure|changed|modified")

    # --- Defense Evasion ---
    local F_NoFW;           F_NoFW=$(flag_match          "$d06" "inactive|not active")
    local F_RootkitDetect;  F_RootkitDetect=$(flag_match "$d17" "INFECTED|Warning.*modified|rootkit")
    local F_DeletedFiles;   F_DeletedFiles=$(flag_match  "$d16" "deleted.*file|Deleted-but-open")
    local F_AuditTamper;    F_AuditTamper=$(flag_match   "$d18" "FAILED")
    local F_PHPObfuscation; F_PHPObfuscation=$(flag_match "$d19" "base64_decode.*found|eval\(\).*found")
    local F_IpForward;      F_IpForward=$(flag_match     "$d15" "ip_forward.*1")

    # --- Credential Access ---
    local F_BruteForce;     F_BruteForce=$(flag_match    "$d12" "failed.*[0-9]{2,}|[0-9]{2,}.*failed")
    local F_Promiscuous;    F_Promiscuous=$(flag_match    "$d04" "PROMISC|promiscuous")
    local F_ARPPoison;      F_ARPPoison=$(flag_match      "$d23" "Duplicate MAC|ARP pois")
    local F_DBWeakCreds;    F_DBWeakCreds=$(flag_match   "$d20" "has_password.*0|trust|root.*%")
    local F_WifiCreds;      F_WifiCreds=$(flag_match     "$d13" "PSK:|open network")
    local F_HistoryCreds;   F_HistoryCreds=$(flag_match  "$d16" "\[!\] suspicious")

    # --- Discovery ---
    local F_ManyPorts;      F_ManyPorts=$(flag_match      "$d05" "0\.0\.0\.0:[0-9]")
    local F_NmapInstalled;  F_NmapInstalled=$(flag_match  "$d10" "Found.*nmap|nmap")
    local F_ExposedDB;      F_ExposedDB=$(flag_match      "$d20" "0\.0\.0\.0")
    local F_DockerInfo;     F_DockerInfo=$(flag_match     "$d21" "Docker version|Running")

    # --- Lateral Movement ---
    local F_SSHExposed;     F_SSHExposed=$(flag_match     "$d05" "0\.0\.0\.0:22|:::22")
    local F_SMBExposed;     F_SMBExposed=$(flag_match     "$d22" "Samba.*running|smbd")
    local F_NFSExposed;     F_NFSExposed=$(flag_match     "$d22" "no_root_squash|world-accessible|\*\(")
    local F_DockerLateral;  F_DockerLateral=$(flag_match  "$d21" "host-network|PRIVILEGED")

    # --- Collection ---
    local F_DBExposed;      F_DBExposed=$(flag_match      "$d20" "0\.0\.0\.0:[0-9]")
    local F_FTPAnon;        F_FTPAnon=$(flag_match        "$d22" "Anonymous FTP is ENABLED")
    local F_Webshell2;      F_Webshell2=$(flag_match      "$d19" "eval\(\).*found|shell_exec.*found")

    # --- C2 ---
    local F_C2History;      F_C2History=$(flag_match      "$d16" "dev/tcp|wget.*\||curl.*\||base64 -d.*bash")
    local F_DNSTamper;      F_DNSTamper=$(flag_match      "$d23" "custom.*hosts|Custom /etc/hosts")
    local F_IcmpRedirect;   F_IcmpRedirect=$(flag_match   "$d15" "accept_redirects.*1")

    # --- Exfiltration ---
    local F_OpenPorts;      F_OpenPorts=$(flag_match      "$d05" "0\.0\.0\.0")
    local F_NFSWorld;       F_NFSWorld=$(flag_match       "$d22" "no_root_squash|\*\(")
    local F_PostfixRelay;   F_PostfixRelay=$(flag_match   "$d22" "open relay|listening on ALL")

    # --- Impact ---
    local F_Rootkit;        F_Rootkit=$(flag_match        "$d17" "INFECTED|rootkit|Warning.*modified")
    local F_TmpExec;        F_TmpExec=$(flag_match        "$d16" "ELF|executable.*tmp")
    local F_PrivContainer;  F_PrivContainer=$(flag_match  "$d21" "PRIVILEGED")

    # ---- Compute composite levels (0-3) ------------------------------------
    local l_ssh_brute;      l_ssh_brute=$(flag_add $F_PasswordAuth $F_NoFail2ban)
    local l_rootauth;       l_rootauth=$(flag_min 3 $(( (F_PermitRoot + F_EmptyPasswords) * 2 )))
    local l_weakacct;       l_weakacct=$(flag_min 2 $(( F_WeakAccounts + F_SudoNoPasswd )))
    local l_cron_exec;      l_cron_exec=$(flag_bool3 $F_SuspCron)
    local l_webshell_exec;  l_webshell_exec=$(flag_bool3 $F_WebShell)
    local l_suid_priv;      l_suid_priv=$(flag_bool2 $F_SuspSUIDprivesc)
    local l_kernel_priv;    l_kernel_priv=$(flag_min 3 $(( (F_KernelCVE + F_IntegrityFail) * 2 )))
    local l_docker_priv;    l_docker_priv=$(flag_bool3 $F_DockerPrivesc)
    local l_no_fw;          l_no_fw=$(flag_bool2 $F_NoFW)
    local l_rootkit_evade;  l_rootkit_evade=$(flag_bool3 $F_RootkitDetect)
    local l_deleted_evade;  l_deleted_evade=$(flag_bool2 $F_DeletedFiles)
    local l_brute;          l_brute=$(flag_min 3 $(( (F_BruteForce + F_PasswordAuth + F_NoFail2ban) )))
    local l_sniff;          l_sniff=$(flag_min 3 $(( (F_Promiscuous + F_ARPPoison) * 2 )))
    local l_c2_hist;        l_c2_hist=$(flag_bool3 $F_C2History)
    local l_dns_tamper;     l_dns_tamper=$(flag_bool2 $F_DNSTamper)
    local l_ssh_lateral;    l_ssh_lateral=$(flag_min 2 $(( F_SSHExposed + F_PermitRoot )))
    local l_nfs_lateral;    l_nfs_lateral=$(flag_bool3 $F_NFSExposed)
    local l_docker_lateral; l_docker_lateral=$(flag_bool3 $F_DockerLateral)
    local l_webshell_coll;  l_webshell_coll=$(flag_bool3 $F_Webshell2)
    local l_db_coll;        l_db_coll=$(flag_bool3 $F_DBExposed)
    local l_anon_ftp;       l_anon_ftp=$(flag_bool3 $F_FTPAnon)
    local l_exfil_ports;    l_exfil_ports=$(flag_bool2 $F_OpenPorts)
    local l_exfil_nfs;      l_exfil_nfs=$(flag_bool3 $F_NFSWorld)
    local l_rootkit_impact; l_rootkit_impact=$(flag_bool3 $F_Rootkit)
    local l_php_obf;        l_php_obf=$(flag_bool2 $F_PHPObfuscation)
    local l_many_ports;     l_many_ports=$(flag_min 1 $F_ManyPorts)
    local l_nmap;           l_nmap=$(flag_min 1 $F_NmapInstalled)
    local l_docker_disco;   l_docker_disco=$(flag_min 1 $F_DockerInfo)
    local l_icmp;           l_icmp=$(flag_bool2 $F_IcmpRedirect)
    local l_creds_hist;     l_creds_hist=$(flag_bool2 $F_HistoryCreds)
    local l_integrity;      l_integrity=$(flag_bool3 $F_IntegrityFail)
    local l_sudo_privesc;   l_sudo_privesc=$(flag_bool3 $F_SudoMisconfig)
    local l_aslr;           l_aslr=$(flag_bool2 $F_ASLR)
    local l_ip_fwd;         l_ip_fwd=$(flag_bool2 $F_IpForward)
    local l_relay;          l_relay=$(flag_bool2 $F_PostfixRelay)

    # ---- Define technique matrix (13 tactics × N techniques) ---------------
    # Format per cell: "TID|ShortName|Level"
    # Tactics ordered as in PowerAudit
    local -A TACTIC_LABELS=(
        ["recon"]="Reconnaissance"
        ["initial"]="Initial Access"
        ["exec"]="Execution"
        ["persist"]="Persistence"
        ["privesc"]="Privilege Escalation"
        ["defense"]="Defense Evasion"
        ["creds"]="Credential Access"
        ["discovery"]="Discovery"
        ["lateral"]="Lateral Movement"
        ["collection"]="Collection"
        ["c2"]="C&amp;C"
        ["exfil"]="Exfiltration"
        ["impact"]="Impact"
    )
    local TACTIC_ORDER=("recon" "initial" "exec" "persist" "privesc" "defense" "creds" "discovery" "lateral" "collection" "c2" "exfil" "impact")

    # Techniques per tactic: "TID|Name|Level|anchor"
    local -A TECHNIQUES
    TECHNIQUES["recon"]="T1595|Active Scanning|${l_many_ports}|ports T1592|Host Recon|${l_nmap}|processes T1590|Net Topology|${l_ip_fwd}|netif T1046|Svc Discovery|${l_nmap}|ports T1018|Remote Sys Disc|${l_ssh_lateral}|netif"
    TECHNIQUES["initial"]="T1190|Exploit Public App|${l_kernel_priv}|kernel T1133|External Remote|${l_ssh_lateral}|ssh T1078|Valid Accounts|${l_rootauth}|users T1566|Phishing|0| T1199|Trusted Relship|${l_anon_ftp}|filesvcs T1195|Supply Chain|${l_integrity}|integrity"
    TECHNIQUES["exec"]="T1059.004|Unix Shell|${l_cron_exec}|cron T1059|Command Interp|${l_cron_exec}|history T1053.003|Cron Job|${l_cron_exec}|cron T1203|Exploit for Exec|${l_kernel_priv}|kernel T1609|Container Exec|${l_docker_priv}|containers T1059.006|Python|${l_webshell_exec}|web T1106|Native API|${l_rootkit_impact}|rootkit"
    TECHNIQUES["persist"]="T1053.003|Cron Job|${l_cron_exec}|cron T1098|Account Manip|${l_weakacct}|users T1136|Create Account|${l_weakacct}|users T1037|Boot/Init Script|${l_cron_exec}|cron T1505.003|Web Shell|${l_webshell_exec}|web T1547|Boot Autostart|${l_cron_exec}|kernel T1556|Modify Auth|${l_rootkit_impact}|rootkit T1543|Create/Mod Svc|${l_rootkit_evade}|services"
    TECHNIQUES["privesc"]="T1548.003|Sudo/Sudoers|${l_sudo_privesc}|users T1068|Exploit Vuln|${l_kernel_priv}|kernel T1611|Escape to Host|${l_docker_priv}|containers T1055|Process Inject|${l_rootkit_impact}|rootkit T1574|Hijack Exec|${l_suid_priv}|suid T1078|Valid Accounts|${l_rootauth}|users T1134|Token Manip|${l_rootkit_impact}|rootkit"
    TECHNIQUES["defense"]="T1070|Indicator Removal|${l_deleted_evade}|history T1562|Disable Security|${l_no_fw}|firewall T1027|Obfuscate Files|${l_php_obf}|web T1036|Masquerading|${l_rootkit_evade}|rootkit T1014|Rootkit|${l_rootkit_evade}|rootkit T1564|Hide Artifacts|${l_deleted_evade}|history T1218|Signed Binary|${l_suid_priv}|suid T1055|Process Inject|${l_rootkit_evade}|rootkit"
    TECHNIQUES["creds"]="T1110|Brute Force|${l_brute}|logs T1552|Unsecured Creds|${l_creds_hist}|history T1040|Net Sniffing|${l_sniff}|netif T1557|MITM|${l_sniff}|netrecon T1003|OS Cred Dumping|${l_rootkit_impact}|rootkit T1558|Steal Kerberos|0| T1539|Steal Web Sess|${l_webshell_coll}|web T1212|Exploit Cred Access|${l_kernel_priv}|kernel"
    TECHNIQUES["discovery"]="T1087|Account Discovery|${l_many_ports}|users T1046|Net Svc Scan|${l_nmap}|ports T1082|Sys Info Disc|${l_many_ports}|os-info T1083|File/Dir Disc|${l_weakacct}|suid T1057|Process Disc|${l_many_ports}|processes T1049|Sys Net Conns|${l_many_ports}|ports T1016|Net Config Disc|${l_many_ports}|netif T1613|Container Disc|${l_docker_disco}|containers"
    TECHNIQUES["lateral"]="T1021.004|SSH|${l_ssh_lateral}|ssh T1021.002|SMB/NFS|${l_nfs_lateral}|filesvcs T1080|Taint Shared|${l_nfs_lateral}|filesvcs T1570|Lateral Transfer|${l_docker_lateral}|containers T1550|Use Alt Auth|${l_rootauth}|users T1534|Internal Phish|0| T1563|Remote Svc Sess|${l_ssh_lateral}|ssh"
    TECHNIQUES["collection"]="T1560|Archive Data|${l_exfil_ports}|netif T1005|Data Local Sys|${l_webshell_coll}|web T1039|Data Net Share|${l_anon_ftp}|filesvcs T1074|Data Staged|${l_c2_hist}|history T1119|Auto Collection|${l_db_coll}|database T1056|Input Capture|${l_rootkit_impact}|rootkit T1113|Screen Capture|0|"
    TECHNIQUES["c2"]="T1071|App Layer Proto|${l_c2_hist}|history T1071.004|DNS C2|${l_dns_tamper}|netrecon T1090|Proxy|${l_icmp}|netrecon T1572|Proto Tunneling|${l_ip_fwd}|kernel T1095|Non-App Layer|${l_no_fw}|firewall T1219|Remote Access|${l_no_fw}|firewall T1105|Ingress Transfer|${l_c2_hist}|history"
    TECHNIQUES["exfil"]="T1041|Exfil over C2|${l_c2_hist}|history T1048|Exfil Alt Proto|${l_exfil_ports}|ports T1567|Exfil Web Svc|${l_webshell_coll}|web T1029|Scheduled Xfer|${l_cron_exec}|cron T1030|Data Xfer Limits|${l_exfil_ports}|netif T1020|Automated Exfil|${l_relay}|filesvcs"
    TECHNIQUES["impact"]="T1486|Data Encrypted|${l_rootkit_impact}|rootkit T1490|Inhibit Recovery|${l_rootkit_impact}|rootkit T1489|Service Stop|${l_no_fw}|services T1499|Endpoint DoS|${l_kernel_priv}|kernel T1491|Defacement|${l_webshell_exec}|web T1485|Data Destruction|${l_rootkit_impact}|rootkit T1565|Data Manip|${l_integrity}|integrity"

    # ---- Compute stats -------------------------------------------------------
    local total_tech=0 crit_count=0 warn_count=0 poss_count=0
    for tac in "${TACTIC_ORDER[@]}"; do
        local IFS_BAK=$IFS; IFS=' '
        for cell in ${TECHNIQUES[$tac]}; do
            IFS='|' read -r tid tname lvl anchor <<< "$cell"
            (( total_tech++ ))
            case $lvl in
                3) (( crit_count++ )) ;;
                2) (( warn_count++ )) ;;
                1) (( poss_count++ )) ;;
            esac
        done
        IFS=$IFS_BAK
    done
    local affected=$(( crit_count + warn_count + poss_count ))

    # ---- Build active flags list (for sidebar summary) ----------------------
    local flags_html=""
    _flag() {
        local label="$1" anchor="$2" active="$3"
        [[ "$active" -eq 1 ]] || return
        if [[ -n "$anchor" ]]; then
            flags_html+="<a href='#${anchor}' class='flag-item flag-link' onclick='event.preventDefault();navToAnchor(\"${anchor}\")' >${label} <span class='flag-arrow'>&#8594;</span></a>"
        else
            flags_html+="<span class='flag-item'>${label}</span>"
        fi
    }
    _flag "PermitRootLogin enabled"          "ssh"         $F_PermitRoot
    _flag "PasswordAuthentication enabled"   "ssh"         $F_PasswordAuth
    _flag "Empty SSH passwords allowed"      "ssh"         $F_EmptyPasswords
    _flag "fail2ban not installed"           "netrecon"    $F_NoFail2ban
    _flag "Suspicious accounts / UID=0"      "users"       $F_WeakAccounts
    _flag "NOPASSWD sudo"                    "users"       $F_SudoNoPasswd
    _flag "Suspicious cron entries"          "cron"        $F_SuspCron
    _flag "Suspicious shell history"         "history"     $F_SuspHistory
    _flag "Webshell indicators"              "web"         $F_WebShell
    _flag "Suspicious processes in /tmp"     "history"     $F_SuspProc
    _flag "Unusual SUID/SGID binaries"       "suid"        $F_SuspSUID
    _flag "Files in /tmp / /dev/shm"         "history"     $F_TmpFiles
    _flag "/etc/hosts modified"              "netrecon"    $F_HostsModified
    _flag "ASLR not fully enabled"           "kernel"      $F_ASLR
    _flag "Rootkit/tampering detected"       "rootkit"     $F_RootkitDetect
    _flag "Package integrity failures"       "integrity"   $F_IntegrityFail
    _flag "Deleted-but-open files"           "history"     $F_DeletedFiles
    _flag "Firewall inactive"                "firewall"    $F_NoFW
    _flag "Brute-force attempts"             "logs"        $F_BruteForce
    _flag "Promiscuous network interface"    "netif"       $F_Promiscuous
    _flag "ARP poisoning indicator"          "netrecon"    $F_ARPPoison
    _flag "Weak DB credentials / exposed"    "database"    $F_DBWeakCreds
    _flag "Anonymous FTP enabled"            "filesvcs"    $F_FTPAnon
    _flag "NFS world-accessible"             "filesvcs"    $F_NFSExposed
    _flag "Privileged Docker container"      "containers"  $F_DockerPrivesc
    _flag "C2 indicators in history"         "history"     $F_C2History
    _flag "IP forwarding enabled"            "kernel"      $F_IpForward
    _flag "ICMP redirects accepted"          "kernel"      $F_IcmpRedirect
    _flag "PHP obfuscation detected"         "web"         $F_PHPObfuscation
    [[ -z "$flags_html" ]] && flags_html="<span class='flag-none'>No significant vulnerability detected</span>"

    # ---- Build header row ---------------------------------------------------
    local header_cells=""
    for tac in "${TACTIC_ORDER[@]}"; do
        local label="${TACTIC_LABELS[$tac]}"
        # Count affected in this column
        local col_count=0
        for cell in ${TECHNIQUES[$tac]}; do
            IFS='|' read -r _t _n lvl _a <<< "$cell"
            [[ $lvl -gt 0 ]] && (( col_count++ ))
        done
        local badge=""
        [[ $col_count -gt 0 ]] && badge="<span class='tac-badge'>${col_count}</span>"
        header_cells+="<th class='tac-header'>${label}${badge}</th>"
    done

    # ---- Build body rows ----------------------------------------------------
    # Find max rows across tactics
    local max_rows=0
    for tac in "${TACTIC_ORDER[@]}"; do
        local cnt=0
        for cell in ${TECHNIQUES[$tac]}; do (( cnt++ )); done
        [[ $cnt -gt $max_rows ]] && max_rows=$cnt
    done

    # Pre-split each tactic into an indexed array
    declare -A TAC_CELLS
    for tac in "${TACTIC_ORDER[@]}"; do
        local idx=0
        for cell in ${TECHNIQUES[$tac]}; do
            TAC_CELLS["${tac}_${idx}"]="$cell"
            (( idx++ ))
        done
        TAC_CELLS["${tac}_count"]=$idx
    done

    local body_rows=""
    for (( row=0; row<max_rows; row++ )); do
        body_rows+="<tr>"
        for tac in "${TACTIC_ORDER[@]}"; do
            local cnt=${TAC_CELLS["${tac}_count"]:-0}
            if [[ $row -lt $cnt ]]; then
                local cell="${TAC_CELLS["${tac}_${row}"]}"
                IFS='|' read -r tid tname lvl anchor <<< "$cell"
                local cls="t-none"
                case $lvl in
                    3) cls="t-crit" ;;
                    2) cls="t-warn" ;;
                    1) cls="t-poss" ;;
                esac
                local url="https://attack.mitre.org/techniques/${tid/\./\//}/"
                local inner="<a href='${url}' target='_blank' rel='noopener'>${tname}<br><small>${tid}</small></a>"
                if [[ $lvl -gt 0 && -n "$anchor" ]]; then
                    inner+="<a href='#${anchor}' class='tech-ext-link' onclick='event.preventDefault();navToAnchor(\"${anchor}\")' title='Go to section'>&#8595;</a>"
                fi
                body_rows+="<td class='tech-cell ${cls}'>${inner}</td>"
            else
                body_rows+="<td class='tech-cell t-empty'></td>"
            fi
        done
        body_rows+="</tr>"
    done

    # ---- Assemble final HTML ------------------------------------------------
    printf '%s' "
<section id='mitre-matrix' class='audit-section mitre-section'>
  <div class='section-header'>
    <h2>MITRE ATT&amp;CK Linux Matrix</h2>
    <span class='badge'>ATT&amp;CK</span>
    <span class='cat-pill'>${affected} / ${total_tech} techniques impacted</span>
  </div>
  <div class='mitre-body'>
    <div class='mitre-stats'>
      <div class='ms-card crit'><div class='ms-num'>${crit_count}</div><div class='ms-lbl'>Critical</div></div>
      <div class='ms-card warn'><div class='ms-num'>${warn_count}</div><div class='ms-lbl'>High</div></div>
      <div class='ms-card poss'><div class='ms-num'>${poss_count}</div><div class='ms-lbl'>Possible</div></div>
      <div class='ms-card none'><div class='ms-num'>$((total_tech - affected))</div><div class='ms-lbl'>Not triggered</div></div>
    </div>
    <div class='mitre-legend'>
      <span class='leg-item t-crit'>Critical — vulnerabilities confirmed</span>
      <span class='leg-item t-warn'>High — favourable conditions</span>
      <span class='leg-item t-poss'>Possible — partial conditions</span>
      <span class='leg-item t-none'>Not triggered</span>
    </div>
    <div class='mitre-flags'>
      <div class='flags-title'>Detected vulnerabilities contributing to the matrix:</div>
      <div class='flags-list'>${flags_html}</div>
    </div>
    <div class='mitre-table-wrap'>
      <table class='mitre-table'>
        <thead><tr>${header_cells}</tr></thead>
        <tbody>${body_rows}</tbody>
      </table>
    </div>
    <div class='mitre-footer'>
      Based on MITRE ATT&amp;CK v14 Enterprise / Linux. Click a technique to open the ATT&amp;CK page.
      Colouring is automatic based on audit findings — not exhaustive.
    </div>
  </div>
</section>"
}

# ---------------------------------------------------------------------------
#  MITRE ATT&CK LINUX MATRIX — HTML Generation
# ---------------------------------------------------------------------------

generate_mitre_matrix() {
    # -----------------------------------------------------------------
    # STEP 1 — Vulnerability flags derived from audit results
    # -----------------------------------------------------------------
    # Each flag is 0 (absent) or 1 (detected)
    # Levels: 0=grey/none  1=possible/blue  2=high/orange  3=critical/red

    local f_PermitRoot=0  f_WeakSSH=0    f_EmptyPwd=0   f_SudoNoPwd=0
    local f_UID0Extra=0   f_SuspCron=0   f_SuspHistory=0 f_FilesInTmp=0
    local f_DeletedFD=0   f_Rootkit=0    f_IntegFail=0  f_RecentBin=0
    local f_Webshell=0    f_PhpRFI=0     f_DBExposed=0  f_DBNoAuth=0
    local f_PrivCont=0    f_DockerSock=0 f_AnonFTP=0    f_NFS_noroot=0
    local f_FWInactive=0  f_Promisc=0    f_ARP_dup=0    f_HostsMod=0
    local f_DnsSuspect=0  f_SuspPorts=0  f_ASLR_off=0   f_IPForward=0
    local f_SUID_extra=0  f_BruteScan=0  f_SuspPkgs=0   f_OpenRelay=0
    local f_KernelWarn=0  f_NoFail2ban=0 f_SuspProcess=0 f_LogCleaned=0

    # SSH (mod 07)
    echo "${REPORT_DATA[07]:-}" | grep -qi "PermitRootLogin.*yes"        && f_PermitRoot=1
    echo "${REPORT_DATA[07]:-}" | grep -qi "PasswordAuthentication.*yes" && f_WeakSSH=1
    echo "${REPORT_DATA[07]:-}" | grep -qi "PermitEmptyPasswords.*yes"   && f_EmptyPwd=1

    # Users (mod 02)
    echo "${REPORT_DATA[02]:-}" | grep -qi "Empty/locked passwords\|UID=0 !" && f_UID0Extra=1
    echo "${REPORT_DATA[02]:-}" | grep -qi "NOPASSWD"                        && f_SudoNoPwd=1
    echo "${REPORT_DATA[02]:-}" | grep -qi "empty password"                  && f_EmptyPwd=1

    # Cron (mod 08)
    echo "${REPORT_DATA[08]:-}" | grep -qiE "curl|wget|base64|/tmp|/dev/shm" && f_SuspCron=1

    # History / IOCs (mod 16)
    echo "${REPORT_DATA[16]:-}" | grep -qi "\[!\] suspicious"   && f_SuspHistory=1
    echo "${REPORT_DATA[16]:-}" | grep -qiE "/tmp|/dev/shm"     && f_FilesInTmp=1
    echo "${REPORT_DATA[16]:-}" | grep -qi "deleted.*file\|open.*deleted" && f_DeletedFD=1

    # Rootkit (mod 17)
    echo "${REPORT_DATA[17]:-}" | grep -qiE "INFECTED|Warning.*modified|Suspicious" && f_Rootkit=1
    echo "${REPORT_DATA[17]:-}" | grep -qiE "exploit attempt|overflow|null pointer"  && f_KernelWarn=1

    # Integrity (mod 18)
    echo "${REPORT_DATA[18]:-}" | grep -qi "failure\|FAILED\|changed" && f_IntegFail=1
    echo "${REPORT_DATA[18]:-}" | grep -qi "recently modified"        && f_RecentBin=1

    # Web (mod 19)
    echo "${REPORT_DATA[19]:-}" | grep -qiE "eval\(\).*found|base64_decode.*found|shell_exec.*found" && f_Webshell=1
    echo "${REPORT_DATA[19]:-}" | grep -qi "allow_url_include.*On"                                   && f_PhpRFI=1

    # Database (mod 20)
    echo "${REPORT_DATA[20]:-}" | grep -qE "0\.0\.0\.0:[0-9]" && f_DBExposed=1
    echo "${REPORT_DATA[20]:-}" | grep -qi "has_password.*0\|trust\|@%"  && f_DBNoAuth=1

    # Containers (mod 21)
    echo "${REPORT_DATA[21]:-}" | grep -qi "\[PRIVILEGED\]"            && f_PrivCont=1
    echo "${REPORT_DATA[21]:-}" | grep -qi "docker\.sock"              && f_DockerSock=1

    # File Services (mod 22)
    echo "${REPORT_DATA[22]:-}" | grep -qi "Anonymous FTP is ENABLED"                    && f_AnonFTP=1
    echo "${REPORT_DATA[22]:-}" | grep -qi "no_root_squash\|world-accessible"            && f_NFS_noroot=1
    echo "${REPORT_DATA[22]:-}" | grep -qi "open relay\|listening on ALL"                && f_OpenRelay=1

    # Firewall (mod 06)
    echo "${REPORT_DATA[06]:-}" | grep -qi "inactive\|not active" && f_FWInactive=1

    # Network (mod 04)
    echo "${REPORT_DATA[04]:-}" | grep -qi "PROMISC"              && f_Promisc=1

    # Network Recon (mod 23)
    echo "${REPORT_DATA[23]:-}" | grep -qi "Duplicate MAC\|ARP poisoning" && f_ARP_dup=1
    echo "${REPORT_DATA[23]:-}" | grep -qi "custom.*hosts\|\[!\].*host"   && f_HostsMod=1
    echo "${REPORT_DATA[23]:-}" | grep -qi "fail2ban.*not installed"      && f_NoFail2ban=1

    # Ports (mod 05)
    local port_count
    port_count=$(echo "${REPORT_DATA[05]:-}" | grep -c "LISTEN" 2>/dev/null || echo 0)
    [[ $port_count -gt 15 ]] && f_SuspPorts=1
    echo "${REPORT_DATA[05]:-}" | grep -qE "0\.0\.0\.0:(4444|1234|31337|8888|9999|6666)" && f_SuspPorts=1

    # Kernel (mod 15)
    echo "${REPORT_DATA[15]:-}" | grep -qE "randomize_va_space.*[01]$" && f_ASLR_off=1
    echo "${REPORT_DATA[15]:-}" | grep -q  "ip_forward.*1"             && f_IPForward=1

    # SUID (mod 09)
    echo "${REPORT_DATA[09]:-}" | grep -qi "UNUSUAL\|unusual"         && f_SUID_extra=1

    # Logs (mod 12)
    local fail_count
    fail_count=$(echo "${REPORT_DATA[12]:-}" | grep -ciE "failed|invalid" 2>/dev/null || echo 0)
    [[ $fail_count -gt 20 ]] && f_BruteScan=1
    echo "${REPORT_DATA[12]:-}" | grep -qi "accepted password.*root\|Accepted.*root" && f_PermitRoot=1

    # Packages (mod 10)
    echo "${REPORT_DATA[10]:-}" | grep -qi "\[!\] Found:" && f_SuspPkgs=1

    # Processes (mod 03)
    echo "${REPORT_DATA[03]:-}" | grep -qi "SUSPICIOUS PATH\|/tmp/\|/dev/shm" && f_SuspProcess=1

    # DNS (mod 23)
    echo "${REPORT_DATA[23]:-}" | grep -qiE "security-update.*[0-9]{1,3}\.[0-9]|dns.*modif" && f_DnsSuspect=1

    # -----------------------------------------------------------------
    # STEP 2 — Combined levels (0-3)
    # -----------------------------------------------------------------
    # Helper: min of two values
    _min() { echo $(( $1 < $2 ? $1 : $2 )); }
    _max() { echo $(( $1 > $2 ? $1 : $2 )); }

    local lSSH=$(    _min 3 $(( (f_PermitRoot + f_WeakSSH + f_EmptyPwd) * 2 )) )
    local lBrute=$(  _min 3 $(( f_BruteScan * 2 + f_WeakSSH + f_NoFail2ban )) )
    local lPrivEsc=$(  _min 3 $(( (f_SUID_extra + f_SudoNoPwd + f_UID0Extra + f_PrivCont) )) )
    local lPrivEsc3=$( _min 3 $(( (f_SUID_extra + f_UID0Extra) * 2 )) )
    local lCron=$(   _min 3 $(( f_SuspCron * 3 )) )
    local lPersist=$(  _min 2 $(( f_SuspCron + f_SuspHistory + f_Rootkit )) )
    local lPersist3=$( _min 3 $(( (f_SuspCron + f_Rootkit) * 2 )) )
    local lExec=$(   _min 3 $(( (f_SuspProcess + f_FilesInTmp + f_SuspHistory) * 2 )) )
    local lExec2=$(  _min 2 $(( f_SuspProcess + f_FilesInTmp )) )
    local lWebRCE=$( _min 3 $(( f_Webshell * 3 )) )
    local lWebRFI=$( _min 2 $(( (f_Webshell + f_PhpRFI) )) )
    local lDB=$(     _min 3 $(( (f_DBExposed + f_DBNoAuth) * 2 )) )
    local lInteg=$(  _min 3 $(( (f_IntegFail + f_Rootkit) * 2 )) )
    local lFW=$(     _min 3 $(( f_FWInactive * 3 )) )
    local lFW2=$(    _min 2 $(( f_FWInactive * 2 )) )
    local lARP=$(    _min 2 $(( f_ARP_dup * 2 + f_Promisc )) )
    local lARP3=$(   _min 3 $(( (f_ARP_dup + f_Promisc) * 2 )) )
    local lDNS=$(    _min 2 $(( f_HostsMod * 2 + f_DnsSuspect )) )
    local lDNS2=$(   _min 2 $(( f_DnsSuspect + f_HostsMod )) )
    local lIPFwd=$(  _min 2 $(( f_IPForward + f_FWInactive )) )
    local lNetwork=$(  _min 2 $(( f_IPForward + f_SuspPorts )) )
    local lAnon=$(   _min 3 $(( (f_AnonFTP + f_NFS_noroot) * 2 )) )
    local lDocker=$( _min 3 $(( (f_PrivCont + f_DockerSock) * 2 )) )
    local lKernel=$( _min 3 $(( (f_ASLR_off + f_KernelWarn) * 2 )) )
    local lKernel2=$(  _min 2 $(( f_ASLR_off + f_KernelWarn )) )
    local lSuid=$(   _min 3 $(( f_SUID_extra * 3 )) )
    local lPkgs=$(   _min 2 $(( f_SuspPkgs * 2 )) )
    local lPkgs3=$(  _min 3 $(( f_SuspPkgs * 3 )) )
    local lAny1=$(   _min 1 $(( f_FWInactive + f_PermitRoot + f_Webshell + f_Rootkit )) )

    # -----------------------------------------------------------------
    # STEP 3 — Techniques per tactic (ID, short name, level 0-3)
    # -----------------------------------------------------------------
    # Each entry: "ID|Name|Level"
    local -a t_recon t_init t_exec t_persist t_privesc t_defense t_cred \
             t_discov t_lateral t_collect t_c2 t_exfil t_impact

    t_recon=(
        "T1595|Active Scanning|${f_SuspPkgs}"
        "T1592|Host Recon|${lAny1}"
        "T1590|Network Recon|$( _min 1 $(( f_SuspPkgs + f_IPForward )) )"
        "T1046|Network Svc Scan|${lPkgs}"
        "T1018|Remote Sys Discov|${f_IPForward}"
        "T1040|Network Sniffing|$( _min 2 $(( f_Promisc * 2 )) )"
    )
    t_init=(
        "T1190|Exploit Public App|$( _min 2 $(( f_Webshell + f_PhpRFI )) )"
        "T1133|External Remote Svc|$( _min 2 $(( f_PermitRoot + f_WeakSSH )) )"
        "T1078|Valid Accounts|$( _min 3 $(( (f_PermitRoot + f_EmptyPwd) * 2 )) )"
        "T1566|Phishing|0"
        "T1195|Supply Chain|0"
        "T1199|Trusted Relationship|0"
        "T1091|Removable Media|0"
    )
    t_exec=(
        "T1059.004|Unix Shell|${lExec}"
        "T1059.006|Python|${lExec2}"
        "T1059.007|JavaScript|${f_SuspProcess}"
        "T1053.003|Cron|${lCron}"
        "T1203|Exploit for Execution|${lKernel2}"
        "T1569|System Services|${lPrivEsc}"
        "T1204|User Execution|${f_SuspHistory}"
        "T1059|Cmd/Script Interp|${lExec}"
        "T1106|Native API|${f_SuspProcess}"
    )
    t_persist=(
        "T1053.003|Cron Job|${lCron}"
        "T1543.002|Systemd Service|${lPersist}"
        "T1547.006|Kernel Modules|$( _min 3 $(( f_Rootkit * 3 )) )"
        "T1037.004|RC Scripts|${lPersist}"
        "T1136|Create Account|${f_UID0Extra}"
        "T1098|Account Manipulation|${f_SudoNoPwd}"
        "T1505.003|Web Shell|${lWebRCE}"
        "T1525|Implant Container Img|${f_PrivCont}"
        "T1574|Hijack Exec Flow|${f_SUID_extra}"
        "T1556|Modify Auth Process|${f_IntegFail}"
    )
    t_privesc=(
        "T1548.003|Sudo/Sudoedit|$( _min 3 $(( f_SudoNoPwd * 3 )) )"
        "T1068|Exploit Vulnerability|${lKernel}"
        "T1055|Process Injection|$( _min 2 $(( f_Rootkit + f_DeletedFD )) )"
        "T1611|Escape to Host|${lDocker}"
        "T1078|Valid Accounts|$( _min 2 $(( f_PermitRoot + f_EmptyPwd )) )"
        "T1574.006|Dynamic Linker|${f_SUID_extra}"
        "T1134|Access Token Manip|${f_Rootkit}"
        "T1484|Domain Policy Mod|0"
    )
    t_defense=(
        "T1562.001|Disable AV/FW|${lFW}"
        "T1070|Indicator Removal|$( _min 2 $(( f_DeletedFD + f_LogCleaned )) )"
        "T1027|Obfuscated Files|$( _min 2 $(( f_SuspHistory + f_FilesInTmp )) )"
        "T1055|Process Injection|$( _min 2 $(( f_Rootkit + f_DeletedFD )) )"
        "T1036|Masquerading|$( _min 2 $(( f_RecentBin + f_IntegFail )) )"
        "T1564.001|Hidden Files|$( _min 2 $(( f_FilesInTmp + f_DeletedFD )) )"
        "T1553|Subvert Trust Ctrl|${f_IntegFail}"
        "T1601|Modify System Img|$( _min 3 $(( f_Rootkit * 3 )) )"
        "T1014|Rootkit|$( _min 3 $(( f_Rootkit * 3 )) )"
        "T1542|Pre-OS Boot|${f_KernelWarn}"
    )
    t_cred=(
        "T1110|Brute Force|${lBrute}"
        "T1552.003|Bash History|$( _min 3 $(( f_SuspHistory * 3 )) )"
        "T1552.001|Credentials in Files|$( _min 2 $(( f_AnonFTP + f_NFS_noroot )) )"
        "T1040|Network Sniffing|${lARP}"
        "T1003|OS Credential Dump|$( _min 3 $(( f_Rootkit * 2 + f_EmptyPwd )) )"
        "T1558|Steal Kerberos Ticket|0"
        "T1539|Steal Web Session Cookie|${f_Webshell}"
        "T1555|Creds from Stores|${f_DBNoAuth}"
        "T1606|Forge Credentials|${f_DBNoAuth}"
    )
    t_discov=(
        "T1087|Account Discovery|$( _min 1 $(( f_WeakSSH + f_PermitRoot )) )"
        "T1082|System Info Disc|$( _min 1 $(( f_WeakSSH + f_SuspProcess )) )"
        "T1083|File/Dir Discovery|${f_AnonFTP}"
        "T1046|Network Svc Scan|${lPkgs}"
        "T1057|Process Discovery|${f_SuspProcess}"
        "T1016|Sys Network Config|$( _min 1 $(( f_IPForward + f_Promisc )) )"
        "T1049|Sys Network Conns|${f_SuspPorts}"
        "T1033|Sys Owner/User Disc|$( _min 1 $(( f_PermitRoot + f_SudoNoPwd )) )"
        "T1069|Permission Groups|${f_SudoNoPwd}"
        "T1007|System Service Disc|${f_SuspPkgs}"
    )
    t_lateral=(
        "T1021.004|SSH Lateral Mvt|$( _min 3 $(( (f_PermitRoot + f_WeakSSH) * 2 )) )"
        "T1021.001|Remote Desktop|0"
        "T1210|Exploit Remote Svc|${lKernel2}"
        "T1570|Lateral Tool Transfer|$( _min 2 $(( f_FWInactive + f_AnonFTP )) )"
        "T1534|Internal Spearphishing|0"
        "T1550|Use Alt Auth Material|$( _min 2 $(( f_EmptyPwd + f_WeakSSH )) )"
        "T1563|Remote Svc Session Hijack|$( _min 2 $(( f_PermitRoot + f_WeakSSH )) )"
        "T1080|Taint Shared Content|${f_NFS_noroot}"
    )
    t_collect=(
        "T1560|Archive Collected|${f_IPForward}"
        "T1005|Data from Local Sys|$( _min 2 $(( f_AnonFTP + f_NFS_noroot )) )"
        "T1039|Data from Net Share|${f_NFS_noroot}"
        "T1074|Data Staged|${f_FilesInTmp}"
        "T1119|Automated Collection|$( _min 2 $(( f_SuspCron + f_SuspHistory )) )"
        "T1056|Input Capture|${f_Rootkit}"
        "T1113|Screen Capture|${f_SuspProcess}"
        "T1530|Data from Cloud|${lDocker}"
    )
    t_c2=(
        "T1071.001|Web Protocols|${lFW2}"
        "T1071.004|DNS C2|${lDNS2}"
        "T1095|Non-App Layer Proto|${lFW}"
        "T1572|Protocol Tunneling|${lIPFwd}"
        "T1090|Proxy|$( _min 2 $(( f_HostsMod + f_DnsSuspect )) )"
        "T1219|Remote Access Tool|${lFW2}"
        "T1102|Web Service C2|${f_FWInactive}"
        "T1573|Encrypted Channel|${f_SuspProcess}"
        "T1105|Ingress Tool Transfer|$( _min 3 $(( f_SuspCron * 3 )) )"
        "T1008|Fallback Channels|${f_DnsSuspect}"
    )
    t_exfil=(
        "T1041|Exfil over C2|${lFW2}"
        "T1048|Exfil Alt Protocol|${lIPFwd}"
        "T1052|Exfil via Physical|0"
        "T1567|Exfil via Web Svc|${f_FWInactive}"
        "T1029|Scheduled Transfer|${f_SuspCron}"
        "T1020|Automated Exfil|$( _min 2 $(( f_SuspCron + f_SuspHistory )) )"
        "T1030|Data Transfer Limits|${f_IPForward}"
    )
    t_impact=(
        "T1486|Data Encrypted|$( _min 3 $(( (f_FWInactive + f_PermitRoot) * 2 )) )"
        "T1490|Inhibit Sys Recovery|${lKernel2}"
        "T1489|Service Stop|$( _min 2 $(( f_PrivCont + f_Rootkit )) )"
        "T1491.001|Defacement Local|${f_Webshell}"
        "T1499|Endpoint DoS|${lKernel2}"
        "T1485|Data Destruction|$( _min 2 $(( f_AnonFTP + f_NFS_noroot )) )"
        "T1496|Resource Hijacking|$( _min 3 $(( f_SuspProcess * 3 )) )"
        "T1561|Disk Wipe|${f_Rootkit}"
    )

    # -----------------------------------------------------------------
    # STEP 4 — Build active flags list for display
    # -----------------------------------------------------------------
    local flags_html=""
    declare -A flag_labels=(
        ["f_PermitRoot"]="PermitRootLogin enabled"
        ["f_WeakSSH"]="SSH password auth enabled"
        ["f_EmptyPwd"]="Empty password accounts"
        ["f_SudoNoPwd"]="sudo NOPASSWD entries"
        ["f_UID0Extra"]="Extra UID=0 account"
        ["f_SuspCron"]="Suspicious cron job (wget/bash/base64)"
        ["f_SuspHistory"]="Suspicious shell history (C2 IOC)"
        ["f_FilesInTmp"]="Executables in /tmp or /dev/shm"
        ["f_DeletedFD"]="Deleted-but-open files (rootkit indicator)"
        ["f_Rootkit"]="Rootkit indicators (chkrootkit/rkhunter)"
        ["f_IntegFail"]="Package checksum failures (tampered binaries)"
        ["f_RecentBin"]="Recently modified system binaries"
        ["f_Webshell"]="Webshell detected (eval/system in PHP)"
        ["f_PhpRFI"]="PHP allow_url_include=On (RFI risk)"
        ["f_DBExposed"]="Database exposed on all interfaces"
        ["f_DBNoAuth"]="Database passwordless or wildcard accounts"
        ["f_PrivCont"]="Privileged Docker container running"
        ["f_DockerSock"]="Docker socket accessible"
        ["f_AnonFTP"]="Anonymous FTP enabled"
        ["f_NFS_noroot"]="NFS no_root_squash or world export"
        ["f_FWInactive"]="Firewall inactive"
        ["f_Promisc"]="Promiscuous network interface"
        ["f_ARP_dup"]="Duplicate MAC (ARP poisoning)"
        ["f_HostsMod"]="Custom /etc/hosts entries"
        ["f_DnsSuspect"]="Suspicious DNS configuration"
        ["f_ASLR_off"]="ASLR disabled or partial"
        ["f_IPForward"]="IP forwarding enabled"
        ["f_SUID_extra"]="Unusual SUID/SGID binaries"
        ["f_BruteScan"]="Brute-force SSH attempts detected"
        ["f_SuspPkgs"]="Pentest/attack tools installed"
        ["f_OpenRelay"]="Mail open relay suspected"
        ["f_KernelWarn"]="Kernel exploit attempt (dmesg)"
        ["f_NoFail2ban"]="fail2ban not installed"
        ["f_SuspProcess"]="Suspicious process (from /tmp or /dev/shm)"
    )

    declare -A flag_anchors=(
        ["f_PermitRoot"]="ssh"        ["f_WeakSSH"]="ssh"
        ["f_EmptyPwd"]="users"        ["f_SudoNoPwd"]="users"
        ["f_UID0Extra"]="users"       ["f_SuspCron"]="cron"
        ["f_SuspHistory"]="history"   ["f_FilesInTmp"]="history"
        ["f_DeletedFD"]="history"     ["f_Rootkit"]="rootkit"
        ["f_IntegFail"]="integrity"   ["f_RecentBin"]="integrity"
        ["f_Webshell"]="web"          ["f_PhpRFI"]="web"
        ["f_DBExposed"]="database"    ["f_DBNoAuth"]="database"
        ["f_PrivCont"]="containers"   ["f_DockerSock"]="containers"
        ["f_AnonFTP"]="filesvcs"      ["f_NFS_noroot"]="filesvcs"
        ["f_FWInactive"]="firewall"   ["f_Promisc"]="netif"
        ["f_ARP_dup"]="netrecon"      ["f_HostsMod"]="netrecon"
        ["f_DnsSuspect"]="netrecon"   ["f_ASLR_off"]="kernel"
        ["f_IPForward"]="kernel"      ["f_SUID_extra"]="suid"
        ["f_BruteScan"]="logs"        ["f_SuspPkgs"]="packages"
        ["f_OpenRelay"]="filesvcs"    ["f_KernelWarn"]="rootkit"
        ["f_NoFail2ban"]="netrecon"   ["f_SuspProcess"]="processes"
    )

    for flag in f_PermitRoot f_WeakSSH f_EmptyPwd f_SudoNoPwd f_UID0Extra \
                f_SuspCron f_SuspHistory f_FilesInTmp f_DeletedFD f_Rootkit \
                f_IntegFail f_RecentBin f_Webshell f_PhpRFI f_DBExposed \
                f_DBNoAuth f_PrivCont f_DockerSock f_AnonFTP f_NFS_noroot \
                f_FWInactive f_Promisc f_ARP_dup f_HostsMod f_DnsSuspect \
                f_ASLR_off f_IPForward f_SUID_extra f_BruteScan f_SuspPkgs \
                f_OpenRelay f_KernelWarn f_NoFail2ban f_SuspProcess; do
        local val="${!flag}"
        [[ "$val" -eq 0 ]] && continue
        local lbl="${flag_labels[$flag]:-$flag}"
        local anc="${flag_anchors[$flag]:-}"
        if [[ -n "$anc" ]]; then
            flags_html+="<a href='#${anc}' class='flag-item flag-link' onclick='event.preventDefault();navToAnchor(\"${anc}\")' title='Go to section'>${lbl} <span class='flag-arrow'>&#8594;</span></a>"
        else
            flags_html+="<span class='flag-item'>${lbl}</span>"
        fi
    done
    [[ -z "$flags_html" ]] && flags_html="<span class='flag-none'>No significant vulnerability detected — good security posture.</span>"

    # -----------------------------------------------------------------
    # STEP 5 — Render matrix HTML
    # -----------------------------------------------------------------
    local -a tactic_names=( "Reconnaissance" "Initial Access" "Execution"
        "Persistence" "Priv. Escalation" "Defense Evasion"
        "Credential Access" "Discovery" "Lateral Movement"
        "Collection" "C2" "Exfiltration" "Impact" )
    local -a tactic_ids=( "TA0043" "TA0001" "TA0002" "TA0003" "TA0004"
        "TA0005" "TA0006" "TA0007" "TA0008" "TA0009"
        "TA0011" "TA0010" "TA0040" )
    local -a tactic_data=( "t_recon[@]" "t_init[@]" "t_exec[@]"
        "t_persist[@]" "t_privesc[@]" "t_defense[@]"
        "t_cred[@]" "t_discov[@]" "t_lateral[@]"
        "t_collect[@]" "t_c2[@]" "t_exfil[@]" "t_impact[@]" )

    local total_tech=0 crit_count=0 warn_count=0 poss_count=0

    # Pre-calculate column counts and max rows
    local -a col_counts=()
    for td in "${tactic_data[@]}"; do
        local arr=("${!td}")
        col_counts+=("${#arr[@]}")
        for entry in "${arr[@]}"; do
            local lvl="${entry##*|}"
            (( total_tech++ ))
            (( lvl >= 3 )) && (( crit_count++ ))
            (( lvl == 2 )) && (( warn_count++ ))
            (( lvl == 1 )) && (( poss_count++ ))
        done
    done
    local affected=$(( crit_count + warn_count + poss_count ))

    # Find max rows
    local max_rows=0
    for c in "${col_counts[@]}"; do (( c > max_rows )) && max_rows=$c; done

    # Build header row
    local header_html=""
    for i in "${!tactic_names[@]}"; do
        local tname="${tactic_names[$i]}"
        local tid="${tactic_ids[$i]}"
        local arr=("${!tactic_data[$i]}")
        local badge_count=0
        for entry in "${arr[@]}"; do
            local lvl="${entry##*|}"
            (( lvl > 0 )) && (( badge_count++ ))
        done
        local badge_html=""
        [[ $badge_count -gt 0 ]] && badge_html="<span class='tac-badge'>${badge_count}</span>"
        header_html+="<th class='tac-header' title='${tid}'>${tname}${badge_html}</th>"
    done

    # Build body rows
    local body_html=""
    for (( row=0; row<max_rows; row++ )); do
        body_html+="<tr>"
        for i in "${!tactic_data[@]}"; do
            local arr=("${!tactic_data[$i]}")
            if (( row < ${#arr[@]} )); then
                local entry="${arr[$row]}"
                local tech_id="${entry%%|*}"
                local rest="${entry#*|}"
                local tech_name="${rest%|*}"
                local lvl="${rest##*|}"
                local cls url
                case $lvl in
                    3) cls="t-crit" ;;
                    2) cls="t-warn" ;;
                    1) cls="t-poss" ;;
                    *) cls="t-none" ;;
                esac
                local tid_url="${tech_id//.//}"
                url="https://attack.mitre.org/techniques/${tid_url}/"
                body_html+="<td class='tech-cell ${cls}'>"
                body_html+="<a href='${url}' target='_blank' rel='noopener'>${tech_name}<br><small>${tech_id}</small></a>"
                body_html+="</td>"
            else
                body_html+="<td class='tech-cell t-empty'></td>"
            fi
        done
        body_html+="</tr>"
    done

    # -----------------------------------------------------------------
    # STEP 6 — Output the full section HTML
    # -----------------------------------------------------------------
    cat << MITRE_HTML
<section id='mitre-matrix' class='audit-section mitre-section'>
  <div class='section-header'>
    <h2>MITRE ATT&amp;CK Linux Matrix</h2>
    <span class='badge'>ATT&amp;CK</span>
    <span class='cat-pill'>${affected} / ${total_tech} techniques impacted</span>
  </div>
  <div class='mitre-body'>
    <div class='mitre-stats'>
      <div class='ms-card crit'><div class='ms-num'>${crit_count}</div><div class='ms-lbl'>Critical</div></div>
      <div class='ms-card warn'><div class='ms-num'>${warn_count}</div><div class='ms-lbl'>High</div></div>
      <div class='ms-card poss'><div class='ms-num'>${poss_count}</div><div class='ms-lbl'>Possible</div></div>
      <div class='ms-card none'><div class='ms-num'>$(( total_tech - affected ))</div><div class='ms-lbl'>Not triggered</div></div>
    </div>
    <div class='mitre-legend'>
      <span class='leg-item t-crit'>Critical — vulnerabilities confirmed</span>
      <span class='leg-item t-warn'>High — favorable conditions</span>
      <span class='leg-item t-poss'>Possible — partial conditions</span>
      <span class='leg-item t-none'>Not triggered</span>
    </div>
    <div class='mitre-flags'>
      <div class='flags-title'>Active vulnerability flags contributing to the matrix:</div>
      <div class='flags-list'>${flags_html}</div>
    </div>
    <div class='mitre-table-wrap'>
      <table class='mitre-table'>
        <thead><tr>${header_html}</tr></thead>
        <tbody>${body_html}</tbody>
      </table>
    </div>
    <div class='mitre-footer'>
      Based on MITRE ATT&amp;CK v14 Enterprise / Linux platform.
      Click any technique to open the ATT&amp;CK knowledge base.
      Coloring is automatic based on audit findings — not exhaustive.
    </div>
  </div>
</section>
MITRE_HTML
}

# ---------------------------------------------------------------------------
#  HTML REPORT GENERATOR
# ---------------------------------------------------------------------------

generate_html_report() {
    local report_path="$1"

    compute_security_scores
    generate_remediations

    local global_score="${SCORE_MAP[GLOBAL]:-5.0}"
    local score_color="#d29922"
    local score_label="Warning"
    # Use awk for float comparison — bash -lt truncates 4.9 to 4 (wrong)
    local score_grade
    score_grade=$(awk "BEGIN{
        s = $global_score + 0
        if (s >= 8) print \"good\"
        else if (s >= 5) print \"warn\"
        else print \"crit\"
    }")
    if   [[ "$score_grade" == "good" ]]; then score_color="#3fb950"; score_label="Good"
    elif [[ "$score_grade" == "crit" ]]; then score_color="#f85149"; score_label="Critical"
    fi

    # --- Build sidebar menu ---
    local menu_html=""
    local categories=("System" "Processes" "Network" "Security" "Packages" "Forensics" "Services")
    for cat in "${categories[@]}"; do
        local cat_id="cat-$(echo "$cat" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
        local items_html=""
        local item_count=0
        for id in $(echo "${!MODULE_META[@]}" | tr ' ' '\n' | sort); do
            local meta="${MODULE_META[$id]}"
            local m_cat
            m_cat=$(echo "$meta" | cut -d'|' -f3)
            [[ "$m_cat" != "$cat" ]] && continue
            [[ -z "${REPORT_DATA[$id]:-}" ]] && continue
            local m_name m_short m_anchor
            m_name=$(echo "$meta" | cut -d'|' -f1)
            m_short=$(echo "$meta" | cut -d'|' -f2)
            m_anchor=$(echo "$meta" | cut -d'|' -f4)
            items_html+="<li><a class='nav-link' href='#${m_anchor}' data-anchor='${m_anchor}'>"
            items_html+="<span class='nav-badge'>${m_short}</span> ${m_name}</a></li>"
            ((item_count++))
        done
        [[ $item_count -eq 0 ]] && continue
        menu_html+="<li class='cat-group'>"
        menu_html+="<button class='cat-toggle open' data-target='${cat_id}'><span class='cat-arrow'>&#9654;</span> ${cat} <span class='cat-count'>${item_count}</span></button>"
        menu_html+="<ul class='cat-items open' id='${cat_id}'>${items_html}</ul>"
        menu_html+="</li>"
    done
    # Extra: Dashboard + Remediation links
    menu_html+="<li class='cat-group'>"
    menu_html+="<button class='cat-toggle open' data-target='cat-report'><span class='cat-arrow'>&#9654;</span> Report <span class='cat-count'>3</span></button>"
    menu_html+="<ul class='cat-items open' id='cat-report'>"
    menu_html+="<li><a class='nav-link' href='#dashboard' data-anchor='dashboard'><span class='nav-badge'>DASH</span> Security Dashboard</a></li>"
    menu_html+="<li><a class='nav-link' href='#domain-analysis' data-anchor='domain-analysis'><span class='nav-badge'>DOM</span> Domain Analysis</a></li>"
    menu_html+="<li><a class='nav-link rem-link' href='#remediation' data-anchor='remediation'><span class='nav-badge'>REM</span> Remediation Plan</a></li>"
    menu_html+="</ul></li>"

    # --- Build domain score cards ---
    local domain_cards=""
    local domain_order=("SSH" "Firewall" "Users" "Cron" "Kernel" "SUID" "Network" "Logs" "Packages" "History" "Integrity" "Web" "Database" "Containers" "Services")
    local domain_anchors=("ssh" "firewall" "users" "cron" "kernel" "suid" "netif" "logs" "packages" "history" "integrity" "web" "database" "containers" "filesvcs")
    local i=0
    for domain in "${domain_order[@]}"; do
        local anchor="${domain_anchors[$i]}"
        ((i++))
        local dscore="${SCORE_MAP[$domain]:-10}"
        local dissues="${ISSUES_MAP[$domain]:-}"
        local dc="#3fb950"; local dlabel="Good"; local dclass="ok"
        # Float-safe comparison (bash -lt truncates 4.9→4)
        { awk "BEGIN{exit !($dscore < 8)}"; } && dc="#d29922" && dlabel="Warning" && dclass="warn"
        { awk "BEGIN{exit !($dscore < 5)}"; } && dc="#f85149" && dlabel="Critical" && dclass="crit"
        local dpct=$(( dscore * 10 ))
        local issues_html=""
        if [[ -n "$dissues" ]]; then
            # Split by "; " and build list
            while IFS=';' read -ra parts; do
                for part in "${parts[@]}"; do
                    part=$(echo "$part" | sed 's/^ *//')
                    [[ -n "$part" ]] && issues_html+="<li>${part}</li>"
                done
            done <<< "$dissues"
            issues_html="<ul class='domain-issues'>${issues_html}</ul>"
        else
            issues_html="<p class='domain-ok'>No issue detected</p>"
        fi
        domain_cards+="<a href='#${anchor}' class='domain-card ${dclass}' onclick='event.preventDefault();navToAnchor(\"${anchor}\")'>"
        domain_cards+="<div class='dc-top'><span class='dc-name'>${domain}</span><span class='dc-badge'>${dlabel}</span></div>"
        domain_cards+="<div class='dc-bar-wrap'><div class='dc-bar' style='width:${dpct}%;background:${dc}'></div></div>"
        domain_cards+="<div class='dc-score-line'><span class='dc-score' style='color:${dc}'>${dscore} / 10</span>${issues_html}</div>"
        domain_cards+="</a>"
    done

    # --- Build radar chart data (JS-injected via data attributes) ---
    local radar_points=""
    local radar_labels=""
    local radar_scores=""
    local radar_anchors_rem=""   # anchors into remediation section
    local domain_list_html=""

    # Emoji tips per domain (fun RPG-style improvement hints)
    declare -A domain_tips=(
        ["SSH"]="🔑 Switch to key-only auth and kick root out of SSH. Your server is not a welcome mat."
        ["Firewall"]="🧱 A firewall with zero rules is just a decorative wall. Add some bricks."
        ["Users"]="👤 Extra UID=0 accounts are like spare master keys under the doormat."
        ["Cron"]="⏰ wget|bash in a crontab is basically a self-destruct timer. Defuse it."
        ["Kernel"]="⚡ ASLR=0 is handing attackers a map of your memory. Turn it on."
        ["SUID"]="🎭 Unknown SUID binaries are actors with root credentials. Audit the cast."
        ["Network"]="📡 A promiscuous interface is silently reading everyone's mail. Unplug it."
        ["Logs"]="📋 300+ failed logins and no alert? Your logs are screaming into the void."
        ["Packages"]="🔧 pentest tools on a production server is like keeping lockpicks in reception."
        ["History"]="🕵️ Shell history is an attacker's diary. Time for some redaction."
        ["Integrity"]="🧬 Modified system binaries are the body-snatchers of Linux. Run debsums."
        ["Web"]="🕷️ eval(\$_POST) in PHP is basically a drive-through window for hackers."
        ["Database"]="🗄️ MySQL on 0.0.0.0 with no password is a public library with no locks."
        ["Containers"]="🐳 --privileged Docker is just running as root with extra steps."
        ["Services"]="📬 Anonymous FTP in 2025 is a time capsule from 1994. Close it."
    )

    local i=0
    for domain in "${domain_order[@]}"; do
        local anchor="${domain_anchors[$i]}"
        ((i++))
        local dscore="${SCORE_MAP[$domain]:-10}"
        local dissues="${ISSUES_MAP[$domain]:-}"
        local dc="#3fb950"; local dlabel="Good"; local dclass="ok"
        # Float-safe comparison (bash -lt truncates 4.9→4)
        { awk "BEGIN{exit !($dscore < 8)}"; } && dc="#d29922" && dlabel="Warning" && dclass="warn"
        { awk "BEGIN{exit !($dscore < 5)}"; } && dc="#f85149" && dlabel="Critical" && dclass="crit"

        # Radar data
        radar_scores+="${dscore},"
        radar_labels+="${domain}|${anchor},"
        radar_anchors_rem+="remediation,"

        # Issues for tooltip
        local tip_issues=""
        if [[ -n "$dissues" ]]; then
            tip_issues=$(echo "$dissues" | sed 's/; /\\n/g' | head -c 200)
        else
            tip_issues="No issue detected"
        fi

        # Domain list item
        local tip="${domain_tips[$domain]:-Investigate and harden this domain.}"
        domain_list_html+="<div class='dl-item ${dclass}' onclick='navToAnchor(\"${anchor}\")'>"
        domain_list_html+="<div class='dl-header'>"
        domain_list_html+="<span class='dl-dot' style='background:${dc}'></span>"
        domain_list_html+="<span class='dl-name'>${domain}</span>"
        domain_list_html+="<span class='dl-score' style='color:${dc}'>${dscore}/10</span>"
        domain_list_html+="</div>"
        domain_list_html+="<div class='dl-tip'>${tip}</div>"
        domain_list_html+="</div>"
    done
    # Trim trailing commas
    radar_scores="${radar_scores%,}"
    radar_labels="${radar_labels%,}"

    # --- Dashboard section ---
    local mod_count="${#REPORT_DATA[@]}"
    local gauge_offset
    gauge_offset=$(awk "BEGIN{printf \"%.1f\", 251.3 - ($global_score / 10.0 * 251.3)}")
    local dashboard_html="
<section id='dashboard' class='audit-section dashboard-section'>
  <div class='section-header'>
    <h2>Security Dashboard</h2>
    <span class='badge'>SUMMARY</span>
    <span class='cat-pill'>Report ${DATE_VAL}</span>
  </div>
  <div class='dashboard-body'>

    <!-- TOP ROW: gauge + radar + domain list -->
    <div class='dash-top-row'>

      <!-- LEFT: global score gauge + meta -->
      <div class='dash-left'>
        <div class='global-gauge'>
          <svg viewBox='0 0 200 140' width='200' height='140'>
            <!-- Background arc (neutral, theme-aware) -->
            <path d='M 20 105 A 80 80 0 0 1 180 105' fill='none' stroke='var(--bg4)' stroke-width='16' stroke-linecap='round'/>
            <!-- Filled arc: stroke-dasharray=full arc length, offset controls fill % -->
            <path d='M 20 105 A 80 80 0 0 1 180 105' fill='none' stroke='${score_color}' stroke-width='16' stroke-linecap='round'
              stroke-dasharray='251.3' stroke-dashoffset='${gauge_offset}' style='transition:stroke-dashoffset 1s ease'/>
            <text x='100' y='95' text-anchor='middle' font-size='32' font-weight='700' fill='${score_color}'>${global_score}</text>
            <text x='100' y='118' text-anchor='middle' font-size='12' fill='${score_color}' font-weight='600'>/ 10  ${score_label}</text>
          </svg>
        </div>
        <div class='global-meta'>
          <div class='gm-title'>Global Security Score</div>
          <div class='gm-machine'>${HOSTNAME_VAL}</div>
          <div class='gm-date'>${DATE_VAL} at ${HOUR_VAL}</div>
          <div class='gm-os'>${OS_PRETTY}</div>
          <div class='gm-modules'>${mod_count} modules analyzed</div>
          <div class='gm-legend'>
            <span class='leg crit'>0-4 Critical</span>
            <span class='leg warn'>5-7 Warning</span>
            <span class='leg ok'>8-10 Good</span>
          </div>
        </div>
      </div>

      <!-- CENTER: radar chart -->
      <div class='dash-radar'>
        <div class='radar-title'>Security Skill Tree</div>
        <canvas id='radar-canvas' width='380' height='380'
          data-scores='${radar_scores}'
          data-labels='${radar_labels}'>
        </canvas>
        <div id='radar-tooltip' class='radar-tooltip' style='display:none'></div>
      </div>

      <!-- RIGHT: domain list -->
      <div class='dash-right'>
        <div class='dl-title'>Domain Breakdown</div>
        <div class='dl-list'>${domain_list_html}</div>
      </div>

    </div><!-- /.dash-top-row -->

  </div><!-- /.dashboard-body -->
</section>

<section id='domain-analysis' class='audit-section domain-analysis-section'>
  <div class='section-header'>
    <h2>Domain Analysis</h2>
    <span class='badge'>DOMAINS</span>
    <span class='cat-pill'>click to navigate to section</span>
  </div>
  <div class='domain-analysis-body'>
    <div class='domains-grid'>${domain_cards}</div>
  </div>
</section>"

    # --- Build content sections ---
    local content_html=""
    content_html+="$dashboard_html"

    # MITRE ATT&CK Linux Matrix (generated from flags)
    local mitre_html
    mitre_html=$(generate_mitre_matrix)
    content_html+="$mitre_html"

    for id in $(echo "${!REPORT_DATA[@]}" | tr ' ' '\n' | sort); do
        local meta="${MODULE_META[$id]:-}"
        [[ -z "$meta" ]] && continue
        local m_name m_short m_cat m_anchor m_level m_advice
        m_name=$(echo "$meta"   | cut -d'|' -f1)
        m_short=$(echo "$meta"  | cut -d'|' -f2)
        m_cat=$(echo "$meta"    | cut -d'|' -f3)
        m_anchor=$(echo "$meta" | cut -d'|' -f4)
        m_level=$(echo "$meta"  | cut -d'|' -f5)
        m_advice=$(echo "$meta" | cut -d'|' -f6)

        # Conseil block
        local conseil_class="info" conseil_label="INFO"
        [[ "$m_level" == "CRITICAL" ]]  && conseil_class="critique"  && conseil_label="CRITICAL"
        [[ "$m_level" == "IMPORTANT" ]] && conseil_class="important" && conseil_label="IMPORTANT"

        local raw_escaped
        raw_escaped=$(html_escape "${REPORT_DATA[$id]}")

        content_html+="
<section id='${m_anchor}' class='audit-section'>
  <div class='section-header'>
    <h2>${m_name}</h2>
    <span class='badge'>${m_short}</span>
    <span class='cat-pill'>${m_cat}</span>
  </div>
  <div class='conseil ${conseil_class}'>
    <span class='conseil-icon'>${conseil_label}</span>
    <span class='conseil-text'>${m_advice}</span>
  </div>
  <pre class='output'>${raw_escaped}</pre>
</section>"
    done

    # --- Remediation Plan ---
    local p1_html="" p2_html="" p3_html=""
    local p1_count=0 p2_count=0 p3_count=0

    for action in "${REMEDIATION_ACTIONS[@]}"; do
        local prio cat title detail cmd ref anchor
        local SEP=$'\x1f'
        prio=$(echo "$action"   | cut -d"$SEP" -f1)
        cat=$(echo "$action"    | cut -d"$SEP" -f2)
        title=$(echo "$action"  | cut -d"$SEP" -f3)
        detail=$(echo "$action" | cut -d"$SEP" -f4)
        cmd=$(echo "$action"    | cut -d"$SEP" -f5)
        ref=$(echo "$action"    | cut -d"$SEP" -f6)
        anchor=$(echo "$action" | cut -d"$SEP" -f7)

        local cmd_html=""
        if [[ -n "$cmd" ]]; then
            local cmd_esc
            cmd_esc=$(html_escape "$cmd")
            cmd_html="<div class='rem-cmd'><span class='rem-cmd-label'>Command:</span><pre>${cmd_esc}</pre></div>"
        fi
        local ref_html=""
        [[ -n "$ref" ]] && ref_html="<span class='rem-ref'>Ref: ${ref}</span>"
        local anchor_html=""
        [[ -n "$anchor" ]] && anchor_html="<a href='#${anchor}' class='rem-section-link' onclick='event.preventDefault();navToAnchor(\"${anchor}\")'>&rarr; Go to section</a>"

        local pclass plabel
        case "$prio" in
            1) pclass="p1"; plabel="CRITICAL" ;;
            2) pclass="p2"; plabel="HIGH" ;;
            *) pclass="p3"; plabel="MEDIUM" ;;
        esac

        local card="<div class='rem-card ${pclass}'>
  <div class='rem-card-header'>
    <span class='rem-prio-badge'>${plabel}</span>
    <span class='rem-cat'>${cat}</span>
    <span class='rem-title'>${title}</span>
    ${anchor_html}
  </div>
  <div class='rem-body'>
    <p class='rem-detail'>${detail}</p>
    ${cmd_html}
    ${ref_html}
  </div>
</div>"

        case "$prio" in
            1) p1_html+="$card"; ((p1_count++)) ;;
            2) p2_html+="$card"; ((p2_count++)) ;;
            *) p3_html+="$card"; ((p3_count++)) ;;
        esac
    done

    local total_actions=$(( p1_count + p2_count + p3_count ))
    local p1_section="" p2_section="" p3_section=""
    [[ -n "$p1_html" ]] && p1_section="<div class='rem-group-title p1-title'>Critical actions — address immediately</div>${p1_html}"
    [[ -n "$p2_html" ]] && p2_section="<div class='rem-group-title p2-title'>High priority actions</div>${p2_html}"
    [[ -n "$p3_html" ]] && p3_section="<div class='rem-group-title p3-title'>Hardening actions</div>${p3_html}"

    local rem_html="
<section id='remediation' class='audit-section rem-section'>
  <div class='section-header'>
    <h2>Remediation Plan</h2>
    <span class='badge'>REMEDIATION</span>
    <span class='cat-pill'>${total_actions} actions identified</span>
  </div>
  <div class='rem-body-wrap'>
    <div class='rem-summary'>
      <div class='rem-sum-card p1'><span class='rem-sum-num'>${p1_count}</span><span class='rem-sum-lbl'>Critical</span></div>
      <div class='rem-sum-card p2'><span class='rem-sum-num'>${p2_count}</span><span class='rem-sum-lbl'>High priority</span></div>
      <div class='rem-sum-card p3'><span class='rem-sum-num'>${p3_count}</span><span class='rem-sum-lbl'>Medium</span></div>
      <div class='rem-disclaimer'>These remediations are automatically generated from detected findings. Test in a validation environment before deploying to production.</div>
    </div>
    ${p1_section}${p2_section}${p3_section}
  </div>
</section>"

    content_html+="$rem_html"

    # --- Assemble full HTML ---
    # --- Assemble full HTML (multi-part: quoted heredocs + printf for dynamic vars) ---
    # PART 1: Static HTML preamble (DOCTYPE + meta, no variable expansion)
    cat > "$report_path" << 'HTML_PART1'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
HTML_PART1
    # Dynamic: page title
    printf '<title>TuxAudit v1.0 -- %s -- %s</title>\n' "${HOSTNAME_VAL}" "${DATE_VAL}" >> "$report_path"
    # PART 2: Static CSS block + </head><body>
    cat >> "$report_path" << 'HTML_PART2'
<style>
:root {
  --bg:        #0d1117;
  --bg2:       #161b22;
  --bg3:       #21262d;
  --bg4:       #2d333b;
  --border:    #30363d;
  --accent:    #58a6ff;
  --accent2:   #3fb950;
  --warn:      #d29922;
  --danger:    #f85149;
  --text:      #c9d1d9;
  --dim:       #8b949e;
  --sidebar-w: 270px;
  --header-h:  58px;
}
/* ===== LIGHT THEME ===== */
body.light {
  --bg:      #f6f8fa;
  --bg2:     #ffffff;
  --bg3:     #f0f2f5;
  --bg4:     #e4e8ec;
  --border:  #d0d7de;
  --accent:  #0969da;
  --accent2: #1a7f37;
  --warn:    #9a6700;
  --danger:  #cf222e;
  --text:    #1f2328;
  --dim:     #57606a;
}
body.light pre.output                { color: #116329; }
body.light .nav-link.active          { background: rgba(9,105,218,.08); }
body.light .nav-link.mitre-link      { color: #cf222e; }
body.light .nav-link.mitre-link.active { background: rgba(207,34,46,.08); }
body.light .nav-link.rem-link        { color: #9a6700; }
body.light .nav-link.rem-link.active { background: rgba(154,103,0,.08); }
body.light .audit-section            { box-shadow: 0 1px 3px rgba(0,0,0,.08); }
body.light .tux-svg                  { filter: drop-shadow(0 1px 3px rgba(9,105,218,.25)); }
body.light .t-crit a { background:rgba(207,34,46,.12);  color:#82071e; border-color:rgba(207,34,46,.35); }
body.light .t-warn a { background:rgba(154,103,0,.12);  color:#7d4e00; border-color:rgba(154,103,0,.35); }
body.light .t-poss a { background:rgba(9,105,218,.10);  color:#0550ae; border-color:rgba(9,105,218,.30); }
body.light .t-none a { background:var(--bg3); color:var(--dim); border-color:var(--border); }
body.light .flag-item { background:rgba(207,34,46,.08); color:#82071e; border-color:rgba(207,34,46,.2); }
body.light a.flag-link:hover { background:rgba(207,34,46,.18); border-color:rgba(207,34,46,.4); color:#6e011a; }
body.light .conseil.critique  { background:rgba(207,34,46,.06); border-color:rgba(207,34,46,.25); color:#82071e; }
body.light .conseil.important { background:rgba(154,103,0,.06); border-color:rgba(154,103,0,.25); color:#7d4e00; }
body.light .conseil.info      { background:rgba(9,105,218,.05); border-color:rgba(9,105,218,.2);  color:#0550ae; }
body.light .conseil.critique  .conseil-icon { background:rgba(207,34,46,.15); color:#cf222e; border-color:rgba(207,34,46,.3); }
body.light .conseil.important .conseil-icon { background:rgba(154,103,0,.15); color:#9a6700; border-color:rgba(154,103,0,.3); }
body.light .conseil.info      .conseil-icon { background:rgba(9,105,218,.12); color:#0969da; border-color:rgba(9,105,218,.25); }
body.light .rem-card.p1 { border-left-color:#cf222e; }
body.light .rem-card.p2 { border-left-color:#9a6700; }
body.light .rem-card.p3 { border-left-color:#0969da; }
body.light .rem-cmd     { background:var(--bg3); }
body.light .rem-cmd pre { color:#0550ae; }
body.light .domain-card.crit { border-left-color:#cf222e; }
body.light .domain-card.warn { border-left-color:#9a6700; }
body.light .domain-card.ok   { border-left-color:#1a7f37; }
/* Theme toggle button */
#theme-toggle {
  background: var(--bg3);
  border: 1px solid var(--border);
  border-radius: 20px;
  padding: 4px 10px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: .75rem;
  font-weight: 600;
  color: var(--dim);
  transition: background .15s, border-color .15s, color .15s;
  white-space: nowrap;
  flex-shrink: 0;
}
#theme-toggle:hover { border-color: var(--accent); color: var(--accent); }
#theme-toggle .th-icon { font-size: .9rem; line-height: 1; }
#theme-toggle .th-label { font-size: .68rem; }
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
html{scroll-behavior:smooth}
body{font-family:'Segoe UI',system-ui,-apple-system,sans-serif;background:var(--bg);color:var(--text);line-height:1.5}
::-webkit-scrollbar{width:5px;height:5px}
::-webkit-scrollbar-track{background:var(--bg)}
::-webkit-scrollbar-thumb{background:var(--bg4);border-radius:3px}
::-webkit-scrollbar-thumb:hover{background:var(--dim)}

/* HEADER */
#header{position:fixed;top:0;left:0;right:0;height:var(--header-h);background:var(--bg2);border-bottom:1px solid var(--border);display:flex;align-items:center;padding:0 18px;gap:10px;z-index:200}
.header-logo{display:flex;align-items:center;gap:10px;white-space:nowrap;flex-shrink:0}
.tux-svg{width:28px;height:34px;flex-shrink:0;filter:drop-shadow(0 1px 3px rgba(88,166,255,.3))}
.logo-text{font-size:1.05rem;font-weight:700;color:var(--accent)}
.logo-ver{color:var(--dim);font-weight:400;font-size:.82rem;margin-left:2px}
.pill{background:var(--bg3);border:1px solid var(--border);border-radius:20px;padding:2px 11px;font-size:.72rem;color:var(--dim);white-space:nowrap}
.pill strong{color:var(--text)}
.header-right{margin-left:auto;display:flex;align-items:center;gap:8px}
#search-input{background:var(--bg3);border:1px solid var(--border);border-radius:6px;padding:4px 10px;color:var(--text);font-size:.78rem;width:180px;outline:none;transition:border-color .2s}
#search-input:focus{border-color:var(--accent)}
#search-input::placeholder{color:var(--dim)}
.header-nav{display:flex;align-items:center;gap:4px;margin-left:8px}
.hn-link{font-size:.75rem;font-weight:600;padding:4px 12px;border-radius:5px;text-decoration:none;border:1px solid transparent;transition:background .15s,border-color .15s,color .15s;white-space:nowrap}
.hn-link:hover{background:var(--bg3);border-color:var(--border)}
.hn-dash{color:var(--accent)}.hn-dash:hover{border-color:var(--accent)}
.hn-rem{color:#d29922}.hn-rem:hover{border-color:#d29922;background:rgba(210,153,34,.08)}
.hn-mitre{color:#f85149}.hn-mitre:hover{border-color:#f85149;background:rgba(248,81,73,.08)}
.hn-link.hn-active{background:var(--bg3);border-color:currentColor}

/* SIDEBAR */
#sidebar{position:fixed;top:var(--header-h);left:0;bottom:0;width:var(--sidebar-w);background:var(--bg2);border-right:1px solid var(--border);overflow-y:auto;z-index:100;display:flex;flex-direction:column}
#sidebar-top{padding:10px 12px 6px;border-bottom:1px solid var(--border);font-size:.68rem;color:var(--dim);display:flex;justify-content:space-between;align-items:center}
#sidebar-top strong{color:var(--accent);font-size:.8rem}
#expand-all,#collapse-all{background:none;border:1px solid var(--border);border-radius:4px;color:var(--dim);font-size:.68rem;padding:2px 7px;cursor:pointer;transition:all .15s}
#expand-all:hover,#collapse-all:hover{border-color:var(--accent);color:var(--accent)}
#sidebar nav{flex:1;overflow-y:auto;padding:6px 0 20px}
#sidebar ul{list-style:none}
.cat-group{margin:3px 0}
.cat-toggle{width:100%;background:none;border:none;cursor:pointer;display:flex;align-items:center;gap:7px;padding:6px 14px;color:var(--dim);font-size:.7rem;font-weight:700;letter-spacing:.08em;text-transform:uppercase;text-align:left;transition:color .15s}
.cat-toggle:hover{color:var(--text)}
.cat-arrow{font-size:.55rem;transition:transform .2s;display:inline-block;color:var(--dim)}
.cat-toggle.open .cat-arrow{transform:rotate(90deg)}
.cat-count{margin-left:auto;background:var(--bg3);border:1px solid var(--border);border-radius:10px;padding:0 6px;font-size:.65rem;color:var(--dim)}
.cat-items{display:none;padding-left:4px}
.cat-items.open{display:block}
.cat-items li{position:relative}
.nav-link{display:flex;align-items:center;gap:7px;padding:5px 14px 5px 18px;color:var(--dim);text-decoration:none;font-size:.78rem;border-left:2px solid transparent;transition:background .12s,color .12s,border-color .12s;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.nav-link:hover{background:var(--bg3);color:var(--text);border-left-color:var(--bg4)}
.nav-link.active{background:rgba(88,166,255,.08);color:var(--accent);border-left-color:var(--accent)}
.nav-badge{flex-shrink:0;background:var(--bg3);border:1px solid var(--border);border-radius:3px;padding:0 5px;font-size:.62rem;font-family:monospace;color:var(--accent)}
.nav-link.active .nav-badge{background:rgba(88,166,255,.15);border-color:var(--accent)}
.nav-link.rem-link{color:#d29922}
.nav-link.rem-link:hover{color:#d29922;border-left-color:#d29922}
.nav-link.rem-link.active{color:#d29922;border-left-color:#d29922;background:rgba(210,153,34,.08)}
.nav-link.hidden-search{display:none}

/* CONTENT */
#content{margin-left:var(--sidebar-w);margin-top:var(--header-h);padding:28px 36px 60px;max-width:1600px}
.audit-section{background:var(--bg2);border:1px solid var(--border);border-radius:8px;margin-bottom:22px;overflow:hidden;scroll-margin-top:calc(var(--header-h) + 12px)}
.section-header{background:var(--bg3);border-bottom:1px solid var(--border);padding:11px 18px;display:flex;align-items:center;gap:10px}
.section-header h2{font-size:.92rem;font-weight:600;color:var(--text);flex:1}
.badge{background:var(--bg);border:1px solid var(--border);border-radius:4px;padding:1px 8px;font-size:.68rem;font-family:monospace;color:var(--accent);flex-shrink:0}
.cat-pill{background:rgba(88,166,255,.08);border:1px solid rgba(88,166,255,.2);border-radius:20px;padding:1px 9px;font-size:.66rem;color:var(--accent);flex-shrink:0}
.conseil{margin:12px 18px 0;padding:9px 14px;border-radius:6px;font-size:.78rem;display:flex;gap:10px;align-items:flex-start;line-height:1.6}
.conseil-icon{flex-shrink:0;font-size:.7rem;font-weight:700;padding:2px 7px;border-radius:4px;margin-top:2px;white-space:nowrap}
.conseil-text{flex:1}
.conseil.critique{background:rgba(248,81,73,.07);border:1px solid rgba(248,81,73,.3);color:#f8a09b}
.conseil.critique .conseil-icon{background:rgba(248,81,73,.2);color:#f85149;border:1px solid rgba(248,81,73,.4)}
.conseil.important{background:rgba(210,153,34,.07);border:1px solid rgba(210,153,34,.3);color:var(--warn)}
.conseil.important .conseil-icon{background:rgba(210,153,34,.2);color:var(--warn);border:1px solid rgba(210,153,34,.4)}
.conseil.info{background:rgba(88,166,255,.06);border:1px solid rgba(88,166,255,.2);color:#79b8ff}
.conseil.info .conseil-icon{background:rgba(88,166,255,.15);color:var(--accent);border:1px solid rgba(88,166,255,.3)}
pre.output{padding:16px 18px;overflow-x:auto;font-family:'Cascadia Code','Consolas','Courier New',monospace;font-size:.76rem;line-height:1.65;color:#7ee787;white-space:pre-wrap;word-break:break-all}

/* DASHBOARD */
.dashboard-section .section-header{background:linear-gradient(135deg,#161b22 60%,#1f2937)}
.dashboard-body{padding:20px 24px 28px}

/* Top row: gauge | radar | list — centred, full-width */
.dash-top-row{
  display:flex;
  gap:40px;                    /* more breathing room between blocks */
  align-items:flex-start;
  justify-content:center;
  flex-wrap:wrap;
  width:100%;
  margin-bottom:24px;
}

/* LEFT: gauge + meta — tight vertical, no extra space below */
.dash-left{
  display:flex;flex-direction:column;align-items:center;
  gap:6px;
  flex:0 0 200px;
  padding-top:32px;
  margin-left:-10px;
  padding-right:40px;          /* right-side spacing before divider */
  border-right:1px solid var(--border);  /* subtle divider */
}
.global-gauge{flex-shrink:0;line-height:0}
.global-meta{display:flex;flex-direction:column;gap:4px;text-align:center}
.gm-title{font-size:.85rem;font-weight:600;color:var(--text)}
.gm-machine{font-size:1rem;font-weight:700;color:var(--accent)}
.gm-date,.gm-modules,.gm-os{font-size:.72rem;color:var(--dim)}
.gm-legend{display:flex;gap:6px;margin-top:4px;flex-wrap:wrap;justify-content:center}
.leg{font-size:.65rem;padding:2px 8px;border-radius:12px;font-weight:600}
.leg.crit{background:rgba(248,81,73,.15);color:#f85149;border:1px solid rgba(248,81,73,.3)}
.leg.warn{background:rgba(210,153,34,.15);color:#d29922;border:1px solid rgba(210,153,34,.3)}
.leg.ok  {background:rgba(63,185,80,.15);color:#3fb950;border:1px solid rgba(63,185,80,.3)}

/* CENTER: radar */
.dash-radar{
  display:flex;flex-direction:column;align-items:center;gap:6px;
  flex:0 0 auto;
  padding-left:0;
  padding-right:40px;          /* right-side spacing before divider */
  border-right:1px solid var(--border);  /* subtle divider */
}
.radar-title{font-size:.75rem;font-weight:700;color:var(--dim);text-transform:uppercase;letter-spacing:.08em}
#radar-canvas{cursor:crosshair;display:block}
.radar-tooltip{
  position:fixed;z-index:9999;
  background:var(--bg2);border:1px solid var(--border);border-radius:8px;
  padding:8px 12px;font-size:.72rem;color:var(--text);
  pointer-events:none;max-width:220px;
  box-shadow:0 4px 16px rgba(0,0,0,.4);line-height:1.5;
}
.radar-tooltip .rt-name{font-weight:700;color:var(--accent);display:block;margin-bottom:3px}
.radar-tooltip .rt-score{font-size:.8rem;font-weight:700;display:block;margin-bottom:3px}
.radar-tooltip .rt-issues{color:var(--dim);font-size:.68rem}

/* RIGHT: domain list — 5 items visible, clean cutoff */
.dash-right{
  flex:1 1 320px;
  min-width:280px;
  max-width:700px;
  padding-top:8px;
}
.dl-title{font-size:.75rem;font-weight:700;color:var(--dim);text-transform:uppercase;letter-spacing:.08em;margin-bottom:8px}

/* 2-column grid, exactly 5 rows visible (item≈66px + gap≈6px) */
.dl-list{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:6px;
  max-height:354px;         /* 5 items × 66px + 4 gaps × 6px = 354px */
  overflow-y:auto;
  padding-right:2px;
  /* Fade out at bottom to hint scroll */
  -webkit-mask-image:linear-gradient(to bottom, black 88%, transparent 100%);
  mask-image:linear-gradient(to bottom, black 88%, transparent 100%);
}
.dl-list::-webkit-scrollbar{width:3px}
.dl-list::-webkit-scrollbar-thumb{background:var(--bg4);border-radius:2px}

.dl-item{background:var(--bg3);border:1px solid var(--border);border-radius:6px;padding:7px 10px;cursor:pointer;transition:border-color .15s,transform .1s}
.dl-item:hover{transform:translateX(2px)}
.dl-item.crit{border-left:3px solid #f85149}.dl-item.crit:hover{border-color:#f85149}
.dl-item.warn{border-left:3px solid #d29922}.dl-item.warn:hover{border-color:#d29922}
.dl-item.ok  {border-left:3px solid #3fb950}.dl-item.ok:hover{border-color:#3fb950}
.dl-header{display:flex;align-items:center;gap:6px;margin-bottom:3px}
.dl-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0}
.dl-name{font-size:.76rem;font-weight:600;color:var(--text);flex:1}
.dl-score{font-size:.72rem;font-weight:700}
.dl-tip{font-size:.67rem;color:var(--dim);line-height:1.4}

/* Domain Analysis standalone section */
.domain-analysis-section .section-header{background:linear-gradient(135deg,#161b22 60%,#1c2230)}
.domain-analysis-body{padding:18px 20px 22px}
.domains-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:10px}
.domain-card{display:block;text-decoration:none;background:var(--bg3);border:1px solid var(--border);border-radius:8px;padding:12px 14px;transition:border-color .15s,transform .1s;cursor:pointer}
.domain-card:hover{transform:translateY(-2px)}
.domain-card.crit{border-left:3px solid #f85149}.domain-card.crit:hover{border-color:#f85149}
.domain-card.warn{border-left:3px solid #d29922}.domain-card.warn:hover{border-color:#d29922}
.domain-card.ok  {border-left:3px solid #3fb950}.domain-card.ok:hover{border-color:#3fb950}
.dc-top{display:flex;justify-content:space-between;align-items:center;margin-bottom:6px}
.dc-name{font-size:.8rem;font-weight:600;color:var(--text)}
.dc-badge{font-size:.63rem;font-weight:700;padding:2px 7px;border-radius:10px}
.domain-card.crit .dc-badge{background:rgba(248,81,73,.15);color:#f85149}
.domain-card.warn .dc-badge{background:rgba(210,153,34,.15);color:#d29922}
.domain-card.ok   .dc-badge{background:rgba(63,185,80,.15);color:#3fb950}
.dc-bar-wrap{height:4px;background:var(--bg4);border-radius:3px;margin-bottom:8px;overflow:hidden}
.dc-bar{height:100%;border-radius:3px;transition:width .8s ease}
.dc-score-line{display:flex;flex-direction:column;gap:4px}
.dc-score{font-size:.8rem;font-weight:700}
.domain-issues{margin:0;padding:0 0 0 12px;font-size:.7rem;color:var(--dim);line-height:1.5}
.domain-issues li{margin-bottom:2px}
.domain-ok{font-size:.7rem;color:#3fb950;margin:0}

/* light-theme overrides for domain cards */
body.light .domain-card.crit{border-left-color:#cf222e}
body.light .domain-card.warn{border-left-color:#9a6700}
body.light .domain-card.ok  {border-left-color:#1a7f37}

/* ---- Responsive breakpoints ---- */
@media(max-width:1200px){
  .dash-right{max-width:500px}
}
@media(max-width:960px){
  .dl-list{grid-template-columns:1fr;max-height:354px}
  .dash-right{flex:1 1 260px;max-width:100%}
  .domains-grid{grid-template-columns:repeat(auto-fill,minmax(180px,1fr))}
}
@media(max-width:768px){
  #sidebar{display:none}
  #content{margin-left:0;padding:16px}
  .dash-top-row{flex-direction:column;align-items:center}
  .dash-left{flex:0 0 auto;width:100%;max-width:320px;padding-top:0;margin-left:0;padding-right:0;border-right:none;border-bottom:1px solid var(--border);padding-bottom:20px}
  .dash-radar{width:100%;max-width:320px;padding-right:0;border-right:none}
  #radar-canvas{width:100%;height:auto}
  .dash-right{flex:1 1 auto;width:100%;max-width:100%;min-width:0;padding-top:0}
  .dl-list{grid-template-columns:1fr;max-height:none;-webkit-mask-image:none;mask-image:none}
  .domains-grid{grid-template-columns:1fr 1fr}
}

/* REMEDIATION */
.rem-section .section-header{background:linear-gradient(135deg,#161b22 60%,#1f1a0e)}
.rem-body-wrap{padding:20px 20px 28px}
.rem-summary{display:flex;gap:12px;margin-bottom:22px;align-items:flex-start;flex-wrap:wrap}
.rem-sum-card{flex-shrink:0;min-width:100px;background:var(--bg3);border:1px solid var(--border);border-radius:8px;padding:12px 16px;text-align:center}
.rem-sum-num{font-size:1.6rem;font-weight:700;line-height:1;display:block}
.rem-sum-lbl{font-size:.7rem;color:var(--dim);margin-top:4px;display:block}
.rem-sum-card.p1 .rem-sum-num{color:#f85149}
.rem-sum-card.p2 .rem-sum-num{color:#d29922}
.rem-sum-card.p3 .rem-sum-num{color:#58a6ff}
.rem-disclaimer{flex:1;min-width:200px;font-size:.72rem;color:var(--dim);background:var(--bg3);border:1px solid var(--border);border-radius:8px;padding:10px 14px;line-height:1.6}
.rem-group-title{font-size:.78rem;font-weight:700;letter-spacing:.05em;text-transform:uppercase;padding:4px 0 10px;margin-top:8px}
.p1-title{color:#f85149}.p2-title{color:#d29922}.p3-title{color:#58a6ff}
.rem-card{background:var(--bg3);border:1px solid var(--border);border-radius:8px;margin-bottom:10px;overflow:hidden}
.rem-card.p1{border-left:3px solid #f85149}
.rem-card.p2{border-left:3px solid #d29922}
.rem-card.p3{border-left:3px solid #58a6ff}
.rem-card-header{padding:10px 16px;display:flex;align-items:center;gap:8px;flex-wrap:wrap;background:var(--bg4)}
.rem-prio-badge{font-size:.62rem;font-weight:700;padding:2px 8px;border-radius:4px}
.p1 .rem-prio-badge{background:rgba(248,81,73,.2);color:#f85149;border:1px solid rgba(248,81,73,.35)}
.p2 .rem-prio-badge{background:rgba(210,153,34,.2);color:#d29922;border:1px solid rgba(210,153,34,.35)}
.p3 .rem-prio-badge{background:rgba(88,166,255,.2);color:#58a6ff;border:1px solid rgba(88,166,255,.35)}
.rem-cat{font-size:.68rem;font-weight:600;color:var(--dim);background:var(--bg3);border:1px solid var(--border);border-radius:4px;padding:1px 7px}
.rem-title{font-size:.82rem;font-weight:600;color:var(--text);flex:1}
.rem-section-link{font-size:.72rem;color:var(--accent);text-decoration:none;margin-left:auto;white-space:nowrap}
.rem-section-link:hover{text-decoration:underline}
.rem-body{padding:12px 16px;display:flex;flex-direction:column;gap:8px}
.rem-detail{font-size:.8rem;color:var(--text);line-height:1.6}
.rem-cmd{background:var(--bg);border:1px solid var(--border);border-radius:6px;padding:8px 12px}
.rem-cmd-label{font-size:.65rem;font-weight:700;color:var(--dim);text-transform:uppercase;letter-spacing:.05em;display:block;margin-bottom:4px}
.rem-cmd pre{font-family:'Cascadia Code','Consolas',monospace;font-size:.74rem;color:#79b8ff;white-space:pre-wrap}
.rem-ref{font-size:.7rem;color:var(--dim)}

/* SIDEBAR REFERENCES PANEL */
#sidebar-refs{border-top:1px solid var(--border);margin-top:auto;flex-shrink:0}
.refs-toggle-btn{width:100%;background:none;border:none;cursor:pointer;display:flex;align-items:center;gap:7px;padding:9px 12px;color:var(--dim);font-size:.68rem;font-weight:700;letter-spacing:.07em;text-transform:uppercase;text-align:left;transition:color .15s,background .15s}
.refs-toggle-btn:hover{color:var(--text);background:var(--bg3)}
.refs-toggle-btn.open{color:var(--text)}
.refs-toggle-icon{font-size:.5rem;transition:transform .2s;display:inline-block;flex-shrink:0}
.refs-toggle-btn.open .refs-toggle-icon{transform:rotate(90deg)}
.refs-title-text{flex:1}
.refs-count{background:var(--bg3);border:1px solid var(--border);border-radius:8px;padding:0 5px;font-size:.6rem;color:var(--dim)}
#refs-list{padding:2px 0 10px;display:none}
.ref-link{display:flex;align-items:flex-start;gap:8px;padding:5px 8px;border-radius:5px;text-decoration:none;color:var(--dim);font-size:.74rem;line-height:1.35;transition:background .12s,color .12s;margin-bottom:1px}
.ref-link:hover{background:var(--bg3);color:var(--text)}
.ref-link .ref-icon{flex-shrink:0;width:20px;height:20px;border-radius:4px;display:flex;align-items:center;justify-content:center;font-size:.6rem;font-weight:700;margin-top:1px}
.ref-link .ref-body{flex:1;overflow:hidden}
.ref-link .ref-name{font-weight:600;color:var(--text);display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ref-link .ref-org{font-size:.67rem;color:var(--dim)}
.ref-link.anssi .ref-icon{background:rgba(0,114,188,.2);color:#0072bc}
.ref-link.cis   .ref-icon{background:rgba(255,138,0,.2);color:#ff8a00}
.ref-link.nist  .ref-icon{background:rgba(63,185,80,.2);color:#3fb950}
.ref-link.mitre .ref-icon{background:rgba(248,81,73,.2);color:#f85149}
.ref-link.ssi   .ref-icon{background:rgba(139,148,158,.2);color:#8b949e}
.ref-link.debian .ref-icon{background:rgba(215,7,81,.2);color:#d70751}
.ref-link.ubuntu .ref-icon{background:rgba(233,84,32,.2);color:#e95420}
.ref-link.cisa  .ref-icon{background:rgba(0,120,212,.2);color:#0078d4}
.hn-refs{color:var(--dim)}.hn-refs:hover{color:var(--text);border-color:var(--border)}
.mitre-section .section-header{background:linear-gradient(135deg,#161b22 60%,#1a1f2e)}
.mitre-body{padding:20px 20px 28px}
.mitre-stats{display:flex;gap:12px;margin-bottom:18px;flex-wrap:wrap}
.ms-card{flex:1;min-width:90px;background:var(--bg3);border:1px solid var(--border);border-radius:8px;padding:12px 14px;text-align:center}
.ms-num{font-size:1.6rem;font-weight:700;line-height:1}
.ms-lbl{font-size:.7rem;color:var(--dim);margin-top:4px}
.ms-card.crit .ms-num{color:#f85149}
.ms-card.warn .ms-num{color:#d29922}
.ms-card.poss .ms-num{color:#58a6ff}
.ms-card.none .ms-num{color:var(--dim)}
.mitre-legend{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:14px}
.leg-item{font-size:.72rem;padding:3px 10px;border-radius:4px;font-weight:600}
.leg-item.t-crit{background:rgba(248,81,73,.25);color:#f88;border:1px solid rgba(248,81,73,.5)}
.leg-item.t-warn{background:rgba(210,153,34,.25);color:#fa3;border:1px solid rgba(210,153,34,.5)}
.leg-item.t-poss{background:rgba(88,166,255,.2);color:#8bf;border:1px solid rgba(88,166,255,.4)}
.leg-item.t-none{background:var(--bg3);color:var(--dim);border:1px solid var(--border)}
.mitre-flags{background:var(--bg3);border:1px solid var(--border);border-radius:6px;padding:12px 14px;margin-bottom:18px}
.flags-title{font-size:.72rem;color:var(--dim);margin-bottom:8px;font-weight:600;text-transform:uppercase;letter-spacing:.05em}
.flags-list{display:flex;flex-wrap:wrap;gap:6px}
.flag-item{font-size:.7rem;background:rgba(248,81,73,.12);color:#f8a09b;border:1px solid rgba(248,81,73,.25);border-radius:4px;padding:2px 8px}
a.flag-link{text-decoration:none;cursor:pointer;transition:background .15s,border-color .15s}
a.flag-link:hover{background:rgba(248,81,73,.28);border-color:rgba(248,81,73,.6);color:#fcc}
.flag-arrow{opacity:.7;font-size:.65rem}
.flag-none{font-size:.75rem;color:#3fb950}
.mitre-table-wrap{overflow-x:auto;border:1px solid var(--border);border-radius:8px}
.mitre-table{border-collapse:collapse;width:100%;min-width:1200px}
.tac-header{background:var(--bg4);color:var(--text);font-size:.68rem;font-weight:700;padding:8px 6px;text-align:center;border:1px solid var(--border);white-space:nowrap;letter-spacing:.03em;position:sticky;top:0;z-index:2}
.tac-badge{display:inline-block;background:#f85149;color:#fff;font-size:.58rem;border-radius:10px;padding:0 5px;margin-left:4px;font-weight:700}
.tech-cell{padding:4px 5px;border:1px solid rgba(48,54,61,.6);vertical-align:top;font-size:.64rem;line-height:1.3;width:calc(100%/13);min-width:82px}
.tech-cell a{text-decoration:none;display:block;border-radius:3px;padding:3px 4px;transition:filter .1s}
.tech-cell a:hover{filter:brightness(1.3)}
.tech-cell small{opacity:.7;font-size:.58rem}
.t-crit a{background:rgba(248,81,73,.3);color:#faa;border:1px solid rgba(248,81,73,.5)}
.t-warn a{background:rgba(210,153,34,.25);color:#fc9;border:1px solid rgba(210,153,34,.4)}
.t-poss a{background:rgba(88,166,255,.18);color:#9cf;border:1px solid rgba(88,166,255,.3)}
.t-none a{background:var(--bg3);color:var(--dim);border:1px solid var(--border)}
.t-empty{background:transparent;border-color:rgba(48,54,61,.3)}
.mitre-footer{font-size:.68rem;color:var(--dim);margin-top:14px;padding-top:10px;border-top:1px solid var(--border)}
.nav-link.mitre-link{color:#f85149;font-weight:600}
.nav-link.mitre-link:hover,.nav-link.mitre-link.active{color:#f85149;border-left-color:#f85149;background:rgba(248,81,73,.08)}

/* BACK TO TOP */
#back-to-top{position:fixed;bottom:24px;right:24px;background:var(--bg3);border:1px solid var(--border);border-radius:50%;width:38px;height:38px;color:var(--dim);font-size:1rem;cursor:pointer;display:flex;align-items:center;justify-content:center;opacity:0;transition:opacity .2s,border-color .2s,color .2s;z-index:300}
#back-to-top.visible{opacity:1}
#back-to-top:hover{border-color:var(--accent);color:var(--accent)}

</style>
</head>
<body>

HTML_PART2
    # PART 3: Dynamic header bar (hostname, OS, date)
    {
        printf '<!-- TOP HEADER -->\n'
        printf '<div id="header">\n'
        cat >> "$report_path" << 'TUX_LOGO_HTML'
  <div class="header-logo">
    <svg class="tux-svg" viewBox="0 0 40 50" xmlns="http://www.w3.org/2000/svg" aria-label="Tux">
      <ellipse cx="20" cy="34" rx="13" ry="14" fill="#1a1a1a"/>
      <ellipse cx="20" cy="36" rx="8"  ry="10" fill="#f5f0e8"/>
      <ellipse cx="20" cy="12" rx="10" ry="11" fill="#1a1a1a"/>
      <ellipse cx="16.5" cy="10" rx="2.2" ry="2.8" fill="white"/>
      <ellipse cx="23.5" cy="10" rx="2.2" ry="2.8" fill="white"/>
      <circle  cx="17"   cy="10.5" r="1.2" fill="#111"/>
      <circle  cx="24"   cy="10.5" r="1.2" fill="#111"/>
      <ellipse cx="20"  cy="16.5" rx="3.2" ry="2"  fill="#f5a623"/>
      <ellipse cx="14"  cy="47"   rx="5.2" ry="2"  fill="#f5a623" transform="rotate(-10,14,47)"/>
      <ellipse cx="26"  cy="47"   rx="5.2" ry="2"  fill="#f5a623" transform="rotate(10,26,47)"/>
      <ellipse cx="8"   cy="34"   rx="4"   ry="10" fill="#111" transform="rotate(-10,8,34)"/>
      <ellipse cx="32"  cy="34"   rx="4"   ry="10" fill="#111" transform="rotate(10,32,34)"/>
    </svg>
    <span class="logo-text">TuxAudit <span class="logo-ver">v1.0</span></span>
  </div>
TUX_LOGO_HTML
        printf '  <div class="pill"><strong>%s</strong></div>\n'   "${HOSTNAME_VAL}"
        printf '  <div class="pill">%s</div>\n'                    "${OS_PRETTY}"
        printf '  <div class="pill">%s %s</div>\n'                 "${DATE_VAL}" "${HOUR_VAL}"
        printf '  <div class="header-nav">\n'
        cat << 'HDR_INNER'
    <a class="hn-link hn-dash"  href="#dashboard"   onclick="event.preventDefault();navToAnchor('dashboard')">Dashboard</a>
    <a class="hn-link hn-mitre" href="#mitre-matrix" onclick="event.preventDefault();navToAnchor('mitre-matrix')">ATT&amp;CK</a>
    <a class="hn-link hn-rem"   href="#remediation"  onclick="event.preventDefault();navToAnchor('remediation')">Remediation</a>
    <a class="hn-link hn-refs"  href="#sidebar-refs" id="refs-header-btn">References</a>
  </div>
  <div class="header-right">
    <button id="theme-toggle" title="Switch theme">
      <span class="th-icon">&#9790;</span>
      <span class="th-label">Light</span>
    </button>
    <input type="text" id="search-input" placeholder="Search module...">
  </div>
</div>
HDR_INNER
    } >> "$report_path"
    # PART 4: Static sidebar structure
    cat >> "$report_path" << 'HTML_PART4'

<!-- SIDEBAR -->
<div id="sidebar">
  <div id="sidebar-top">
    <strong>TuxAudit v1.0</strong>
    <div style="display:flex;gap:4px">
      <button id="expand-all">+</button>
      <button id="collapse-all">-</button>
    </div>
  </div>
  <nav>
    <ul>
      <li><a class="nav-link" href="#dashboard" data-anchor="dashboard">
        <span class="nav-badge">DASH</span> Security Dashboard</a></li>
      <li><a class="nav-link" href="#domain-analysis" data-anchor="domain-analysis">
        <span class="nav-badge">DOM</span> Domain Analysis</a></li>
      <li><a class="nav-link mitre-link" href="#mitre-matrix" data-anchor="mitre-matrix">
        <span class="nav-badge">ATT&amp;CK</span> MITRE Matrix</a></li>
      <li><a class="nav-link rem-link" href="#remediation" data-anchor="remediation">
        <span class="nav-badge">REM</span> Remediation Plan</a></li>
HTML_PART4
    # Dynamic: sidebar menu items
    printf '%s\n' "${menu_html}" >> "$report_path"
    # PART 6: Close sidebar + open content wrapper
    cat >> "$report_path" << 'HTML_PART6'
    </ul>
  </nav>

  <!-- SECURITY REFERENCES PANEL -->
  <div id="sidebar-refs">
    <button id="refs-toggle" class="refs-toggle-btn">
      <span class="refs-toggle-icon">&#9654;</span>
      <span class="refs-title-text">Security References</span>
      <span class="refs-count">16</span>
    </button>
    <div id="refs-list" style="display:none">

    <a class="ref-link cis" href="https://www.cisecurity.org/benchmark/debian_linux" target="_blank" rel="noopener">
      <span class="ref-icon">CI</span>
      <span class="ref-body"><span class="ref-name">CIS Debian Linux Benchmark</span>
      <span class="ref-org">CIS — Debian 11/12 hardening guide</span></span>
    </a>
    <a class="ref-link cis" href="https://www.cisecurity.org/benchmark/ubuntu_linux" target="_blank" rel="noopener">
      <span class="ref-icon">CI</span>
      <span class="ref-body"><span class="ref-name">CIS Ubuntu Linux Benchmark</span>
      <span class="ref-org">CIS — Ubuntu 22.04/24.04 hardening</span></span>
    </a>
    <a class="ref-link cis" href="https://www.cisecurity.org/controls" target="_blank" rel="noopener">
      <span class="ref-icon">CI</span>
      <span class="ref-body"><span class="ref-name">CIS Controls v8</span>
      <span class="ref-org">CIS — 18 essential security controls</span></span>
    </a>
    <a class="ref-link ssi" href="https://www.ssh.com/academy/ssh/security" target="_blank" rel="noopener">
      <span class="ref-icon">SS</span>
      <span class="ref-body"><span class="ref-name">SSH Security Best Practices</span>
      <span class="ref-org">SSH.com — Hardening SSH configuration</span></span>
    </a>
    <a class="ref-link ssi" href="https://linux-audit.com/linux-security-guide-for-hardening-ssh/" target="_blank" rel="noopener">
      <span class="ref-icon">LA</span>
      <span class="ref-body"><span class="ref-name">Linux Audit — SSH Hardening Guide</span>
      <span class="ref-org">Linux Audit — Practical SSH lockdown</span></span>
    </a>
    <a class="ref-link nist" href="https://www.nist.gov/cyberframework" target="_blank" rel="noopener">
      <span class="ref-icon">NI</span>
      <span class="ref-body"><span class="ref-name">NIST Cybersecurity Framework 2.0</span>
      <span class="ref-org">NIST — Identify / Protect / Detect / Respond</span></span>
    </a>
    <a class="ref-link nist" href="https://csrc.nist.gov/publications/detail/sp/800-123/final" target="_blank" rel="noopener">
      <span class="ref-icon">NI</span>
      <span class="ref-body"><span class="ref-name">NIST SP 800-123</span>
      <span class="ref-org">NIST — Guide to General Server Security</span></span>
    </a>
    <a class="ref-link nist" href="https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final" target="_blank" rel="noopener">
      <span class="ref-icon">NI</span>
      <span class="ref-body"><span class="ref-name">NIST SP 800-53 Rev5</span>
      <span class="ref-org">NIST — Security and Privacy Controls</span></span>
    </a>
    <a class="ref-link mitre" href="https://attack.mitre.org/matrices/enterprise/linux/" target="_blank" rel="noopener">
      <span class="ref-icon">MT</span>
      <span class="ref-body"><span class="ref-name">MITRE ATT&amp;CK Linux</span>
      <span class="ref-org">MITRE — Tactics and techniques (Linux)</span></span>
    </a>
    <a class="ref-link mitre" href="https://attack.mitre.org/mitigations/enterprise/" target="_blank" rel="noopener">
      <span class="ref-icon">MT</span>
      <span class="ref-body"><span class="ref-name">ATT&amp;CK Mitigations</span>
      <span class="ref-org">MITRE — Mitigations per technique</span></span>
    </a>
    <a class="ref-link mitre" href="https://gtfobins.github.io/" target="_blank" rel="noopener">
      <span class="ref-icon">GT</span>
      <span class="ref-body"><span class="ref-name">GTFOBins</span>
      <span class="ref-org">UNIX binaries exploitable for privilege escalation</span></span>
    </a>
    <a class="ref-link cisa" href="https://www.cisa.gov/known-exploited-vulnerabilities-catalog" target="_blank" rel="noopener">
      <span class="ref-icon">CS</span>
      <span class="ref-body"><span class="ref-name">CISA KEV Catalog</span>
      <span class="ref-org">CISA — Known Exploited Vulnerabilities</span></span>
    </a>
    <a class="ref-link debian" href="https://www.debian.org/doc/manuals/securing-debian-manual/" target="_blank" rel="noopener">
      <span class="ref-icon">DB</span>
      <span class="ref-body"><span class="ref-name">Securing Debian Manual</span>
      <span class="ref-org">Debian — Official security hardening documentation</span></span>
    </a>
    <a class="ref-link ubuntu" href="https://ubuntu.com/security/certifications/docs/usg" target="_blank" rel="noopener">
      <span class="ref-icon">UB</span>
      <span class="ref-body"><span class="ref-name">Ubuntu Security Guide (USG)</span>
      <span class="ref-org">Canonical — CIS/DISA automated hardening</span></span>
    </a>
    <a class="ref-link ssi" href="https://linux-audit.com/" target="_blank" rel="noopener">
      <span class="ref-icon">LA</span>
      <span class="ref-body"><span class="ref-name">Linux Audit</span>
      <span class="ref-org">Security auditing tools, guides and best practices</span></span>
    </a>
    <a class="ref-link ssi" href="https://nvd.nist.gov/" target="_blank" rel="noopener">
      <span class="ref-icon">NV</span>
      <span class="ref-body"><span class="ref-name">NVD — CVE Database</span>
      <span class="ref-org">NIST — National Vulnerability Database</span></span>
    </a>

    </div>
  </div>
</div>

<!-- MAIN CONTENT -->
<div id="content">
HTML_PART6
    # Dynamic: all audit section content
    printf '%s\n' "${content_html}" >> "$report_path"
    # PART 8: Static closing HTML + JavaScript
    cat >> "$report_path" << 'HTML_PART8'
</div>

<button id="back-to-top" title="Back to top">&#8679;</button>

<script>
var headerH = parseInt(getComputedStyle(document.documentElement).getPropertyValue('--header-h')) || 58;

function navToAnchor(anchor) {
  var el = document.getElementById(anchor);
  if (!el) return;
  var top = el.getBoundingClientRect().top + window.scrollY - headerH - 12;
  window.scrollTo({ top: top, behavior: 'smooth' });
  setActiveLink(anchor);
  var navLink = document.querySelector('.nav-link[data-anchor="' + anchor + '"]');
  if (navLink) ensureParentOpen(navLink);
}

function openGroup(btn, ul) {
  if (!ul) return;
  ul.classList.add('open');
  btn.classList.add('open');
}
function closeGroup(btn, ul) {
  if (!ul) return;
  ul.classList.remove('open');
  btn.classList.remove('open');
}
function ensureParentOpen(linkEl) {
  var ul = linkEl.closest('.cat-items');
  if (!ul) return;
  if (!ul.classList.contains('open')) {
    ul.classList.add('open');
    var btn = document.querySelector('[data-target="' + ul.id + '"]');
    if (btn) btn.classList.add('open');
  }
}

document.querySelectorAll('.cat-toggle').forEach(function(btn) {
  var ul = document.getElementById(btn.getAttribute('data-target'));
  openGroup(btn, ul);
  btn.addEventListener('click', function() {
    if (ul.classList.contains('open')) { closeGroup(btn, ul); }
    else { openGroup(btn, ul); }
  });
});

document.getElementById('expand-all').addEventListener('click', function() {
  document.querySelectorAll('.cat-toggle').forEach(function(btn) {
    openGroup(btn, document.getElementById(btn.getAttribute('data-target')));
  });
});
document.getElementById('collapse-all').addEventListener('click', function() {
  document.querySelectorAll('.cat-toggle').forEach(function(btn) {
    closeGroup(btn, document.getElementById(btn.getAttribute('data-target')));
  });
});

document.getElementById('search-input').addEventListener('input', function() {
  var q = this.value.trim().toLowerCase();
  document.querySelectorAll('.nav-link').forEach(function(a) {
    if (!q || a.textContent.toLowerCase().indexOf(q) !== -1) {
      a.classList.remove('hidden-search');
      if (q) ensureParentOpen(a);
    } else {
      a.classList.add('hidden-search');
    }
  });
});

var sections  = document.querySelectorAll('.audit-section');
var navLinks  = document.querySelectorAll('.nav-link');

function getActiveAnchor() {
  var scrollY = window.scrollY + headerH + 30;
  var active  = null;
  sections.forEach(function(sec) {
    if (sec.offsetTop <= scrollY) { active = sec.id; }
  });
  return active;
}
function setActiveLink(anchor) {
  navLinks.forEach(function(a) {
    if (a.getAttribute('data-anchor') === anchor) {
      a.classList.add('active');
      ensureParentOpen(a);
    } else {
      a.classList.remove('active');
    }
  });
  // Header nav
  document.querySelectorAll('.hn-link').forEach(function(a) {
    a.classList.toggle('hn-active', a.getAttribute('href') === '#' + anchor);
  });
}

var ticking = false;
window.addEventListener('scroll', function() {
  if (!ticking) {
    requestAnimationFrame(function() {
      setActiveLink(getActiveAnchor());
      document.getElementById('back-to-top').classList.toggle('visible', window.scrollY > 300);
      ticking = false;
    });
    ticking = true;
  }
});

document.getElementById('back-to-top').addEventListener('click', function() {
  window.scrollTo({ top: 0, behavior: 'smooth' });
});

// --- References panel toggle ---
var refsToggleBtn = document.getElementById('refs-toggle');
var refsListEl    = document.getElementById('refs-list');

function _refsIsOpen() {
  return refsListEl && refsListEl.style.display !== 'none';
}
function _refsOpen() {
  if (!refsListEl) return;
  refsListEl.style.display = 'block';
  if (refsToggleBtn) refsToggleBtn.classList.add('open');
}
function _refsClose() {
  if (!refsListEl) return;
  refsListEl.style.display = 'none';
  if (refsToggleBtn) refsToggleBtn.classList.remove('open');
}

if (refsToggleBtn && refsListEl) {
  refsToggleBtn.addEventListener('click', function() {
    _refsIsOpen() ? _refsClose() : _refsOpen();
  });
}

// Header "References" button → true toggle + scroll sidebar to bottom when opening
var refsHeaderBtn = document.getElementById('refs-header-btn');
if (refsHeaderBtn) {
  refsHeaderBtn.addEventListener('click', function(e) {
    e.preventDefault();
    var sidebar = document.getElementById('sidebar');
    if (_refsIsOpen()) {
      _refsClose();
    } else {
      _refsOpen();
      if (sidebar) setTimeout(function() {
        sidebar.scrollTo({ top: sidebar.scrollHeight, behavior: 'smooth' });
      }, 50);
    }
  });
}

// --- Theme toggle (dark / light) ---
(function() {
  var btn    = document.getElementById('theme-toggle');
  var icon   = btn  ? btn.querySelector('.th-icon')  : null;
  var label  = btn  ? btn.querySelector('.th-label') : null;
  var stored = localStorage.getItem('tuxaudit-theme');

  function applyTheme(theme) {
    if (theme === 'light') {
      document.body.classList.add('light');
      if (icon)  icon.innerHTML  = '&#9728;';   /* ☀ sun */
      if (label) label.textContent = 'Dark';
    } else {
      document.body.classList.remove('light');
      if (icon)  icon.innerHTML  = '&#9790;';   /* ☾ crescent */
      if (label) label.textContent = 'Light';
    }
    localStorage.setItem('tuxaudit-theme', theme);
  }

  /* Restore saved preference */
  applyTheme(stored === 'light' ? 'light' : 'dark');

  if (btn) {
    btn.addEventListener('click', function() {
      var isLight = document.body.classList.contains('light');
      applyTheme(isLight ? 'dark' : 'light');
    });
  }
})();

// =====================================================================
// RADAR CHART — RPG Skill Tree
// =====================================================================
(function() {
  var canvas  = document.getElementById('radar-canvas');
  if (!canvas) return;
  var ctx     = canvas.getContext('2d');
  var tooltip = document.getElementById('radar-tooltip');
  var W = canvas.width, H = canvas.height;
  var cx = W / 2, cy = H / 2;
  var R = Math.min(W, H) / 2 - 48;   // outer ring radius

  // Read data from data-attributes
  var rawScores  = canvas.getAttribute('data-scores').split(',').map(Number);
  var rawLabels  = canvas.getAttribute('data-labels').split(',');
  var N = rawScores.length;

  // Parse labels: "Name|anchor"
  var domainNames   = rawLabels.map(function(l){ return l.split('|')[0]; });
  var domainAnchors = rawLabels.map(function(l){ return l.split('|')[1] || ''; });
  var domainIssues  = [];  // will be populated from dl-items
  document.querySelectorAll('.dl-item').forEach(function(el, i) {
    var tip = el.querySelector('.dl-tip');
    domainIssues[i] = tip ? tip.textContent : '';
  });

  var isDark = !document.body.classList.contains('light');

  function getCSSVar(name) {
    return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  }
  function colors() {
    isDark = !document.body.classList.contains('light');
    return {
      bg:      isDark ? '#0d1117' : '#f6f8fa',
      bg3:     isDark ? '#21262d' : '#f0f2f5',
      border:  isDark ? '#30363d' : '#d0d7de',
      dim:     isDark ? '#8b949e' : '#57606a',
      text:    isDark ? '#c9d1d9' : '#1f2328',
      accent:  isDark ? '#58a6ff' : '#0969da',
    };
  }

  // Score → colour (centre=red, edge=green)
  function scoreColor(s) {
    // s: 0-10
    var t = s / 10;
    // interpolate red(0) → orange(0.5) → green(1)
    var r, g, b;
    if (t < 0.5) {
      var u = t / 0.5;
      r = Math.round(248 - (248-210)*u);
      g = Math.round(81  + (153-81)*u);
      b = Math.round(73  + (34-73)*u);
    } else {
      var u = (t - 0.5) / 0.5;
      r = Math.round(210 - (210-63)*u);
      g = Math.round(153 + (185-153)*u);
      b = Math.round(34  + (80-34)*u);
    }
    return 'rgb('+r+','+g+','+b+')';
  }

  // Compute polygon point for domain i at radius r
  function point(i, r) {
    var angle = (Math.PI * 2 * i / N) - Math.PI / 2;
    return {
      x: cx + r * Math.cos(angle),
      y: cy + r * Math.sin(angle)
    };
  }

  // Store clickable node positions for hit-testing
  var nodePositions = [];

  function draw() {
    var C = colors();
    ctx.clearRect(0, 0, W, H);

    var levels = 10;

    // ---- Background rings (levels 1-10) ----
    for (var lv = 1; lv <= levels; lv++) {
      var r = R * lv / levels;
      ctx.beginPath();
      for (var i = 0; i < N; i++) {
        var p = point(i, r);
        i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y);
      }
      ctx.closePath();
      // Subtle fill gradient from center (red) to edge (green)
      var t = lv / levels;
      var alpha = 0.04 + t * 0.03;
      ctx.fillStyle = lv <= 4 ? 'rgba(248,81,73,'+alpha+')'
                   : lv <= 7 ? 'rgba(210,153,34,'+alpha+')'
                              : 'rgba(63,185,80,'+alpha+')';
      ctx.fill();
      ctx.strokeStyle = C.border;
      ctx.lineWidth   = lv === 10 ? 1.5 : 0.5;
      ctx.setLineDash(lv === 10 ? [] : [3, 4]);
      ctx.stroke();
      ctx.setLineDash([]);

      // Ring level number (1,3,5,7,10 only)
      if (lv === 1 || lv === 3 || lv === 5 || lv === 7 || lv === 10) {
        ctx.fillStyle  = C.dim;
        ctx.font       = '9px monospace';
        ctx.textAlign  = 'center';
        ctx.fillText(lv, cx + 4, cy - r + 10);
      }
    }

    // ---- Spokes (axes) ----
    for (var i = 0; i < N; i++) {
      var pOuter = point(i, R);
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(pOuter.x, pOuter.y);
      ctx.strokeStyle = C.border;
      ctx.lineWidth   = 1;
      ctx.stroke();
    }

    // ---- Filled polygon (scores) ----
    ctx.beginPath();
    for (var i = 0; i < N; i++) {
      var r  = R * rawScores[i] / 10;
      var p  = point(i, r);
      i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y);
    }
    ctx.closePath();
    // Gradient fill based on avg score
    var avgScore = rawScores.reduce(function(a,b){return a+b},0)/N;
    var fillCol  = scoreColor(avgScore);
    var gradFill = ctx.createRadialGradient(cx, cy, 0, cx, cy, R);
    gradFill.addColorStop(0,   'rgba(248,81,73,0.35)');
    gradFill.addColorStop(0.5, 'rgba(210,153,34,0.25)');
    gradFill.addColorStop(1,   'rgba(63,185,80,0.20)');
    ctx.fillStyle   = gradFill;
    ctx.fill();
    ctx.strokeStyle = fillCol;
    ctx.lineWidth   = 2;
    ctx.shadowColor = fillCol;
    ctx.shadowBlur  = 6;
    ctx.stroke();
    ctx.shadowBlur  = 0;

    // ---- Nodes (dots) on each spoke ----
    nodePositions = [];
    for (var i = 0; i < N; i++) {
      var r  = R * rawScores[i] / 10;
      var p  = point(i, r);
      var nc = scoreColor(rawScores[i]);

      nodePositions.push({ x: p.x, y: p.y, index: i, r: 7 });

      // Glow ring
      ctx.beginPath();
      ctx.arc(p.x, p.y, 9, 0, Math.PI * 2);
      ctx.fillStyle = nc.replace('rgb', 'rgba').replace(')', ',0.18)');
      ctx.fill();
      // Dot
      ctx.beginPath();
      ctx.arc(p.x, p.y, 5, 0, Math.PI * 2);
      ctx.fillStyle   = nc;
      ctx.shadowColor = nc;
      ctx.shadowBlur  = 8;
      ctx.fill();
      ctx.strokeStyle = isDark ? '#0d1117' : '#ffffff';
      ctx.lineWidth   = 1.5;
      ctx.stroke();
      ctx.shadowBlur  = 0;
    }

    // ---- Labels ----
    var labelR = R + 22;
    for (var i = 0; i < N; i++) {
      var p    = point(i, labelR);
      var s    = rawScores[i];
      var nc   = scoreColor(s);
      var name = domainNames[i];

      // Short name if too long
      if (name.length > 10) name = name.substring(0, 9) + '…';

      ctx.font      = 'bold 10px "Segoe UI", system-ui, sans-serif';
      ctx.fillStyle = nc;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';

      // Background pill for legibility
      var tw  = ctx.measureText(name).width + 8;
      ctx.fillStyle = isDark ? 'rgba(13,17,23,0.75)' : 'rgba(246,248,250,0.85)';
      ctx.beginPath();
      ctx.roundRect(p.x - tw/2, p.y - 7, tw, 14, 4);
      ctx.fill();

      ctx.fillStyle = nc;
      ctx.fillText(name, p.x, p.y);
    }
  }

  draw();

  // Redraw on theme toggle
  document.getElementById('theme-toggle') && document.getElementById('theme-toggle').addEventListener('click', function() {
    setTimeout(draw, 30);
  });

  // ---- Tooltip & hover ----
  var hoveredIndex = -1;

  canvas.addEventListener('mousemove', function(e) {
    var rect  = canvas.getBoundingClientRect();
    var mx    = (e.clientX - rect.left) * (W / rect.width);
    var my    = (e.clientY - rect.top)  * (H / rect.height);
    var found = -1;

    for (var i = 0; i < nodePositions.length; i++) {
      var np = nodePositions[i];
      var dx = mx - np.x, dy = my - np.y;
      if (Math.sqrt(dx*dx + dy*dy) <= np.r + 6) { found = i; break; }
    }

    if (found !== hoveredIndex) {
      hoveredIndex = found;
      draw();  // redraw to highlight
      if (found >= 0) {
        // Redraw with highlight ring
        var np = nodePositions[found];
        var nc = scoreColor(rawScores[found]);
        ctx.beginPath();
        ctx.arc(np.x, np.y, 11, 0, Math.PI * 2);
        ctx.strokeStyle = nc;
        ctx.lineWidth   = 2;
        ctx.shadowColor = nc;
        ctx.shadowBlur  = 12;
        ctx.stroke();
        ctx.shadowBlur  = 0;
        canvas.style.cursor = 'pointer';
      } else {
        canvas.style.cursor = 'crosshair';
      }
    }

    if (found >= 0) {
      var s   = rawScores[found];
      var nc  = scoreColor(s);
      var lbl = s <= 4 ? 'Critical' : s <= 7 ? 'Warning' : 'Good';
      var iss = domainIssues[found] || 'No issue detected';
      tooltip.innerHTML =
        "<span class='rt-name'>" + domainNames[found] + "</span>" +
        "<span class='rt-score' style='color:" + nc + "'>" + s + " / 10 — " + lbl + "</span>" +
        "<span class='rt-issues'>" + iss.replace(/\n/g,'<br>') + "</span>" +
        "<span class='rt-issues' style='margin-top:4px;display:block;color:var(--accent)'>↗ Click to view remediation</span>";
      tooltip.style.display = 'block';
      tooltip.style.left    = (e.clientX + 14) + 'px';
      tooltip.style.top     = (e.clientY - 10) + 'px';
      // Keep tooltip in viewport
      var tr = tooltip.getBoundingClientRect();
      if (tr.right > window.innerWidth - 10)
        tooltip.style.left = (e.clientX - tr.width - 14) + 'px';
    } else {
      tooltip.style.display = 'none';
    }
  });

  canvas.addEventListener('mouseleave', function() {
    tooltip.style.display = 'none';
    hoveredIndex = -1;
    draw();
  });

  // Click → navigate to remediation section filtered by domain
  canvas.addEventListener('click', function(e) {
    var rect = canvas.getBoundingClientRect();
    var mx   = (e.clientX - rect.left) * (W / rect.width);
    var my   = (e.clientY - rect.top)  * (H / rect.height);
    for (var i = 0; i < nodePositions.length; i++) {
      var np = nodePositions[i];
      var dx = mx - np.x, dy = my - np.y;
      if (Math.sqrt(dx*dx + dy*dy) <= np.r + 6) {
        navToAnchor('remediation');
        // Highlight matching cards after scroll
        setTimeout(function(name) {
          document.querySelectorAll('.rem-card').forEach(function(card) {
            var catEl = card.querySelector('.rem-cat');
            if (catEl && catEl.textContent.toLowerCase() === name.toLowerCase()) {
              card.style.outline = '2px solid var(--accent)';
              card.style.outlineOffset = '2px';
              setTimeout(function(){ card.style.outline=''; card.style.outlineOffset=''; }, 2500);
            }
          });
        }, 600, domainNames[i]);
        break;
      }
    }
  });
})();

// Init
setActiveLink('dashboard');
</script>
</body>
</html>
HTML_PART8

    echo "$report_path"
}

# ---------------------------------------------------------------------------
#  GENERATE REPORT MENU ACTION
# ---------------------------------------------------------------------------

generate_report_interactive() {
    clear
    echo ""
    echo -e "  ${DCYAN}TuxAudit v1.0${NC}  ${GRAY}·${NC}  ${WHITE}HTML Report Generator${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo ""

    # Ask which modules to include
    local already_captured="${#REPORT_DATA[@]}"
    echo -e "  ${YELLOW}Select data source for the report:${NC}"
    echo ""
    echo -e "  ${CYAN}[ALL]${NC} Run all 23 modules now and generate report ${GRAY}(recommended)${NC}"
    if [[ $already_captured -gt 0 ]]; then
        echo -e "  ${CYAN}[SEL]${NC} Use already-captured data ${GREEN}(${already_captured} modules in memory)${NC}"
    else
        echo -e "  ${CYAN}[SEL]${NC} Use already-captured data ${GRAY}(none yet — run [ALL] from main menu first)${NC}"
    fi
    echo -e "  ${CYAN}[Q]${NC}   Cancel"
    echo ""
    read -rp "  $(echo -e "${WHITE}Choice:${NC} ")" rchoice

    case "${rchoice^^}" in
        ALL)
            echo ""
            echo -e "  ${YELLOW}[...] Running all 23 modules, please wait...${NC}"
            echo ""
            local all_mods=(01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23)
            local total=${#all_mods[@]}
            local count=0
            for m in "${all_mods[@]}"; do
                ((count++))
                local mod_name
                mod_name=$(echo "${MODULE_META[$m]:-}" | cut -d'|' -f1)
                progress_bar "$count" "$total" "${mod_name:-Module $m}"
                capture_module "$m"
            done
            echo ""
            echo -e "\n  ${GREEN}[✔] All ${#REPORT_DATA[@]} modules captured.${NC}"
            ;;
        SEL)
            if [[ $already_captured -eq 0 ]]; then
                echo -e "\n  ${RED}[!] No module data in memory.${NC}"
                echo -e "  ${GRAY}    Run [ALL] from the main menu first, then come back here.${NC}"
                pause
                return
            fi
            echo -e "\n  ${GREEN}[✔] Using ${already_captured} already-captured modules.${NC}"
            ;;
        [Qq]|"")
            return ;;
        *)
            echo -e "  ${RED}Invalid choice.${NC}"
            sleep 0.7
            return
            ;;
    esac

    # Ask output path
    echo ""
    local default_path="/tmp/tuxaudit_${HOSTNAME_VAL}_${REPORT_DATE}.html"
    echo -e "  ${GRAY}Output path [default: ${default_path}]:${NC}"
    read -rp "  " out_path
    [[ -z "$out_path" ]] && out_path="$default_path"

    echo ""
    echo -e "  ${YELLOW}[...] Generating HTML report...${NC}"

    local result_path
    result_path=$(generate_html_report "$out_path")

    if [[ -f "$result_path" ]]; then
        LAST_REPORT_PATH="$result_path"
        local fsize
        fsize=$(du -sh "$result_path" 2>/dev/null | cut -f1)
        echo ""
        echo -e "  ${GREEN}[✔] Report generated successfully!${NC}"
        echo ""
        echo -e "  ${CYAN}Path :${NC} ${WHITE}${result_path}${NC}"
        echo -e "  ${CYAN}Size :${NC} ${WHITE}${fsize}${NC}"
        echo ""
        echo -e "  ${GRAY}Open with:  python3 -m http.server 8080 --directory /tmp${NC}"
        echo -e "  ${GRAY}Then visit: http://<pi-ip>:8080/$(basename "$result_path")${NC}"
    else
        echo -e "  ${RED}[!] Report generation failed.${NC}"
    fi

    pause
}

# ---------------------------------------------------------------------------
#  MAIN MENU
# ---------------------------------------------------------------------------

show_main_menu() {
    clear
    echo ""
    echo -e "  ${DCYAN}TuxAudit v1.0${NC}  ${GRAY}·${NC}  ${WHITE}Linux Configuration Audit${NC}"
    echo -e "  ${GRAY}${HOSTNAME_VAL}${NC}  ${GRAY}·${NC}  ${WHITE}${OS_NAME} ${OS_VERSION}${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${DYELLOW}SYSTEM${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo -e "  ${CYAN}[01]${NC} ${WHITE}OS Information${NC}              ${GRAY}Kernel, CPU, RAM, uptime, disks${NC}"
    echo -e "  ${CYAN}[02]${NC} ${WHITE}Users & Groups${NC}              ${GRAY}Local accounts, sudo, sudoers${NC}"
    echo -e "  ${CYAN}[15]${NC} ${WHITE}Kernel & Boot Security${NC}      ${GRAY}ASLR, sysctl, boot config (Pi)${NC}"
    echo ""
    echo -e "  ${DYELLOW}PROCESSES${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo -e "  ${CYAN}[03]${NC} ${WHITE}Process List${NC}                ${GRAY}Top CPU, suspicious paths${NC}"
    echo ""
    echo -e "  ${DYELLOW}NETWORK${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo -e "  ${CYAN}[04]${NC} ${WHITE}Network Interfaces${NC}          ${GRAY}IP, routes, promiscuous mode${NC}"
    echo -e "  ${CYAN}[05]${NC} ${WHITE}Open Ports & Connections${NC}    ${GRAY}Listening services, established${NC}"
    echo -e "  ${CYAN}[06]${NC} ${WHITE}Firewall Status${NC}             ${GRAY}UFW / iptables / firewalld${NC}"
    echo -e "  ${CYAN}[13]${NC} ${WHITE}Wi-Fi Configuration${NC}         ${GRAY}Saved profiles, PSK, scan${NC}"
    echo -e "  ${CYAN}[14]${NC} ${WHITE}Time Source (NTP)${NC}           ${GRAY}chrony, ntpd, drift${NC}"
    echo -e "  ${CYAN}[23]${NC} ${WHITE}Network Recon${NC}               ${GRAY}ARP, DNS, hosts, fail2ban${NC}"
    echo ""
    echo -e "  ${DYELLOW}SECURITY${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo -e "  ${CYAN}[07]${NC} ${WHITE}SSH Configuration${NC}           ${GRAY}sshd_config, authorized_keys${NC}"
    echo -e "  ${CYAN}[08]${NC} ${WHITE}Scheduled Tasks (Cron)${NC}      ${GRAY}All cron entries, suspicious jobs${NC}"
    echo -e "  ${CYAN}[09]${NC} ${WHITE}SUID / SGID Files${NC}           ${GRAY}Privilege escalation vectors${NC}"
    echo -e "  ${CYAN}[12]${NC} ${WHITE}System Logs Summary${NC}         ${GRAY}Auth failures, sudo usage${NC}"
    echo ""
    echo -e "  ${DYELLOW}PACKAGES & SERVICES${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo -e "  ${CYAN}[10]${NC} ${WHITE}Installed Packages${NC}          ${GRAY}Suspicious tools, recent installs${NC}"
    echo -e "  ${CYAN}[11]${NC} ${WHITE}Services${NC}                    ${GRAY}Enabled/running systemd units${NC}"
    echo ""
    echo -e "  ${DYELLOW}FORENSICS${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo -e "  ${CYAN}[16]${NC} ${WHITE}Bash History & IOCs${NC}         ${GRAY}/tmp files, deleted FDs, history${NC}"
    echo -e "  ${CYAN}[17]${NC} ${WHITE}Kernel Modules & Rootkits${NC}   ${GRAY}lsmod, dmesg, chkrootkit, rkhunter${NC}"
    echo -e "  ${CYAN}[18]${NC} ${WHITE}File Integrity${NC}              ${GRAY}debsums, rpm -Va, AIDE, recent changes${NC}"
    echo ""
    echo -e "  ${DYELLOW}SERVICES AUDIT${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo -e "  ${CYAN}[19]${NC} ${WHITE}Web Stack${NC}                   ${GRAY}Apache/Nginx, PHP, webshell detection${NC}"
    echo -e "  ${CYAN}[20]${NC} ${WHITE}Database Audit${NC}              ${GRAY}MySQL/PostgreSQL, exposure, accounts${NC}"
    echo -e "  ${CYAN}[21]${NC} ${WHITE}Container Audit${NC}             ${GRAY}Docker, Kubernetes, privileged containers${NC}"
    echo -e "  ${CYAN}[22]${NC} ${WHITE}File & Mail Services${NC}        ${GRAY}FTP, Samba, NFS, Postfix${NC}"
    echo ""

    # RHEL-specific extras
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        echo -e "  ${DYELLOW}RHEL/FEDORA SPECIFIC${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
        echo -e "  ${CYAN}[R1]${NC} ${WHITE}SELinux Status${NC}"
        echo -e "  ${CYAN}[R2]${NC} ${WHITE}DNF/YUM History${NC}"
        echo ""
    fi

    echo -e "  ${DYELLOW}OTHER${NC}"
    echo -e "  ${DCYAN}────────────────────────────────────${NC}"
    echo -e "  ${CYAN}[ALL]${NC} ${WHITE}Run Full Audit${NC}              ${GRAY}Execute all 23 modules + capture data${NC}"
    echo -e "  ${CYAN}[R]${NC}   ${WHITE}Generate HTML Report${NC}        ${GRAY}Export audit to HTML (use after [ALL])${NC}"
    echo -e "  ${CYAN}[D]${NC}   ${WHITE}Dashboard / Overview${NC}"
    echo -e "  ${CYAN}[O]${NC}   ${WHITE}Change OS${NC}                   ${GRAY}Re-run OS selection${NC}"
    echo -e "  ${CYAN}[Q]${NC}   ${WHITE}Quit${NC}"
    echo ""
}

# ---------------------------------------------------------------------------
#  MAIN LOOP
# ---------------------------------------------------------------------------

main() {
    check_root
    register_modules
    os_detection_banner

    while true; do
        show_main_menu
        read -rp "  $(echo -e "${WHITE}Your choice:${NC} ")" choice

        case "${choice^^}" in
            01)  module_01 ;;
            02)  module_02 ;;
            03)  module_03 ;;
            04)  module_04 ;;
            05)  module_05 ;;
            06)  module_06 ;;
            07)  module_07 ;;
            08)  module_08 ;;
            09)  module_09 ;;
            10)  module_10 ;;
            11)  module_11 ;;
            12)  module_12 ;;
            13)  module_13 ;;
            14)  module_14 ;;
            15)  module_15 ;;
            16)  module_16 ;;
            17)  module_17 ;;
            18)  module_18 ;;
            19)  module_19 ;;
            20)  module_20 ;;
            21)  module_21 ;;
            22)  module_22 ;;
            23)  module_23 ;;
            R1)  module_rhel_selinux ;;
            R2)  module_rhel_dnf_history ;;
            ALL) run_full_audit ;;
            R)   generate_report_interactive ;;
            D)   show_dashboard ;;
            O)   os_selection_menu ;;
            Q)
                echo ""
                echo -e "  ${CYAN}Goodbye!${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "  ${RED}Invalid choice.${NC}"
                sleep 0.7
                ;;
        esac
    done
}

main "$@"
