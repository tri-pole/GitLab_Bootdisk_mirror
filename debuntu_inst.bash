#!/bin/bash

# debuntu_inst.bash
# 22-07-15: v0.1
# Author: Tripole

# - Introduction -
# Script to create a (grub) bootable Linux system image for ARM64 with either
# Ubuntu or Debian. The script is intended to be run on an exiting ARM64
# Ubuntu/Debian environment, for instance Ubuntu Server live.
#
# A simple application of the Debian debootstrap mechanism is used to produce
# a base Ubuntu or base Debian install on e.g. a USB stick, which can later be
# grub booted (e.g. via u-root-bootdisk).
#
# The Ubuntu Server live iso is conventient to use since it will provide a
# Ubuntu/Debian environment with all hardware correctly identified and a
# working network connection. (To reach this state, one proceeds only with the
# first five steps of the Ubuntu Server installer; set keyboard, locale, type
# of install, network and archive mirror, and pause at partitioning. Then, one
# opens up a virtual terminal an proceeds from there.)

# - Prerequisites -
# The script assumes a certain partition layout of the install target device:
#
# /dev/sdX1: at least 300M, ext4 (for /boot)
# /dev/sdX2: at least 1G, swap
# /dev/sdX3: at least 10G, ext4 (for /)
#
# The sizes can be different but the layout is fixed. (The /boot partition
# must be formatted for ext4 booting but / can be anything that Ubuntu/Debian
# can mount and use.)

# - Usage of the script -
# (0) Prepare an install target USB according to the recipe above.
# (1) Boot up the Ubuntu Server install iso (e.g. using u-root-bootdisk) and go
#     through the first steps indicated above (stop at partitioning screen).
# (2) Switch to a virtial terminal (e.g. At-F2).
# (3) Become root (sudo su).
# (4) Download this script:
#     wget https://gitlab.com/tripole-inc/bootdisk/-/blob/main/lnxarm64inst.bash
#     Make it executable: chmod +x lnxarm64inst.bash
# (5) Identify the install target USB device, e.g. /dev/sdX, among the devices
#     attached, e.g. by issuing the command lsblk and looking at the output.
# (6) Run the script with install target device and distro as arguments, e.g.:
#     ./lnxarm64inst.bash /dev/sdX debian
#     (For available choices here, see below.) This will install the selected
#     distro into /dev/sdX with the partitioning layout above.

# Notes: We do not set up a dtb file with the install (there is a placeholder
# in grub.cfg though) since this is not currently used with u-root-bootdisk.
# It is easy to modify the script to add more packages or tweak the debootstrap
# procedure. This install script has been tested on an Ugoos Am6 plus.

# ToDo:
# - Set up networking properly for Ubuntu install (currently we use ifupdown).
# - Set up grub properly so that grub.cfg is updated at kernel updates.
# - Include some more script input/argument checks.

# ------------------------ User editable parameters. --------------------------

# Edit these to your liking.
# distro_name is just a descriptive tag used by us.
# distro_release must be a correct lower case name.
case $2 in
"ubuntu")
    distro_name=Ubuntu
    distro_release=jammy
    distro_repourl="http://ports.ubuntu.com/ubuntu-ports"
    ;;
"debian")
    distro_name=Debian
    distro_release=bullseye
    distro_repourl="http://ftp.debian.org/debian"
    ;;
*)
    echo "The distro name must be ubuntu or debian."
    exit 1
    ;;
esac

echo -e "-- You have selected to install $distro_name ($distro_release). --\n"

# Set this to your router's IP address.
name_server_1=192.168.0.1

#----------------------------------- code -----------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root, exiting."
    exit 1
fi

# Our backup DNS.
name_server_2=8.8.8.8

root_part_dev=${1}3
boot_part_dev=${1}1
swap_part_dev=${1}2

uuid_boot_part=$(/sbin/blkid $boot_part_dev | cut -d '"' -f 2)
uuid_root_part=$(/sbin/blkid $root_part_dev | cut -d '"' -f 2)
uuid_swap_part=$(/sbin/blkid $swap_part_dev | cut -d '"' -f 2)

echo -e "The target device for the install is\n"
echo -e "${1}\n"
echo -e "with the following partition default assignments\n"

echo "$boot_part_dev  UUID=$uuid_boot_part  boot partition (/boot)"
echo "$root_part_dev  UUID=$uuid_root_part  root partition (/)"
echo -e "$swap_part_dev  UUID=$uuid_swap_part  swap partition\n"

echo -n "Is this correct? [N,y] "
read is_part_correct

if [ "$is_part_correct" == "y" ]; then
    echo "OK, good, continuing."
else
    echo "OK, exiting."
    exit 1
fi

echo "Enter the user name of a local user (will be in adm,sudo groups):"
echo -n ">"
read loc_username

interfaces_file=$(cat <<EOF
allow-hotplug eth0
auto eth0
iface eth0 inet dhcp
EOF
)

resolver_file=$(cat <<EOF
nameserver $name_server_1
nameserver $name_server_2
EOF
)

fstab_file=$(cat <<EOF
UUID=$uuid_root_part  /      ext4   errors=remount-ro  0  1
UUID=$uuid_boot_part  /boot  ext4   defaults  0  2
UUID=$uuid_swap_part  none   swap   sw  0  0
EOF
)

debian_custom_inst=$(cat <<EOF
#!/bin/bash
apt update
apt -y install linux-image-arm64
# apt -y install linux-headers-arm64
apt -y install locales ntp sudo console-setup
adduser ${loc_username}
usermod -a -G adm,sudo ${loc_username}
EOF
)

flashk_block_file=$(cat <<EOF
Package: flash-kernel
Pin: release *
Pin-Priority: -1
EOF
)

ubuntu_repo_list=$(cat <<EOF
deb http://ports.ubuntu.com/ubuntu-ports/ jammy main restricted
deb http://ports.ubuntu.com/ubuntu-ports/ jammy-updates main restricted

deb http://ports.ubuntu.com/ubuntu-ports/ jammy universe
deb http://ports.ubuntu.com/ubuntu-ports/ jammy-updates universe

deb http://ports.ubuntu.com/ubuntu-ports/ jammy multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ jammy-updates multiverse

deb http://ports.ubuntu.com/ubuntu-ports/ jammy-backports main restricted universe multiverse

deb http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted
deb http://ports.ubuntu.com/ubuntu-ports/ jammy-security universe
deb http://ports.ubuntu.com/ubuntu-ports/ jammy-security multiverse
EOF
)

ubuntu_custom_inst=$(cat <<EOF
apt update
apt -y install linux-image-generic
# apt -y install linux-headers-generic
apt -y install man-db apt-utils sudo nano ssh ifupdown
adduser ${loc_username}
usermod -a -G adm,sudo ${loc_username}
EOF
)

echo "Starting the installation..."

echo "Installing the debootstrap package."
apt install -y debootstrap

echo -n "Mounting the install target root partition under /mnt..."
mount $root_part_dev /mnt
echo " Done"

case $2 in
"ubuntu")
    echo "Performing debootstrapping of Ubuntu system to /mnt."
    debootstrap --arch arm64 \
    --keyring /usr/share/keyrings/ubuntu-archive-keyring.gpg \
    $distro_release /mnt $distro_repourl

    echo "Mounting install target boot partition to /mnt/boot."
    mount $boot_part_dev /mnt/boot

    echo "Setting up /etc/network/interfaces."
    mkdir -p /mnt/etc/network
    echo -e "$interfaces_file" >/mnt/etc/network/interfaces

    # This is a hack needed during install.
    echo "Setting up resolv.conf"
    rm -f /mnt/etc/resolv.conf
    echo -e "$resolver_file" >/mnt/etc/resolv.conf

    echo "Setting up /etc/fstab."
    echo -e "$fstab_file" >/mnt/etc/fstab

    echo "Preventing apt from installing flash-kernel."
    echo -e "$flashk_block_file" >/mnt/etc/apt/preferences.d/no-flash-kernel

    echo "Set up a more complete /etc/apt/sources.list"
    rm -f /mnt/etc/apt/sources.list
    echo -e "$ubuntu_repo_list" >/mnt/etc/apt/sources.list

    echo "Setting up the /sys /proc /dev/ mounts for the chroot jail at /mnt."
    for f in /sys /proc /dev ; do mount --rbind $f /mnt/$f ; done

    echo "Preparing for chroot jail."
    echo -e "$ubuntu_custom_inst" >/mnt/root/ubuntu_custom_inst.bash
    chmod +x /mnt/root/ubuntu_custom_inst.bash

    echo "Entering chroot jail and installing kernel and some extra packages."
    chroot /mnt /root/ubuntu_custom_inst.bash

    echo "Cleaning up after chroot jail."
    rm /mnt/root/ubuntu_custom_inst.bash
    mount --make-rprivate /mnt
    for f in /sys /proc /dev ; do umount -R /mnt/$f ; done
    ;;
"debian")
    echo "Installing keyring for Debian."
    apt -y install debian-archive-keyring

    echo "Performing debootstrapping of Debian system to /mnt."
    debootstrap --arch arm64 \
        --keyring /usr/share/keyrings/debian-archive-keyring.gpg \
    $distro_release /mnt $distro_repourl

    echo "Mounting install target boot partition to /mnt/boot."
    mount $boot_part_dev /mnt/boot

    echo "Setting up /etc/network/interfaces."
    mkdir -p /mnt/etc/network
    echo -e "$interfaces_file" >/mnt/etc/network/interfaces

    echo "Setting up /etc/fstab."
    echo -e "$fstab_file" >/mnt/etc/fstab

    echo "Setting up the /sys /proc /dev/ mounts for the chroot jail at /mnt."
    for f in /sys /proc /dev ; do mount --rbind $f /mnt/$f ; done

    echo "Preparing for chroot jail."
    echo -e "$debian_custom_inst" >/mnt/root/debian_custom_inst.bash
    chmod +x /mnt/root/debian_custom_inst.bash

    echo "Entering chroot jail and installing kernel and some extra packages."
    chroot /mnt /root/debian_custom_inst.bash

    echo "Cleaning up after chroot jail."
    rm /mnt/root/debian_custom_inst.bash
    mount --make-rprivate /mnt
    for f in /sys /proc /dev ; do umount -R /mnt/$f ; done

    echo "Adding the security updates repo to /etc/apt/sources.list"
    echo "deb http://security.debian.org/ bullseye-security main" >>\
         /mnt/etc/apt/sources.list
    ;;
esac

cd /mnt/boot
mkdir -p grub

# We loop here in case an update during install will add another kernel.
for kernel_version in $(ls | egrep "vmlinuz-" | cut -b 9-) ; do
    kernel_name=vmlinuz-${kernel_version}
    initrd_name=initrd.img-${kernel_version}

    # Note: The leading tabs in the here-document below are important.
    cat <<-EOF >> grub/grub.cfg
	menuentry "$distro_name (kernel $kernel_version)" {
	
	# devicetree /meson-g12b-ugoos-am6.dtb
	linux /$kernel_name root=UUID=$uuid_root_part
	initrd /$initrd_name
	
	}
EOF
done

echo -e "grub.cfg file (on boot partition in subdir grub):\n"
cat /mnt/boot/grub/grub.cfg

echo -e "\nUnmounting install target's partitions."
cd /root
umount /mnt/boot
umount /mnt

echo "We are done and you can reboot now."
