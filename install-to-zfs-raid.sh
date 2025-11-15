#!/bin/bash
#
# ZFS RAID-Z1 Installer Script
# Installs a Linux live ISO squashfs to a ZFS RAID-Z1 array
#
# Author: Claude AI
# License: MIT
#
# WARNING: This script will DESTROY all data on the selected disks!
#          Use with extreme caution and only on systems you intend to wipe.

set -e  # Exit on error
set -u  # Exit on undefined variable

#=============================================================================
# CONFIGURATION VARIABLES
#=============================================================================

SCRIPT_VERSION="1.1.0"
LOG_FILE="/tmp/zfs-install-$(date +%Y%m%d-%H%M%S).log"
POOL_NAME="rpool"
BOOT_POOL_NAME="bpool"
MOUNT_POINT="/mnt"
MIN_DISKS=3  # RAID-Z1 requires minimum 3 disks

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#=============================================================================
# UTILITY FUNCTIONS
#=============================================================================

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

die() {
    error "$*"
    exit 1
}

confirm() {
    local prompt="$1"
    local response
    while true; do
        read -p "$prompt [y/N]: " response
        case "$response" in
            [yY][eE][sS]|[yY])
                return 0
                ;;
            [nN][oO]|[nN]|"")
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

#=============================================================================
# PREREQUISITE CHECKS
#=============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root"
    fi
}

detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

get_package_for_command() {
    local cmd=$1
    local pkg_mgr=$2
    local boot_mode=$3

    # Map commands to packages based on package manager
    case "$pkg_mgr" in
        apt)
            case "$cmd" in
                zfs|zpool) echo "zfsutils-linux" ;;
                sgdisk) echo "gdisk" ;;
                mkfs.vfat) echo "dosfstools" ;;
                unsquashfs) echo "squashfs-tools" ;;
                grub-install)
                    if [[ "$boot_mode" == "UEFI" ]]; then
                        echo "grub-efi-amd64"
                    else
                        echo "grub-pc"
                    fi
                    ;;
                chroot) echo "coreutils" ;;
                *) echo "" ;;
            esac
            ;;
        dnf|yum)
            case "$cmd" in
                zfs|zpool) echo "zfs" ;;
                sgdisk) echo "gdisk" ;;
                mkfs.vfat) echo "dosfstools" ;;
                unsquashfs) echo "squashfs-tools" ;;
                grub-install)
                    if [[ "$boot_mode" == "UEFI" ]]; then
                        echo "grub2-efi-x64"
                    else
                        echo "grub2-pc"
                    fi
                    ;;
                chroot) echo "coreutils" ;;
                *) echo "" ;;
            esac
            ;;
        pacman)
            case "$cmd" in
                zfs|zpool) echo "zfs-utils" ;;
                sgdisk) echo "gptfdisk" ;;
                mkfs.vfat) echo "dosfstools" ;;
                unsquashfs) echo "squashfs-tools" ;;
                grub-install) echo "grub" ;;
                chroot) echo "coreutils" ;;
                *) echo "" ;;
            esac
            ;;
        zypper)
            case "$cmd" in
                zfs|zpool) echo "zfs" ;;
                sgdisk) echo "gptfdisk" ;;
                mkfs.vfat) echo "dosfstools" ;;
                unsquashfs) echo "squashfs-tools" ;;
                grub-install)
                    if [[ "$boot_mode" == "UEFI" ]]; then
                        echo "grub2-x86_64-efi"
                    else
                        echo "grub2"
                    fi
                    ;;
                chroot) echo "coreutils" ;;
                *) echo "" ;;
            esac
            ;;
        *)
            echo ""
            ;;
    esac
}

install_package() {
    local package=$1
    local pkg_mgr=$2

    log "Installing $package..."

    case "$pkg_mgr" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$package"
            ;;
        dnf)
            dnf install -y "$package"
            ;;
        yum)
            yum install -y "$package"
            ;;
        pacman)
            pacman -Sy --noconfirm "$package"
            ;;
        zypper)
            zypper install -y "$package"
            ;;
        *)
            return 1
            ;;
    esac
}

check_requirements() {
    log "Checking system requirements..."

    local required_cmds=("zfs" "zpool" "sgdisk" "mkfs.vfat" "unsquashfs" "chroot" "grub-install")
    local missing_cmds=()
    local pkg_mgr=$(detect_package_manager)
    local boot_mode=$(check_uefi)

    # First pass: identify missing commands
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_cmds+=("$cmd")
        fi
    done

    if [[ ${#missing_cmds[@]} -eq 0 ]]; then
        log "All required commands found"
        return 0
    fi

    # Attempt to install missing packages
    warn "Missing commands: ${missing_cmds[*]}"

    if [[ "$pkg_mgr" == "unknown" ]]; then
        error "Unable to detect package manager"
        error "Please manually install packages for: ${missing_cmds[*]}"
        die "Cannot auto-install dependencies"
    fi

    log "Detected package manager: $pkg_mgr"
    log "Attempting to install missing dependencies..."

    # Track packages we've already tried to install
    local -A installed_packages

    for cmd in "${missing_cmds[@]}"; do
        local package=$(get_package_for_command "$cmd" "$pkg_mgr" "$boot_mode")

        if [[ -z "$package" ]]; then
            warn "Unknown package for command: $cmd"
            continue
        fi

        # Skip if we've already installed this package
        if [[ -n "${installed_packages[$package]:-}" ]]; then
            continue
        fi

        info "Installing package: $package (provides $cmd)"

        if install_package "$package" "$pkg_mgr"; then
            log "Successfully installed $package"
            installed_packages[$package]=1
        else
            error "Failed to install $package"
        fi
    done

    # Second pass: verify all commands are now available
    local still_missing=()
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            still_missing+=("$cmd")
        fi
    done

    if [[ ${#still_missing[@]} -gt 0 ]]; then
        error "Still missing required commands after installation attempt: ${still_missing[*]}"
        info "Please manually install the required packages and try again"
        die "Missing required dependencies"
    fi

    log "All required commands are now available"
}

check_uefi() {
    if [[ -d /sys/firmware/efi ]]; then
        echo "UEFI"
    else
        echo "BIOS"
    fi
}

#=============================================================================
# DISK SELECTION AND PARTITIONING
#=============================================================================

list_disks() {
    log "Available disks:"
    lsblk -d -n -o NAME,SIZE,MODEL | grep -E '^(sd|nvme|vd)' | while read -r line; do
        echo "  $line"
    done
}

select_disks() {
    local -n disk_array=$1

    echo ""
    info "You need to select at least $MIN_DISKS disks for RAID-Z1"
    list_disks
    echo ""

    while true; do
        read -p "Enter disk names separated by spaces (e.g., sda sdb sdc): " -a disk_array

        if [[ ${#disk_array[@]} -lt $MIN_DISKS ]]; then
            error "RAID-Z1 requires at least $MIN_DISKS disks. You selected ${#disk_array[@]}."
            continue
        fi

        # Validate disks exist
        local all_exist=true
        for disk in "${disk_array[@]}"; do
            if [[ ! -b "/dev/$disk" ]]; then
                error "Disk /dev/$disk does not exist"
                all_exist=false
            fi
        done

        if [[ "$all_exist" == "false" ]]; then
            continue
        fi

        # Show what will be destroyed
        warn "The following disks will be COMPLETELY WIPED:"
        for disk in "${disk_array[@]}"; do
            echo "  - /dev/$disk ($(lsblk -d -n -o SIZE /dev/$disk))"
        done

        if confirm "Are you absolutely sure you want to continue?"; then
            break
        else
            disk_array=()
        fi
    done
}

partition_disk() {
    local disk=$1
    local boot_mode=$2

    log "Partitioning /dev/$disk..."

    # Wipe existing partition table
    sgdisk --zap-all "/dev/$disk" || die "Failed to zap disk /dev/$disk"

    if [[ "$boot_mode" == "UEFI" ]]; then
        # UEFI partitioning scheme:
        # Part 1: EFI System Partition (512M)
        # Part 2: Boot pool partition (2G)
        # Part 3: Root pool partition (rest of disk)

        sgdisk -n 1:0:+512M -t 1:EF00 -c 1:"EFI System" "/dev/$disk" || die "Failed to create EFI partition"
        sgdisk -n 2:0:+2G   -t 2:BE00 -c 2:"Boot Pool"  "/dev/$disk" || die "Failed to create boot pool partition"
        sgdisk -n 3:0:0     -t 3:BF00 -c 3:"Root Pool"  "/dev/$disk" || die "Failed to create root pool partition"
    else
        # BIOS partitioning scheme:
        # Part 1: BIOS boot partition (1M)
        # Part 2: Boot pool partition (2G)
        # Part 3: Root pool partition (rest of disk)

        sgdisk -n 1:0:+1M   -t 1:EF02 -c 1:"BIOS boot"  "/dev/$disk" || die "Failed to create BIOS boot partition"
        sgdisk -n 2:0:+2G   -t 2:BE00 -c 2:"Boot Pool"  "/dev/$disk" || die "Failed to create boot pool partition"
        sgdisk -n 3:0:0     -t 3:BF00 -c 3:"Root Pool"  "/dev/$disk" || die "Failed to create root pool partition"
    fi

    # Inform kernel of partition changes
    partprobe "/dev/$disk" 2>/dev/null || true
    sleep 2
}

get_partition_path() {
    local disk=$1
    local part_num=$2

    # Handle different disk naming schemes
    if [[ "$disk" =~ ^nvme ]]; then
        echo "/dev/${disk}p${part_num}"
    else
        echo "/dev/${disk}${part_num}"
    fi
}

#=============================================================================
# ZFS POOL CREATION
#=============================================================================

create_boot_pool() {
    local -n disks=$1
    local boot_parts=()

    log "Creating boot pool (mirror)..."

    for disk in "${disks[@]}"; do
        boot_parts+=("$(get_partition_path "$disk" 2)")
    done

    # Boot pool should be mirror for compatibility
    # Use ashift=12 for 4K sectors
    zpool create -f \
        -o ashift=12 \
        -o autotrim=on \
        -O acltype=posixacl \
        -O canmount=off \
        -O compression=lz4 \
        -O devices=off \
        -O normalization=formD \
        -O relatime=on \
        -O xattr=sa \
        -O mountpoint=/boot \
        -R "$MOUNT_POINT" \
        "$BOOT_POOL_NAME" \
        mirror "${boot_parts[@]}" || die "Failed to create boot pool"

    log "Boot pool created successfully"
}

create_root_pool() {
    local -n disks=$1
    local root_parts=()

    log "Creating root pool (RAID-Z1)..."

    for disk in "${disks[@]}"; do
        root_parts+=("$(get_partition_path "$disk" 3)")
    done

    # Create root pool with RAID-Z1
    zpool create -f \
        -o ashift=12 \
        -o autotrim=on \
        -O acltype=posixacl \
        -O canmount=off \
        -O compression=lz4 \
        -O dnodesize=auto \
        -O normalization=formD \
        -O relatime=on \
        -O xattr=sa \
        -O mountpoint=/ \
        -R "$MOUNT_POINT" \
        "$POOL_NAME" \
        raidz1 "${root_parts[@]}" || die "Failed to create root pool"

    log "Root pool created successfully"
}

create_datasets() {
    log "Creating ZFS datasets..."

    # Create boot dataset
    zfs create -o canmount=off -o mountpoint=none "$BOOT_POOL_NAME"/BOOT
    zfs create -o mountpoint=/boot "$BOOT_POOL_NAME"/BOOT/default || die "Failed to create boot dataset"

    # Create root container
    zfs create -o canmount=off -o mountpoint=none "$POOL_NAME"/ROOT

    # Create root filesystem
    zfs create -o canmount=noauto -o mountpoint=/ "$POOL_NAME"/ROOT/default || die "Failed to create root dataset"
    zfs mount "$POOL_NAME"/ROOT/default

    # Create home dataset
    zfs create -o mountpoint=/home "$POOL_NAME"/home || die "Failed to create home dataset"

    # Create var datasets
    zfs create -o canmount=off -o mountpoint=none "$POOL_NAME"/var
    zfs create -o mountpoint=/var/log "$POOL_NAME"/var/log
    zfs create -o mountpoint=/var/spool "$POOL_NAME"/var/spool
    zfs create -o mountpoint=/var/cache "$POOL_NAME"/var/cache
    zfs create -o mountpoint=/var/tmp "$POOL_NAME"/var/tmp

    # Create optional datasets
    zfs create -o mountpoint=/opt "$POOL_NAME"/opt
    zfs create -o mountpoint=/srv "$POOL_NAME"/srv
    zfs create -o mountpoint=/usr/local "$POOL_NAME"/usr-local

    # Set bootfs
    zpool set bootfs="$POOL_NAME"/ROOT/default "$POOL_NAME"

    log "Datasets created successfully"
}

format_efi_partitions() {
    local -n disks=$1
    local boot_mode=$2

    if [[ "$boot_mode" == "UEFI" ]]; then
        log "Formatting EFI partitions..."

        local first_disk="${disks[0]}"
        local efi_part=$(get_partition_path "$first_disk" 1)

        mkfs.vfat -F32 -n EFI "$efi_part" || die "Failed to format EFI partition"

        mkdir -p "$MOUNT_POINT/boot/efi"
        mount "$efi_part" "$MOUNT_POINT/boot/efi" || die "Failed to mount EFI partition"

        log "EFI partition formatted and mounted"
    fi
}

#=============================================================================
# SYSTEM INSTALLATION
#=============================================================================

select_squashfs() {
    local squashfs_path=""

    info "Please provide the path to the squashfs file to install"
    info "Common locations:"
    info "  - /run/live/medium/live/filesystem.squashfs (Debian Live)"
    info "  - /lib/live/mount/medium/casper/filesystem.squashfs (Ubuntu Live)"
    info "  - Custom path from mounted ISO"

    while true; do
        read -p "Enter squashfs path: " squashfs_path

        if [[ -f "$squashfs_path" ]]; then
            if file "$squashfs_path" | grep -q "Squashfs"; then
                echo "$squashfs_path"
                return 0
            else
                error "File is not a valid squashfs file"
            fi
        else
            error "File does not exist: $squashfs_path"
        fi
    done
}

install_system() {
    local squashfs_path=$1

    log "Installing system from $squashfs_path..."

    # Extract squashfs to mounted ZFS
    unsquashfs -f -d "$MOUNT_POINT" "$squashfs_path" || die "Failed to extract squashfs"

    # Remove live-specific packages list if exists
    rm -f "$MOUNT_POINT/var/lib/dpkg/info/live-*" 2>/dev/null || true

    log "System files extracted successfully"
}

#=============================================================================
# SYSTEM CONFIGURATION
#=============================================================================

configure_system() {
    local hostname=$1
    local -n disks=$2
    local boot_mode=$3

    log "Configuring system..."

    # Set hostname
    echo "$hostname" > "$MOUNT_POINT/etc/hostname"

    # Configure hosts file
    cat > "$MOUNT_POINT/etc/hosts" <<EOF
127.0.0.1       localhost
127.0.1.1       $hostname

# The following lines are desirable for IPv6 capable hosts
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

    # Configure fstab
    cat > "$MOUNT_POINT/etc/fstab" <<EOF
# /etc/fstab: static file system information.
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>

# ZFS datasets are mounted by ZFS itself
# Only the EFI partition needs to be in fstab
EOF

    if [[ "$boot_mode" == "UEFI" ]]; then
        local first_disk="${disks[0]}"
        local efi_part=$(get_partition_path "$first_disk" 1)
        local efi_uuid=$(blkid -s UUID -o value "$efi_part")
        echo "UUID=$efi_uuid  /boot/efi  vfat  defaults  0  1" >> "$MOUNT_POINT/etc/fstab"
    fi

    # Configure network interfaces (basic DHCP)
    mkdir -p "$MOUNT_POINT/etc/network/interfaces.d"
    cat > "$MOUNT_POINT/etc/network/interfaces" <<EOF
# interfaces(5) file used by ifup(8) and ifdown(8)
auto lo
iface lo inet loopback

# Primary network interface (DHCP)
auto eth0
iface eth0 inet dhcp

auto enp0s3
iface enp0s3 inet dhcp
EOF

    log "System configuration completed"
}

configure_bootloader() {
    local -n disks=$1
    local boot_mode=$2

    log "Configuring bootloader..."

    # Bind mount necessary filesystems
    mount --rbind /dev  "$MOUNT_POINT/dev"
    mount --rbind /proc "$MOUNT_POINT/proc"
    mount --rbind /sys  "$MOUNT_POINT/sys"
    mount --rbind /run  "$MOUNT_POINT/run"

    # Create chroot script
    cat > "$MOUNT_POINT/tmp/setup-boot.sh" <<'CHROOT_SCRIPT'
#!/bin/bash
set -e

echo "Installing ZFS support packages..."

# Ensure ZFS packages are installed
if ! dpkg -l | grep -q zfs-initramfs; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        zfs-initramfs \
        zfs-zed \
        zfsutils-linux \
        || echo "Warning: Could not install ZFS packages"
fi

# Ensure GRUB is installed
if ! dpkg -l | grep -q grub; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y grub-pc || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y grub-efi-amd64 || \
    echo "Warning: Could not install GRUB"
fi

echo "Configuring GRUB..."

# Configure GRUB for ZFS
cat >> /etc/default/grub <<EOF

# ZFS Configuration
GRUB_CMDLINE_LINUX="root=ZFS=rpool/ROOT/default boot=zfs"
GRUB_TERMINAL=console
EOF

# Disable os-prober to avoid errors
echo "GRUB_DISABLE_OS_PROBER=true" >> /etc/default/grub

echo "Updating initramfs..."
update-initramfs -u -k all || echo "Warning: initramfs update had errors"

echo "Installing GRUB..."
CHROOT_SCRIPT

    if [[ "$boot_mode" == "UEFI" ]]; then
        echo 'grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck || echo "Warning: GRUB installation had errors"' >> "$MOUNT_POINT/tmp/setup-boot.sh"
    else
        for disk in "${disks[@]}"; do
            echo "grub-install --target=i386-pc /dev/$disk || echo 'Warning: GRUB installation to /dev/$disk had errors'" >> "$MOUNT_POINT/tmp/setup-boot.sh"
        done
    fi

    cat >> "$MOUNT_POINT/tmp/setup-boot.sh" <<'CHROOT_SCRIPT'

echo "Updating GRUB configuration..."
update-grub || echo "Warning: GRUB update had errors"

echo "Bootloader setup complete"
CHROOT_SCRIPT

    chmod +x "$MOUNT_POINT/tmp/setup-boot.sh"

    # Execute in chroot
    chroot "$MOUNT_POINT" /tmp/setup-boot.sh || warn "Chroot bootloader setup had errors"

    # Cleanup
    rm "$MOUNT_POINT/tmp/setup-boot.sh"

    # Unmount bind mounts
    umount -l "$MOUNT_POINT/run" 2>/dev/null || true
    umount -l "$MOUNT_POINT/sys" 2>/dev/null || true
    umount -l "$MOUNT_POINT/proc" 2>/dev/null || true
    umount -l "$MOUNT_POINT/dev" 2>/dev/null || true

    log "Bootloader configuration completed"
}

set_root_password() {
    log "Setting root password..."

    mount --rbind /dev  "$MOUNT_POINT/dev"
    mount --rbind /proc "$MOUNT_POINT/proc"
    mount --rbind /sys  "$MOUNT_POINT/sys"

    info "Please set the root password for the new system:"
    chroot "$MOUNT_POINT" passwd root || warn "Failed to set root password"

    umount -l "$MOUNT_POINT/sys" 2>/dev/null || true
    umount -l "$MOUNT_POINT/proc" 2>/dev/null || true
    umount -l "$MOUNT_POINT/dev" 2>/dev/null || true
}

#=============================================================================
# CLEANUP AND FINALIZATION
#=============================================================================

cleanup() {
    log "Performing cleanup..."

    # Unmount everything
    if mountpoint -q "$MOUNT_POINT/boot/efi" 2>/dev/null; then
        umount "$MOUNT_POINT/boot/efi" || warn "Failed to unmount EFI partition"
    fi

    # Export pools
    zpool export "$BOOT_POOL_NAME" 2>/dev/null || warn "Failed to export boot pool"
    zpool export "$POOL_NAME" 2>/dev/null || warn "Failed to export root pool"

    log "Cleanup completed"
}

show_summary() {
    local -n disks=$1
    local boot_mode=$2

    echo ""
    log "=============================================="
    log "Installation Complete!"
    log "=============================================="
    echo ""
    info "Configuration Summary:"
    info "  Boot Mode: $boot_mode"
    info "  Disks Used: ${disks[*]}"
    info "  Root Pool: $POOL_NAME (RAID-Z1)"
    info "  Boot Pool: $BOOT_POOL_NAME (Mirror)"
    info "  Log File: $LOG_FILE"
    echo ""
    warn "Important Post-Installation Steps:"
    warn "  1. Remove the installation media"
    warn "  2. Reboot the system"
    warn "  3. Import pools if necessary:"
    warn "     zpool import -R /mnt $POOL_NAME"
    warn "  4. Set up additional users"
    warn "  5. Configure networking if needed"
    warn "  6. Update system packages"
    echo ""
}

#=============================================================================
# MAIN INSTALLATION WORKFLOW
#=============================================================================

main() {
    log "ZFS RAID-Z1 Installer v$SCRIPT_VERSION"
    log "Log file: $LOG_FILE"

    # Prerequisite checks
    check_root
    check_requirements

    local boot_mode=$(check_uefi)
    log "Boot mode detected: $boot_mode"

    # Disk selection
    local -a selected_disks
    select_disks selected_disks

    # Get hostname
    local hostname
    read -p "Enter hostname for the new system [default: zfs-system]: " hostname
    hostname=${hostname:-zfs-system}

    # Final confirmation
    echo ""
    warn "=============================================="
    warn "FINAL WARNING"
    warn "=============================================="
    warn "This will DESTROY all data on: ${selected_disks[*]}"
    warn "Boot mode: $boot_mode"
    warn "Hostname: $hostname"
    echo ""

    if ! confirm "Type YES in capital letters to proceed"; then
        die "Installation cancelled by user"
    fi

    # Partition disks
    for disk in "${selected_disks[@]}"; do
        partition_disk "$disk" "$boot_mode"
    done

    # Create ZFS pools
    create_boot_pool selected_disks
    create_root_pool selected_disks
    create_datasets
    format_efi_partitions selected_disks "$boot_mode"

    # Install system
    local squashfs_path=$(select_squashfs)
    install_system "$squashfs_path"

    # Configure system
    configure_system "$hostname" selected_disks "$boot_mode"
    configure_bootloader selected_disks "$boot_mode"
    set_root_password

    # Cleanup and summary
    cleanup
    show_summary selected_disks "$boot_mode"

    log "Installation completed successfully!"
}

# Trap errors and cleanup
trap cleanup EXIT

# Run main
main "$@"
