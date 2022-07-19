#!/bin/bash

# debuntu_inst.bash
# 22-07-18: v0.12
# Author: Tripole

# - Introduction -
# Template script to create a (grub) bootable Linux system image for ARM64 with
# either Ubuntu or Debian. The script is intended to be run on an exiting ARM64
# Ubuntu/Debian environment, for instance Ubuntu Server live.
#
# The script uses the Debian debootstrap mechanism to produce a base Ubuntu or
# base Debian install to e.g. a USB stick which can later be grub booted (e.g.
# via u-root-bootdisk). Alternatively, a compressed disk image file can be
# generated instead (but this takes longer time).
#
# The Ubuntu Server live iso is convenient to use since it will provide a
# Ubuntu/Debian environment with all hardware correctly identified and a
# working network connection. (To reach this state, one proceeds only with the
# first five steps of the Ubuntu Server installer; set keyboard, locale, type
# of install, network and archive mirror, and pause at partitioning. Then, one
# opens up a virtual terminal an proceeds from there.)

# - Prerequisites -
# For USB install the script assumes a certain partition layout of the target:
#
# /dev/sdX1: recommended at least 300M, ext4 (for /boot)
# /dev/sdX2: recommended at least 1G, swap
# /dev/sdX3: recommended at least 3G, ext4 (for /)
#
# The sizes can be different but the geometry is fixed. (The /boot partition
# must be formatted for ext4 booting but / can be anything that Ubuntu/Debian
# can mount and use but then the code below must be adjusted (look for ext4).)
# When the install target is a compressed disk image file a simpler
# one-partition geometry is used, with a single ext4 partition.

# - Usage -
# Tailored for use with Ubuntu Server but easily adapted to other environments:
# (0) Inspect the user editable parameters below and reconfigure as needed.
# (1) Boot up the Ubuntu Server install iso (e.g. using u-root-bootdisk) and go
#     through the first steps indicated above (stop at partitioning screen).
# (2) Switch to a virtial terminal (e.g. Alt-F2).
# (3) Become root: sudo su
# (4) Make sure that you have enough disk space: Ubuntu Server typically finds
#     and allocates all available remaining space on the USB where is resides,
#     and mounts this space (called/labeled "writable") under /var/log.
#     Thus, we do: cd /var/log ; mkdir debuntu ; cd debuntu
# (5) Then, download this script:
#     wget https://gitlab.com/tripole-inc/bootdisk/-/raw/main/debuntu_inst.bash
#     Make it executable: chmod +x debuntu_inst.bash
# (6) Only for USB install: Identify the install target USB device, e.g. /dev/
#     e.g. by issuing the command lsblk and looking at the output.
# (7) Run the script.
#     (a) For USB install do e.g.: ./debuntu_inst.bash debian /dev/sdX
#     (b) For disk image creation do e.g.: ./debuntu_inst.bash debian
#         Note: /var/log is transient storage; you must move and save a newly
#         created disk image before you reboot Ubuntu Server live.

# - Notes -
# It is easy to modify the script to add more packages or tweak the debootstrap
# procedure. The script installs the package debootstrap and possibly the
# package debian-archive-keyring. Installing to disk image takes a lot longer
# time and installation of some packages can take a long time, in particular
# the packages for firmware and kernel modules. Likewise, generation of
# initrd.img can take a long time as well as compression of the final image.
# (By commenting out two lines below you can skip the compression stage.)
# We do not set up a dtb file with the install (but there is a placeholder in
# grub.cfg) since this is not currently used with u-root-bootdisk. The script
# has been tested on Ugoos AM6 plus (Amlogic x922x SoC, 3.7GB ram).

# - Disclaimer -
# Use at you own risk. I cannot accept any responsibility for any adverse
# effects for you from the use of this script.

# ToDo (perhaps):
# - Set up networking properly for Ubuntu install (currently we use ifupdown).
# - Set up grub properly so that grub.cfg is updated at kernel updates.
# - Include some more script input/argument checks.
# - Enable optional wrapping by qemu-aarch64-static for cross debootstrapping.

# ------------------------ User editable parameters. --------------------------

# Edit these to your liking.
# distro_name is just a descriptive tag used by us.
# distro_release must be a correct lower case name.
case $1 in
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
    echo "Usage: debuntu_inst.bash distro mydev"
    echo "       where distro is one of: ubuntu,debian"
    echo "       and mydev is e.g.:      /dev/sdc"
    echo "       If mydev is absent, a compressed disk image is produced."
    echo "       For more customizable parameters, see inside the script."
    exit 0
    ;;
esac

# These two are only used on the installed image.
name_server_1=192.168.0.1 # Set to your router's IP address.
name_server_2=8.8.8.8     # Set to your backup DNS (8.8.8.8 is dns.google).

# For output in the form of an disk image file (uncompressed).
imgfile_name=${distro_name}_${distro_release}.img

# Location (dir) of disk image container during install (for size, see below).
imgfile_dir=$(pwd)

# Mount point for the debootstrap process.
mnt_dir=/mnt

#----------------------------------- code -----------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root, exiting."
    exit 1
fi

# Default is install to device (not disk image).
install_to_imgfile=0

# For disk image install: The raw (uncompressed) disk image size in MB. Must
# be enough to hold your install (with everything on a single root partition).
imgfile_sizeMB=3500

# For disk image install: Root partition label.
root_label=DBNT_ROOT

echo -e "\n-- You have selected to install $distro_name ($distro_release). --\n"

if [[ $# -eq 2 ]] ; then
    root_part_dev=${2}3
    boot_part_dev=${2}1
    swap_part_dev=${2}2

    uuid_boot_part=$(blkid -s UUID -o value $boot_part_dev)
    uuid_root_part=$(blkid -s UUID -o value $root_part_dev)
    uuid_swap_part=$(blkid -s UUID -o value $swap_part_dev)

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
else
    install_to_imgfile=1
    imgfile_loc=$imgfile_dir/$imgfile_name
    echo "The finished install will be in the file ${imgfile_loc}.xz"
    # If we assume that the compressed disk image is 40% of the original:
    reqd_spaceMB=$((14*${imgfile_sizeMB}/10)) # space for output img +img.xz
    echo "Make sure that you have enough space (~${reqd_spaceMB}MB +some)."
    echo "This is what you have:"
    df -h
    echo -n "Is this enough? [N,y] "
    read is_space_enough
    if [[ "$is_space_enough" == "y" ]] ; then
        echo "OK, good, continuing."
    else
        echo "OK, exiting."
        exit 1
    fi
fi

echo -e "\nGive a hostname for the new machine:"
echo -n ">"
read host_name

# Yes, we force setting up a local user.
echo "Enter the user name of a local user (will be in adm,sudo groups):"
echo -n ">"
read user_name

echo -e "\nStarting the installation..."

echo "Installing the debootstrap package."
apt install -y debootstrap

if [[ $install_to_imgfile -eq 1 ]] ; then
    echo "Creating ${imgfile_sizeMB}MB disk image container $imgfile_loc ... "
    dd if=/dev/zero of=$imgfile_loc bs=1M count=$imgfile_sizeMB status=progress
    echo "Done"
    echo "Setting up a loop device for the disk image container."
    losetup -f $imgfile_loc
    loop_dev=$(losetup -a | grep $imgfile_loc | cut -d ":" -f 1)
    num_cyls=$((1000*1000*$imgfile_sizeMB/512))
    echo -n "Creating an MBR (one part. $num_cyls cyls/sectors) "
    echo "inside disk image container."
    echo ",$num_cyls,83" | sfdisk $loop_dev
    partprobe $loop_dev
    root_part_dev=${loop_dev}p1
    echo "Formatting the disk image root partition with ext4... "
    mkfs.ext4 -F $root_part_dev
    echo "Done"
    echo "Setting disk image root partition label to $root_label"
    e2label $root_part_dev $root_label
    uuid_root_part=$(blkid -s UUID -o value $root_part_dev)
    echo "The disk image container (root part.) will be the install target."
    echo "It has UUID=$uuid_root_part"
fi

echo "Constructing templates for configuration files."

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

fstab_file_simple=$(cat <<EOF
UUID=$uuid_root_part  /      ext4   errors=remount-ro  0  1
EOF
)

fstab_file_part=$(cat <<EOF
UUID=$uuid_root_part  /      ext4   errors=remount-ro  0  1
UUID=$uuid_boot_part  /boot  ext4   defaults  0  2
UUID=$uuid_swap_part  none   swap   sw  0  0
EOF
)

debian_custom_inst=$(cat <<EOF
#!/bin/bash
apt clean
apt update
apt -y install linux-image-arm64
# apt -y install linux-headers-arm64
apt -y install locales ntp sudo console-setup
adduser ${user_name}
usermod -a -G adm,sudo ${user_name}
EOF
)

flashk_block_file=$(cat <<EOF
Package: flash-kernel
Pin: release *
Pin-Priority: -1
EOF
)

ubuntu_hosts_file=$(cat <<EOF
127.0.0.1    localhost
127.0.1.1    $host_name
# The following lines are desirable fo IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
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
apt clean
apt update
apt -y install linux-image-generic
# apt -y install linux-headers-generic
apt -y install man-db apt-utils nano ssh ifupdown dialog
dpkg-reconfigure keyboard-configuration
adduser ${user_name}
usermod -a -G adm,sudo ${user_name}
EOF
)

echo -n "Mounting the install target root partition under ${mnt_dir}..."
mount $root_part_dev $mnt_dir
echo " Done"

case $1 in
"ubuntu")
    echo "Performing debootstrapping of Ubuntu system to ${mnt_dir}."
    debootstrap --arch arm64 \
    --keyring /usr/share/keyrings/ubuntu-archive-keyring.gpg \
    $distro_release $mnt_dir $distro_repourl

    if [[ $install_to_imgfile -eq 0 ]] ; then
        echo "Mounting install target boot partition to ${mnt_dir}/boot."
        mount $boot_part_dev ${mnt_dir}/boot
	echo "Setting up /etc/fstab."
	echo -e "$fstab_file_part" >${mnt_dir}/etc/fstab
    else
        echo "Setting up /etc/fstab."
	echo -e "$fstab_file_simple" >${mnt_dir}/etc/fstab
    fi

    echo "Setting the hostname in /etc/hostname."
    echo -e "$host_name" >${mnt_dir}/etc/hostname
    echo "Setting up /etc/hosts."
    rm -f ${mnt_dir}/etc/hosts
    echo -e "$ubuntu_hosts_file" >${mnt_dir}/etc/hosts
    
    echo "Setting up /etc/network/interfaces."
    mkdir -p ${mnt_dir}/etc/network
    echo -e "$interfaces_file" >${mnt_dir}/etc/network/interfaces

    # This is a hack needed during install.
    echo "Setting up /etc/resolv.conf"
    rm -f ${mnt_dir}/etc/resolv.conf
    echo -e "$resolver_file" >${mnt_dir}/etc/resolv.conf

    echo "Preventing apt from installing flash-kernel."
    echo -e "$flashk_block_file" >\
	 ${mnt_dir}/etc/apt/preferences.d/no-flash-kernel

    echo "Set up a more complete /etc/apt/sources.list"
    rm -f ${mnt_dir}/etc/apt/sources.list
    echo -e "$ubuntu_repo_list" >${mnt_dir}/etc/apt/sources.list

    echo "Setting up the /sys /proc /dev/ mounts for chroot jail at $mnt_dir."
    for fs in /sys /proc /dev ; do mount --rbind $fs ${mnt_dir}/${fs} ; done

    echo "Preparing for chroot jail."
    echo -e "$ubuntu_custom_inst" >${mnt_dir}/root/ubuntu_custom_inst.bash
    chmod +x ${mnt_dir}/root/ubuntu_custom_inst.bash

    echo "Entering chroot jail and installing kernel and some extra packages."
    chroot $mnt_dir /root/ubuntu_custom_inst.bash

    echo "Cleaning up after chroot jail."
    rm ${mnt_dir}/root/ubuntu_custom_inst.bash
    mount --make-rprivate $mnt_dir
    for fs in /sys /proc /dev ; do umount -R ${mnt_dir}/${fs} ; done
    ;;
"debian")
    echo "Installing keyring for Debian."
    apt -y install debian-archive-keyring

    echo "Performing debootstrapping of Debian system to $mnt_dir."
    debootstrap --arch arm64 \
        --keyring /usr/share/keyrings/debian-archive-keyring.gpg \
    $distro_release $mnt_dir $distro_repourl

    if [[ $install_to_imgfile -eq 0 ]] ; then
	echo "Mounting install target boot partition to ${mnt_dir}/boot."
        mount $boot_part_dev ${mnt_dir}/boot
	echo "Setting up /etc/fstab."
	echo -e "$fstab_file_part" >${mnt_dir}/etc/fstab
    else
	echo "Setting up /etc/fstab."
	echo -e "$fstab_file_simple" >${mnt_dir}/etc/fstab
    fi

    echo "Setting the hostname in /etc/hostname."
    echo -e "$host_name" >${mnt_dir}/etc/hostname
    
    echo "Setting up /etc/network/interfaces."
    mkdir -p ${mnt_dir}/etc/network
    echo -e "$interfaces_file" >${mnt_dir}/etc/network/interfaces

    echo "Setting up the /sys /proc /dev/ mounts for chroot jail at $mnt_dir."
    for fs in /sys /proc /dev ; do mount --rbind $fs ${mnt_dir}/${fs} ; done

    echo "Preparing for chroot jail."
    echo -e "$debian_custom_inst" >${mnt_dir}/root/debian_custom_inst.bash
    chmod +x ${mnt_dir}/root/debian_custom_inst.bash

    echo "Entering chroot jail and installing kernel and some extra packages."
    chroot $mnt_dir /root/debian_custom_inst.bash

    echo "Cleaning up after chroot jail."
    rm ${mnt_dir}/root/debian_custom_inst.bash
    mount --make-rprivate $mnt_dir
    for fs in /sys /proc /dev ; do umount -R ${mnt_dir}/${fs} ; done

    echo "Adding the security updates repo to /etc/apt/sources.list"
    echo "deb http://security.debian.org/ bullseye-security main" >>\
         ${mnt_dir}/etc/apt/sources.list
    ;;
esac

cd ${mnt_dir}/boot
mkdir -p grub

# We loop here in case an update during install will add another kernel.
for kernel_version in $(ls | egrep "vmlinuz-" | cut -b 9-) ; do
    kernel_name=vmlinuz-${kernel_version}
    initrd_name=initrd.img-${kernel_version}

    if [[ $install_to_imgfile -eq 0 ]] ; then
        kernel_path=$kernel_name
	initrd_path=$initrd_name
    else
        kernel_path=boot/$kernel_name
	initrd_path=boot/$initrd_name
    fi

    # Note: The leading tabs in the here-document below are important.
    cat <<-EOF >> grub/grub.cfg
	menuentry "$distro_name $distro_release (kernel $kernel_version)" {
	
	# devicetree /meson-g12b-ugoos-am6.dtb # not used currently
	linux /$kernel_path root=UUID=$uuid_root_part
	initrd /$initrd_path
	
	}
EOF
done

echo -e "This is the contents of the grub.cfg file:\n"
cat ${mnt_dir}/boot/grub/grub.cfg

echo -e "\nUnmounting install target's partitions."
cd /root

if [[ $install_to_imgfile -eq 0 ]] ; then
    umount $boot_part_dev
    umount $root_part_dev
    echo "We are done and you can reboot now."
else
    umount $root_part_dev
    # If an uncompressed disk image is OK for you, comment out these two lines:
    echo "Creating compressed disk image file ${imgfile_loc}.xz"
    dd if=$loop_dev bs=1M status=progress | xz -c > ${imgfile_loc}.xz
    echo -n "Removing the loop device for the disk image file container... "
    losetup -d $loop_dev
    echo "Done"
    echo "We are done and you can reboot now."
    echo "If you are running a live image now: "
    echo "Remember to backup/save the install disk image file first!."
fi
