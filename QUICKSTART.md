# Quick Start Guide

## TL;DR

```bash
# 1. Boot from Linux Live ISO with ZFS support
# 2. Install dependencies
sudo apt-get update && sudo apt-get install -y zfsutils-linux gdisk dosfstools squashfs-tools

# 3. Run the installer
sudo bash install-to-zfs-raid.sh
```

## What You Need

1. **At least 3 identical disks** (SSD or HDD)
2. **Linux Live USB/ISO** (Debian, Ubuntu, or similar with ZFS support)
3. **Network connection** (to install packages if needed)
4. **Backup of any important data** (disks will be wiped!)

## Installation Steps

### 1. Boot Live Environment

Boot from your Debian/Ubuntu Live USB or ISO.

### 2. Open Terminal

Open a terminal and become root:
```bash
sudo -i
```

### 3. Install Required Packages

```bash
apt-get update
apt-get install -y zfsutils-linux gdisk dosfstools squashfs-tools grub-efi-amd64
```

### 4. Download/Copy Script

If you have the script on a USB drive:
```bash
mount /dev/sdX1 /mnt  # Replace sdX1 with your USB partition
cp /mnt/install-to-zfs-raid.sh /root/
cd /root
```

Or download it (if you have internet):
```bash
# Copy from your source
```

### 5. Make Executable

```bash
chmod +x install-to-zfs-raid.sh
```

### 6. Run Installer

```bash
./install-to-zfs-raid.sh
```

### 7. Follow Prompts

The script will ask you to:
- Select disks (choose at least 3)
- Confirm disk selection (double-check!)
- Enter hostname
- Provide squashfs path (usually `/run/live/medium/live/filesystem.squashfs`)
- Set root password

### 8. Wait for Completion

The installation will take 10-30 minutes depending on:
- System size
- Disk speed
- Number of disks

### 9. Reboot

```bash
reboot
```

Remove the installation media when prompted.

## Example Session

```
root@debian-live:~# ./install-to-zfs-raid.sh

ZFS RAID-Z1 Installer v1.0.0
Boot mode detected: UEFI

Available disks:
  sda 120G Samsung SSD 850
  sdb 120G Samsung SSD 850
  sdc 120G Samsung SSD 850

You need to select at least 3 disks for RAID-Z1

Enter disk names separated by spaces: sda sdb sdc

The following disks will be COMPLETELY WIPED:
  - /dev/sda (120G)
  - /dev/sdb (120G)
  - /dev/sdc (120G)

Are you absolutely sure? [y/N]: y

Enter hostname [default: zfs-system]: myserver

==============================================
FINAL WARNING
==============================================
This will DESTROY all data on: sda sdb sdc
Boot mode: UEFI
Hostname: myserver

Type YES to proceed [y/N]: y

[... installation proceeds ...]

==============================================
Installation Complete!
==============================================
```

## Common Issues

### "Command not found: zfs"
Install zfsutils-linux:
```bash
apt-get install zfsutils-linux
```

### "Cannot find squashfs file"
Common locations:
- Debian: `/run/live/medium/live/filesystem.squashfs`
- Ubuntu: `/lib/live/mount/medium/casper/filesystem.squashfs`

Search for it:
```bash
find /run /lib -name "*.squashfs" 2>/dev/null
```

### "Not enough disks"
RAID-Z1 requires minimum 3 disks. Connect more disks or consider RAID-1 (mirror).

## After Installation

### First Boot

1. Log in as root with the password you set
2. Create a user:
   ```bash
   adduser yourname
   usermod -aG sudo yourname
   ```

3. Update system:
   ```bash
   apt-get update
   apt-get upgrade
   ```

4. Install additional software:
   ```bash
   apt-get install ssh vim htop
   ```

### Verify ZFS

```bash
# Check pool status
zpool status

# Should show:
#   pool: rpool
#   state: ONLINE
#   config:
#     raidz1-0  ONLINE
#       sda3    ONLINE
#       sdb3    ONLINE
#       sdc3    ONLINE

# Check datasets
zfs list

# Check disk usage
df -h
```

### Enable SSH (if needed)

```bash
apt-get install openssh-server
systemctl enable ssh
systemctl start ssh
```

## Testing in VM

Recommended for testing before real installation:

### VirtualBox

1. Create VM with at least 4GB RAM
2. Add 3+ virtual disks (10GB+ each)
3. Boot from Debian/Ubuntu Live ISO
4. Run installer
5. Remove ISO and reboot

### QEMU/KVM

```bash
# Create 3 disk images
qemu-img create -f qcow2 disk1.qcow2 20G
qemu-img create -f qcow2 disk2.qcow2 20G
qemu-img create -f qcow2 disk3.qcow2 20G

# Boot live ISO
qemu-system-x86_64 -m 4G -cdrom debian-live.iso \
  -drive file=disk1.qcow2 \
  -drive file=disk2.qcow2 \
  -drive file=disk3.qcow2 \
  -boot d
```

## Get Help

- Read full README.md for detailed documentation
- Check logs: `/tmp/zfs-install-*.log`
- OpenZFS docs: https://openzfs.github.io/openzfs-docs/
- Community forums and IRC

## Safety Checklist

Before running on real hardware:

- [ ] Backed up all important data
- [ ] Verified disk names are correct (check with `lsblk`)
- [ ] Have installation media ready to boot from if something goes wrong
- [ ] Tested in VM first (recommended)
- [ ] Read the full README.md
- [ ] Understand that ALL DATA WILL BE DESTROYED on selected disks

## Success!

Once installed, you have:
- ZFS RAID-Z1 root filesystem
- Single disk fault tolerance
- Automatic snapshots (if configured)
- Advanced filesystem features (compression, deduplication, etc.)
- Reliable, production-ready system

Enjoy your ZFS system!
