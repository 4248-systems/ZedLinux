#!/bin/bash
#
# ZedLinux Installer
#
# Usage:
#   install.sh [options]
#
# Options:
#   -y, --unattended        Do not prompt for anything; use flags/env vars or defaults
#       --ssh=yes|no        Allow SSH through the firewall (default: yes)
#       --desktop=yes|no    Install the ZedLinux desktop environment (default: no)
#       --rdp=yes|no        Install RDP (xrdp) - requires --desktop=yes (default: no)
#       --vnc=yes|no        Install VNC (TigerVNC) - requires --desktop=yes (default: no)
#       --cockpit=yes|no    Install Cockpit web console (default: no)
#       --sdk=yes|no        Install COBOL/Fortran/Pascal/C/C++ SDKs (default: no)
#       --force-fresh       Run a full (re)install even if ZedLinux is already present
#   -h, --help              Show this help text
#
# Environment variables (used when a flag is not given):
#   ZLINUX_SSH, ZLINUX_DESKTOP, ZLINUX_RDP, ZLINUX_VNC, ZLINUX_COCKPIT, ZLINUX_SDK

set -euo pipefail

LOG_FILE="/var/log/ZedLinux-install.log"
RELEASE_CONF="/etc/ZedLinux/release.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UNATTENDED="no"
FORCE_FRESH="no"
OPT_SSH=""
OPT_DESKTOP=""
OPT_RDP=""
OPT_VNC=""
OPT_COCKPIT=""
OPT_SDK=""
OPT_MVS_TK=""
RES_MVS_TK=""
RES_VIRTUALIZATION=""

DIALOG_AVAILABLE="no"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE" >&2
}

die() {
    log "ERROR: $*"
    exit 1
}

on_error() {
    local line="$1"
    log "installation failed at line ${line}. See ${LOG_FILE} for details."
}
trap 'on_error $LINENO' ERR


usage() {
    grep '^#' "${BASH_SOURCE[0]}" | sed -n '2,/^set -euo/p' | sed '$d' | sed 's/^# \{0,1\}//'
}

require_root() {
    [[ "$(id -u)" -eq 0 ]] || die "this installer must be run as root (try sudo)."
}


norm_yn() {
    case "${1,,}" in
        y|yes|1|true)  echo "yes" ;;
        n|no|0|false)  echo "no" ;;
        *) die "invalid yes/no value: '$1'" ;;
    esac
}

check_network() {
    if ! curl -fsS --max-time 5 -o /dev/null https://deb.debian.org 2>/dev/null \
       && ! ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
        log "WARNING: could not verify internet connectivity. Continuing anyway - package installs may fail."
    fi
}


ask() {
    local __var="$1" prompt="$2" default="$3"
    local current="${!__var-}"

    if [[ -n "$current" ]]; then
        printf -v "$__var" '%s' "$(norm_yn "$current")"
        return
    fi

    if [[ "$UNATTENDED" == "yes" ]]; then
        printf -v "$__var" '%s' "$default"
        return
    fi

    if [[ "$DIALOG_AVAILABLE" == "yes" ]]; then
        if dialog --title "ZedLinux Installer" --yesno "$prompt" 10 60; then
            printf -v "$__var" 'yes'
        else
            printf -v "$__var" 'no'
        fi
        return
    fi

    local reply
    read -r -p "$prompt [y/N]: " reply
    printf -v "$__var" '%s' "$(norm_yn "${reply:-n}")"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--unattended) UNATTENDED="yes" ;;
            --force-fresh) FORCE_FRESH="yes" ;;
            --ssh=*) OPT_SSH="${1#*=}" ;;
            --desktop=*) OPT_DESKTOP="${1#*=}" ;;
            --rdp=*) OPT_RDP="${1#*=}" ;;
            --vnc=*) OPT_VNC="${1#*=}" ;;
            --cockpit=*) OPT_COCKPIT="${1#*=}" ;;
            --sdk=*) OPT_SDK="${1#*=}" ;;
            --mvs-tk=*) OPT_MVS_TK="${1#*=}" ;;
            --virtualization=*) OPT_VIRTUALIZATION="${1#*=}" ;;
            -h|--help) usage; exit 0 ;;
            *) die "unknown option '$1' (--help for usage)" ;;
        esac
        shift
    done

    OPT_SSH="${OPT_SSH:-${ZLINUX_SSH:-}}"
    OPT_DESKTOP="${OPT_DESKTOP:-${ZLINUX_DESKTOP:-}}"
    OPT_RDP="${OPT_RDP:-${ZLINUX_RDP:-}}"
    OPT_VNC="${OPT_VNC:-${ZLINUX_VNC:-}}"
    OPT_COCKPIT="${OPT_COCKPIT:-${ZLINUX_COCKPIT:-}}"
    OPT_SDK="${OPT_SDK:-${ZLINUX_SDK:-}}"
    OPT_MVS_TK="${OPT_MVS_TK:-${ZLINUX_MVS_TK:-}}"
    OPT_VIRTUALIZATION="${OPT_VIRTUALIZATION:-${ZLINUX_VIRTUALIZATION:-}}"
}

sync_rootfs() {
    log "syncing rootfs overlay onto /"
    rsync -avh --progress "${SCRIPT_DIR}/rootfs/" / | tee -a "$LOG_FILE"

    if [[ -f "${SCRIPT_DIR}/chmod_x.lst" ]]; then
        while IFS= read -r file; do
            [[ -n "$file" && -f "$file" ]] || continue
            log "chmod +x: $file"
            chmod +x "$file"
        done < "${SCRIPT_DIR}/chmod_x.lst"
    fi
}

generate_os_release() {
    [[ -f "$RELEASE_CONF" ]] || return 0
    source <(sed -E 's/^([A-Z_]+)=/\1=/' "$RELEASE_CONF")
    {
        echo "NAME=\"${NAME:-ZedLinux}\""
        echo "PRETTY_NAME=\"${FULLNAME:-ZedLinux}\""
        echo "VERSION=\"${VERSION:-unknown}\""
        echo "VERSION_ID=\"${VERSION:-unknown}\""
        echo "ID=ZedLinux"
        echo "ID_LIKE=debian"
        echo "ANSI_COLOR=\"1;36\""
    } > /etc/os-release
    log "regenerated /etc/os-release"
}

run_update_path() {
    log "ZedLinux is already installed - refreshing packages and rootfs overlay."
    apt-get update
    apt-get upgrade -y
    sync_rootfs
    generate_os_release
    log "update complete."
}

install_base_packages() {
    log "installing base system utilities."
    apt-get update
    apt-get install -y \
        curl wget net-tools iproute2 iputils-ping traceroute mtr-tiny \
        nmap tcpdump wireshark-common tshark netcat-openbsd socat \
        dnsutils whois ethtool iperf3 nload iftop bmon vnstat rsync \
        htop btop iotop sysstat lsof strace ltrace \
        git vim nano tmux screen openssh-client openssh-server \
        build-essential python3 python3-pip \
        fail2ban ufw \
        arp-scan netdiscover masscan \
        speedtest-cli \
        jq unzip zip tree ncdu \
        bind9-dnsutils \
        wireguard-tools \
        network-manager mc sudo
}

configure_firewall() {
    log "configuring firewall (ufw)."
    ufw default deny incoming
    ufw default allow outgoing

    if [[ "$RES_SSH" == "yes" ]]; then
        ufw allow ssh
    fi

    ufw --force enable
}

install_desktop() {
    [[ "$RES_DESKTOP" == "yes" ]] || return 0

    log "installing XFCE desktop environment."
    apt-get install -y \
        xorg xserver-xorg lightdm lightdm-gtk-greeter \
        xfce4 xfce4-terminal xfce4-taskmanager xfce4-power-manager \
        thunar gvfs gvfs-backends file-roller mousepad ristretto \
        firefox-esr remmina \
        pavucontrol vlc mpv \
        gnome-disk-utility gparted \
        network-manager-gnome gufw filezilla \
        timeshift \
        virt-manager gnome-themes-extra \
        adwaita-icon-theme


    set_xfce_dark_theme_systemwide

    systemctl enable lightdm

    if [[ "$RES_RDP" == "yes" ]]; then
        log "installing xrdp."
        apt-get install -y xrdp
        systemctl enable xrdp
        ufw allow 3389/tcp
    fi

    if [[ "$RES_VNC" == "yes" ]]; then
        log "installing TigerVNC."
        apt-get install -y tigervnc-standalone-server tigervnc-common
        systemctl enable vncserver@:1.service
        ufw allow 5901/tcp
    fi
}

set_xfce_dark_theme_systemwide() {
    local xfce_dir="/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
    mkdir -p "$xfce_dir"

    cat > "$xfce_dir/xsettings.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita-dark"/>
    <property name="IconThemeName" type="string" value="Tango"/>
  </property>
</channel>
EOF

    cat > "$xfce_dir/xfwm4.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Default"/>
  </property>
</channel>
EOF

    mkdir -p /etc/xdg/gtk-3.0
    cat > /etc/xdg/gtk-3.0/settings.ini <<'EOF'
[Settings]
gtk-application-prefer-dark-theme=1
EOF
}

install_cockpit() {
    [[ "$RES_COCKPIT" == "yes" ]] || return 0
    log "installing Cockpit."
    apt-get install -y cockpit
    systemctl enable --now cockpit.socket
    ufw allow 9090/tcp
}

install_sdk() {
    [[ "$RES_SDK" == "yes" ]] || return 0
    log "installing language SDKs (COBOL, Fortran, Pascal, C/C++)."
    apt-get install -y \
        gnucobol4 \
        gfortran \
        fp-compiler fp-units-fcl fp-units-rtl \
        gcc g++ clang lldb \
        gdb make cmake ninja-build autoconf automake libtool pkg-config \
        manpages-dev bison flex ltrace strace db-util libdb-dev libgdm-dev
}

install_python_extras() {
    apt-get install -y python3-venv python3-dev python3-pyqt5 python3-tk python3-pil \
        python3-pandas python3-numpy python3-scipy python3-matplotlib
}

install_sdk_extras() {
    [[ "${RES_SDK_EXTRAS:-}" == "yes" ]] || return 0
    log "installing additional SDK extras."
    apt-get install -y \
        libblas-dev liblapack-dev libfftw3-dev \
        libgmp-dev libmpfr-dev libmpc-dev \
        libreadline-dev libncurses5-dev libncursesw5-dev \
        libx11-dev libxext-dev libxrender-dev libxrandr-dev \
        libxtst-dev libxi-dev libxinerama-dev \
        libgtk-3-dev libqt5core5a libqt5gui5 libqt5widgets5 \
        libboost-all-dev lazarus
}

mvs_tk_install() {
    [[ "$RES_MVS_TK" == "yes" ]] || return 0
    log "installing MVS TK5."

    rm -rf /usr/local/mvs-tk5
cat << 'EOF' > /usr/local/bin/mvs-start
#!/bin/bash
export MVS_TK5_HOME=/usr/local/mvs-tk5
echo "CONSOLE" > "$MVS_TK5_HOME/unattended/mode"
cd "$MVS_TK5_HOME"
exec ./mvs
EOF
    chmod +x /usr/local/bin/mvs-start
    apt-get install -y wget unzip x3270 c3270
    wget https://www.prince-webdesign.nl/images/downloads/mvs-tk5.zip
    unzip mvs-tk5.zip -d /usr/local/
    find /usr/local/mvs-tk5 -type f -exec chmod +x {} \;
    rm mvs-tk5.zip  
}

virtualization_containerization() {
    [[ "$RES_VIRTUALIZATION" == "yes" ]] || return 0
    log "installing virtualization and containerization tools."
    apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager docker.io qemu-system
    systemctl enable --now libvirtd
    systemctl enable --now docker
}

main() {
    parse_args "$@"
    require_root
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/ZedLinux-install.log"

    check_network

    if [[ -f "$RELEASE_CONF" && "$FORCE_FRESH" != "yes" ]]; then
        run_update_path
        exit 0
    fi

    if [[ "$UNATTENDED" != "yes" ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
        apt-get install -y dialog
        DIALOG_AVAILABLE="yes"
    fi

    local RES_SSH="" RES_DESKTOP="" RES_RDP="no" RES_VNC="no" RES_COCKPIT="" RES_SDK=""

    ask RES_SSH "Do you want to allow SSH connections through the firewall?" "yes"
    ask RES_DESKTOP "Do you want to install the ZedLinux desktop environment (XFCE)?" "no"
    ask RES_RDP "Do you want to install RDP (xrdp) for remote desktop access?" "no"
    ask RES_VNC "Do you want to install VNC (TigerVNC) for remote desktop access?" "no"

    ask RES_COCKPIT "Do you want to install Cockpit for web-based system administration?" "no"
    ask RES_SDK "Do you want to install ZedLinux COBOL, Fortran, Pascal and C/C++ support and SDKs?" "no"
    if [[ "$RES_SDK" == "yes" ]]; then
        ask RES_SDK_EXTRAS "Do you want to install additional SDK extras (libaries)?" "no"
    fi
    ask RES_MVS_TK "Do you want to install MVS TK5 for mainframe emulation?" "no"
    ask RES_VIRTUALIZATION "Do you want to install virtualization and containerization tools?" "no"

    local total_mem
    total_mem="$(free -m | awk '/^Mem:/{print $2}')"
    if [[ "$total_mem" -lt 10000 ]]; then
        log "WARNING: system has less than 10GB of RAM. Consider disabling non-essential services."
    fi

    install_base_packages
    configure_firewall
    install_desktop
    install_cockpit
    install_sdk
    install_python_extras
    install_sdk_extras
    mvs_tk_install
    virtualization_containerization

    sync_rootfs
    generate_os_release

    log "installation complete."
}

main "$@"