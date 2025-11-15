# ZFS RAID-Z1 Installer

A comprehensive bash script for installing a Linux live ISO (squashfs) to a ZFS RAID-Z1 array. This script addresses the limitation of most Linux installers that don't support installing directly to ZFS RAID configurations.

## Features

- **RAID-Z1 Support**: Install Linux on a ZFS RAID-Z1 array (minimum 3 disks)
- **UEFI and BIOS Support**: Works with both modern UEFI and legacy BIOS systems
- **Auto-Dependency Installation**: Automatically detects and installs missing prerequisites
- **Multi-Distro Support**: Works with Debian, Ubuntu, Fedora, RHEL, Arch, openSUSE
- **Automated Partitioning**: Automatically partitions disks with proper layouts
- **Dual Pool Design**: Separate boot pool (mirror) and root pool (RAID-Z1) for reliability
- **Bootloader Installation**: Configures GRUB with ZFS support
- **Interactive**: Guides users through disk selection and configuration
- **Comprehensive Logging**: Detailed logs for troubleshooting

## Prerequisites

### System Requirements

- **Minimum 3 disks** for RAID-Z1 (more disks recommended for better redundancy)
- Running from a **Linux live environment**
- Root/sudo access
- Internet connection (for automatic package installation)
- Sufficient RAM (4GB+ recommended)

### Required Packages (Auto-Installed)

The script **automatically detects and installs** missing dependencies using your system's package manager:

| Package Manager | Distributions | Auto-Install Support |
|----------------|---------------|---------------------|
| apt | Debian, Ubuntu, Linux Mint | ✅ Yes |
| dnf | Fedora 22+ | ✅ Yes |
| yum | RHEL, CentOS, Fedora <22 | ✅ Yes |
| pacman | Arch Linux, Manjaro | ✅ Yes |
| zypper | openSUSE, SLES | ✅ Yes |

**Packages installed automatically:**
- ZFS utilities (zfsutils-linux, zfs, zfs-utils)
- Partitioning tools (gdisk/gptfdisk)
- Filesystem tools (dosfstools)
- SquashFS tools (squashfs-tools)
- GRUB bootloader (grub-efi-amd64, grub-pc, or grub2)

**Note:** If automatic installation fails or you're on an unsupported distribution, you'll need to manually install the required packages before running the script.

## Usage

### Basic Usage

1. Boot into a Linux live environment (Debian, Ubuntu, Fedora, Arch, etc.)
2. Download or copy the script to the live system
3. Make it executable: `chmod +x install-to-zfs-raid.sh`
4. Run as root: `sudo ./install-to-zfs-raid.sh`
5. The script will automatically detect and install any missing dependencies

### Step-by-Step Example

```bash
# Boot from Linux Live ISO

# Make script executable
chmod +x install-to-zfs-raid.sh

# Run the installer (it will auto-install dependencies)
sudo ./install-to-zfs-raid.sh
```

The script will:
- Detect your package manager (apt, dnf, yum, pacman, or zypper)
- Check for required commands (zfs, sgdisk, mkfs.vfat, etc.)
- Automatically install any missing packages
- Proceed with the installation once all dependencies are satisfied

The script will guide you through:
1. Disk selection (select at least 3 disks)
2. Final confirmation (all data will be destroyed!)
3. Automatic partitioning and ZFS pool creation
4. System installation from squashfs
5. Bootloader configuration
6. Root password setup

## Disk Layout

### UEFI Systems

Each disk is partitioned as follows:

| Partition | Size | Type | Purpose |
|-----------|------|------|---------|
| 1 | 512M | EFI System (EF00) | EFI boot partition |
| 2 | 2G | Solaris Boot (BE00) | Boot pool (mirrored) |
| 3 | Rest | Solaris Root (BF00) | Root pool (RAID-Z1) |

### BIOS/Legacy Systems

Each disk is partitioned as follows:

| Partition | Size | Type | Purpose |
|-----------|------|------|---------|
| 1 | 1M | BIOS boot (EF02) | GRUB BIOS boot |
| 2 | 2G | Solaris Boot (BE00) | Boot pool (mirrored) |
| 3 | Rest | Solaris Root (BF00) | Root pool (RAID-Z1) |

## ZFS Pool Structure

### Boot Pool (bpool)

- **Configuration**: Mirror across all disks
- **Purpose**: Stores /boot directory for GRUB compatibility
- **Properties**:
  - Compression: lz4
  - Mountpoint: /boot

### Root Pool (rpool)

- **Configuration**: RAID-Z1 across all disks
- **Purpose**: Main system storage
- **Datasets**:
  - `rpool/ROOT/default` - Root filesystem (/)
  - `rpool/home` - User home directories
  - `rpool/var/log` - System logs
  - `rpool/var/spool` - Mail and print spools
  - `rpool/var/cache` - Package cache
  - `rpool/var/tmp` - Temporary files
  - `rpool/opt` - Optional software
  - `rpool/srv` - Service data
  - `rpool/usr-local` - Locally installed software

## Squashfs Paths

The script will prompt for the squashfs file path. Common locations:

| Distribution | Typical Path |
|--------------|--------------|
| Debian Live | `/run/live/medium/live/filesystem.squashfs` |
| Ubuntu Live | `/lib/live/mount/medium/casper/filesystem.squashfs` |
| Custom ISO | Mount ISO and locate the squashfs file |

## Post-Installation

After the script completes:

1. **Remove installation media**
2. **Reboot** the system
3. **Verify pools** import correctly (should be automatic)
4. **Create user accounts**:
   ```bash
   adduser yourusername
   usermod -aG sudo yourusername
   ```
5. **Update system**:
   ```bash
   apt-get update
   apt-get upgrade
   ```
6. **Configure networking** (if needed beyond DHCP)

## Troubleshooting

### Script Fails with Missing Commands

Ensure all required packages are installed:
```bash
apt-get install zfsutils-linux gdisk dosfstools squashfs-tools grub-efi-amd64
```

### Cannot Find Squashfs File

Mount your live ISO/USB and search for `.squashfs` files:
```bash
find /run -name "*.squashfs" 2>/dev/null
find /lib -name "*.squashfs" 2>/dev/null
```

### System Won't Boot After Installation

1. Boot from live media again
2. Import the pools:
   ```bash
   zpool import -f rpool
   zpool import -f bpool
   ```
3. Mount the root filesystem:
   ```bash
   zfs mount rpool/ROOT/default
   mount -t zfs bpool/BOOT/default /mnt/boot
   ```
4. Check GRUB installation:
   ```bash
   mount --rbind /dev /mnt/dev
   mount --rbind /proc /mnt/proc
   mount --rbind /sys /mnt/sys
   chroot /mnt
   update-grub
   grub-install /dev/sdX  # Replace with your disk
   ```

### Pool Import Issues

If pools don't import automatically on boot:
```bash
# Add to /etc/systemd/system/zfs-import-cache.service
zpool import -c /etc/zfs/zpool.cache -aN
```

## ZFS Management

### Common ZFS Commands

```bash
# Check pool status
zpool status

# Check pool health
zpool list

# Check dataset usage
zfs list

# Create snapshot
zfs snapshot rpool/home@backup-2024

# List snapshots
zfs list -t snapshot

# Rollback to snapshot
zfs rollback rpool/home@backup-2024

# Scrub pools (data integrity check)
zpool scrub rpool
zpool scrub bpool
```

### Performance Tuning

```bash
# Enable auto-snapshots (install zfs-auto-snapshot package)
apt-get install zfs-auto-snapshot

# Adjust ARC cache size (in /etc/modprobe.d/zfs.conf)
options zfs zfs_arc_max=8589934592  # 8GB

# Adjust compression
zfs set compression=lz4 rpool/home
zfs set compression=zstd rpool/var/log
```

## RAID-Z1 Considerations

### Advantages
- **Single disk fault tolerance**: Can survive one disk failure
- **Good storage efficiency**: (N-1)/N usable space
- **Better than RAID-5**: No write hole issue
- **Flexible**: Can add more vdevs (not disks to existing vdev)

### Disadvantages
- **Minimum 3 disks required**
- **Cannot add disks** to existing RAID-Z1 vdev
- **Slower rebuild** times with large disks
- **Performance**: RAID-Z1 is slower than mirrors for writes

### Recommended Configurations

| Disks | Configuration | Usable Space | Fault Tolerance |
|-------|---------------|--------------|-----------------|
| 3 | RAID-Z1 | 66% | 1 disk |
| 4 | RAID-Z1 | 75% | 1 disk |
| 5 | RAID-Z1 | 80% | 1 disk |
| 6+ | RAID-Z2 | (N-2)/N | 2 disks (recommended) |

## Security Notes

- **WARNING**: This script will **DESTROY ALL DATA** on selected disks
- Always verify disk selection before confirming
- Keep installation logs for reference
- Set strong root password during installation
- Consider full disk encryption for sensitive data (not included in this script)

## Customization

The script can be customized by editing these variables at the top:

```bash
POOL_NAME="rpool"           # Name of root pool
BOOT_POOL_NAME="bpool"      # Name of boot pool
MOUNT_POINT="/mnt"          # Installation mount point
MIN_DISKS=3                 # Minimum disks required
```

## Contributing

Contributions are welcome! Please:
1. Test changes in a VM environment
2. Document any new features
3. Follow existing code style
4. Add error handling for edge cases

## License

MIT License - See LICENSE file for details

## Acknowledgments

- OpenZFS project for excellent filesystem
- Debian and Ubuntu for ZFS integration
- Community contributions and testing

## References

- [OpenZFS Documentation](https://openzfs.github.io/openzfs-docs/)
- [Debian ZFS Root](https://github.com/openzfs/zfs/wiki/Debian)
- [Ubuntu ZFS Root](https://ubuntu.com/tutorials/setup-zfs-storage-pool)
- [ZFS Best Practices](https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Workload%20Tuning.html)

## Support

For issues and questions:
- Check the troubleshooting section
- Review installation logs in `/tmp/zfs-install-*.log`
- Consult OpenZFS documentation
- Seek help in ZFS community forums
