#!/bin/bash

# ubuntu_mkimg.bash (a.k.a. flibuntu_mkimg.bash)
# 22-09-18: v0.1
# Author: Tripole

# Script to generate an Ubuntu ARM64 (CLI, "server") image with a custom kernel
# (flippy-76) for Amlogic TV-boxes/SBCs. The Ubuntu infrastructure is based in
# daily builds of the rootfs of the latest LTS release (currently 22.04 Jammy).
# The script must be executed (as root) on an Ubuntu/Debian type ARM64 machine
# (e.g. Ubuntu Server Live booted via bootdisk). The generated image can be
# booted using resident/vendor u-boot (using the boot scripts on the fat
# partition) or via bootdisk (using the grub.cfg file on the rootfs partition).
# Tested on Ugoos AM6 plus (s922x, for booting and running) and on QEMU
# (qemu-system-aarch64, for developing/executing). This script is simply a
# template or proof-of-concept, nothing more. (Please, fork it, improve it.)

# Requires: Standard basic functionality incl. blkid, dd, losetup, mkfs, xv,
# wget and the packages u-boot-tools, systemd-container (for systemd-nspawn)
# ArchLinux wiki:
# "systemd-nspawn is like the chroot command, but it is a chroot on steroids."

# Inspiration taken from
# https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/rebuild
# https://github.com/manjaro-arm/am6-plus-images/releases

# Typical usage: Edit the parameters below and run the script from a temp dir
# (the image as well as all temporary files will be created in this dir).

# Notes:
# - The uImage and uInitrd (u-boot tagged) versions of the kernel and
# initramfs that are on the fat partition are created "once and for all" by
# the mkimage command in the script below. Thus, when updating the kernel or
# initramfs then also uImage and uInitrd have to be recreated manually (unless
# you rely on grub booting e.g. via bootdisk, then only /boot/grub/grub.cfg
# on the rootfs partition has to be updated; for inspiration, see below).
# - The rootfs is installed in "minimized" state for many packages. It is
# therefore advisable to run the command unminimize (and reboot) to restore the
# system into normal state.
# - Depending on the terminal used when running the script, the keyboard setup
# may not run properly so it has to be set up afterwards (by running the cmd
# dpkg-reconfigure keyboard-configuration, or editing /etc/default/keyboard).
# - In general, the system configuration is minimal, so e.g. no swap is set up.

# ------------------------------- parameters -------------------------------

# Do not edit the next two, for now.
distro_name=Ubuntu
distro_edition=Jammy

distro_release="$(tr [A-Z] [a-z] <<< "$distro_edition")" # To lowercase.

# Official Ubuntu rootfs tarball.
distro_urlbase="https://cdimage.ubuntu.com/ubuntu-base"/${distro_release}
distro_relstr=daily/current
distro_buildfile=${distro_release}-base-arm64.tar.gz
distro_buildurl=${distro_urlbase}/${distro_relstr}/${distro_buildfile}

# Ophub repo with his builds of Flippy/Unifreq kernels (incl. initramfs, thx.).
kernel_release="5.19.9-flippy-76+" # Name string with special characters.
kernel_urlboot="https://github.com/ophub/kernel/raw/main/pub/stable/5.19.9/boot-5.19.9-flippy-76%2B.tar.gz"
kernel_urlmods="https://github.com/ophub/kernel/raw/main/pub/stable/5.19.9/modules-5.19.9-flippy-76%2B.tar.gz"
kernel_urldtbs="https://github.com/ophub/kernel/raw/main/pub/stable/5.19.9/dtb-amlogic-5.19.9-flippy-76%2B.tar.gz"

# Edit this to your liking.
img_tag=${kernel_release}_3pole-$(date +"%y%m%d")

imgfile_name=${distro_name}_${distro_edition}_${img_tag}.img

# Location (dir) of disk image container during install (for size, see below).
imgfile_dir=$PWD
tmpfile_dir=${imgfile_dir}/temp_files

# File system sizes and types (unit MiB).
# - The partition table type on the image is MBR.
# - The min skip (gap) size (before 1st part) is 1MB (2048 sectors, 512B each).
# - The boot fs type is vfat/fat32 and the root fs type is one of {ext4,btrfs}.
# Note: The boot fs is only for u-boot formatted copies of kernel +initramfs.
skip_MB=1
boot_MB=100
root_MB=3000
rootfs_type=ext4
bootfs_label=UBNT_BOOT
rootfs_label=UBNT_ROOT

# The string root=UUID=${rootfs_UUID} will be prepended below once UUID exists.
kernel_cmdline_opts="rootdelay=3 rootflags=data=writeback rw console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 loglevel=1"

# This is the dtb file name pointed to in uEnv.ini
dtbfile_name=meson-g12b-ugoos-am6.dtb

# Compression (xz) takes some extra time.
compressed_img=no # {yes,no}

# Temporary moint points (dirs) used during image creation.
rootfs_mnt=${imgfile_dir}/rootfs_tmp
bootfs_dir=/boot/aux
bootfs_mnt=${rootfs_mnt}/${bootfs_dir}

# These two are only (possibly) used on the installed image.
name_server_1=192.168.0.1 # Set to your router's IP address.
name_server_2=8.8.8.8     # Set to your backup DNS (8.8.8.8 is dns.google).

# Do we want to clean up all temporary files and directories afterwards?
docleanup_after=yes # {yes,no}

# UUIDs can also be generated with the cmd uuidgen from the pkg uuid-runtime.
rootfs_UUID=$(cat /proc/sys/kernel/random/uuid)
if [[ -z $rootfs_UUID ]]; then
    echo ${e_msg}" Cannot generate a valid UUID for the rootfs, exiting."
    exit 1
fi

kernel_cmdline="root=UUID=${rootfs_UUID} "${kernel_cmdline_opts}

# Bling? Yes, we like.
i_msg="[\033[94m Info \033[0m]"
w_msg="[\033[93m Warning \033[0m]"
e_msg="[\033[91m Error \033[0m]"

# Below we add also a line for the vfat boot partition.
fstab_file=$(cat <<EOF
UUID=$rootfs_UUID  /  $rootfs_type   errors=remount-ro  0  1
EOF
)

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

hosts_file=$(cat <<EOF
127.0.0.1    localhost
127.0.1.1    $host_name
# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
)

flashk_block_file=$(cat <<EOF
Package: flash-kernel
Pin: release *
Pin-Priority: -1
EOF
)

# If you want to add packages, this is the place to do it (just before EOF).
# To add the generic (ARM64) kernel do apt -y install linux-image-generic
# but then the GRUB_CMDLINE_LINUX definition below should be removed/adjusted.
ubuntu_custom_inst=$(cat <<EOF
apt update
apt -y install man-db apt-utils nano ssh ifupdown grub2-common
apt -y install dialog keyboard-configuration
dpkg-reconfigure keyboard-configuration
echo "Set password for root:"
until passwd; do echo "Try again."; done
# If you want to add a local user, uncomment these lines and dialog below.
# adduser $user_name
# usermod -a -G adm,sudo $user_name
EOF
)

# The doble quotes around the limit string EOF prevents command substitution.
aml_autoscript=$(cat <<"EOF"
defenv
setenv bootcmd 'run start_autoscript; run storeboot'
setenv start_autoscript 'mmcinfo && run start_mmc_autoscript; usb start && run start_usb_autoscript; run start_emmc_autoscript'
setenv start_emmc_autoscript 'fatload mmc 1 1020000 emmc_autoscript && autoscr 1020000'
setenv start_mmc_autoscript 'fatload mmc 0 1020000 s905_autoscript && autoscr 1020000'
setenv start_usb_autoscript 'for usbdev in 0 1 2 3; do fatload usb ${usbdev} 1020000 s905_autoscript && autoscr 1020000; done'
setenv system_part b
setenv upgrade_step 2
saveenv
sleep 1
reboot
EOF
)

s905_autoscript=$(cat <<"EOF"
if fatload mmc 0 0x1000000 u-boot.ext; then go 0x1000000; fi;
if fatload usb 0 0x1000000 u-boot.ext; then go 0x1000000; fi;
setenv env_addr 0x1040000
setenv initrd_addr 0x13000000
setenv boot_start 'bootm ${loadaddr} ${initrd_addr} ${dtb_mem_addr}'
setenv addmac 'if printenv mac; then setenv bootargs ${bootargs} mac=${mac}; elif printenv eth_mac; then setenv bootargs ${bootargs} mac=${eth_mac}; fi'
setenv try_boot_start 'if fatload ${devtype} ${devnum} ${loadaddr} uImage; then if fatload ${devtype} ${devnum} ${initrd_addr} uInitrd; then fatload ${devtype} ${devnum} ${env_addr} uEnv.ini && env import -t ${env_addr} ${filesize} && run addmac; fatload ${devtype} ${devnum} ${dtb_mem_addr} ${dtb_name} && run boot_start; fi;fi'
setenv devtype mmc
setenv devnum 0
run try_boot_start
setenv devtype usb
for devnum in 0 1 2 3 ; do run try_boot_start ; done
EOF
)

uEnv=$(cat <<EOF
dtb_name=/$dtbfile_name
bootargs=$kernel_cmdline
EOF
)

mkgrubcfg=$(cat <<EOF
#!/bin.bash
if [[ -f /boot/grub/grub.cfg ]]; then
    mv /boot/grub/grub.cfg /boot/grub/grub.cfg.bak
fi
GRUB_DISTRIBUTOR="$distro_name $distro_edition" GRUB_CMDLINE_LINUX="$kernel_cmdline_opts" grub-mkconfig -o /boot/grub/grub.cfg
EOF
)

mk_grub_entry() {
    # Should be run in /boot
    kernel_version=$1
    kernel_name=vmlinuz-${kernel_version}
    initrd_name=initrd.img-${kernel_version}

    kernel_path=/boot/$kernel_name
    initrd_path=/boot/$initrd_name

    # Note: The leading tabs in the here-document below are important.
    cat <<-EOF >> grub/grub.cfg
	menuentry "$distro_name $distro_edition (kernel $kernel_version)" {
	
	linux  $kernel_path $kernel_cmdline
	initrd $initrd_path
	# devicetree /dtbs/amlogic/${dtbfile_name} # not used currently
	
	}
EOF
}

#----------------------------------- code -----------------------------------

if [[ $EUID -ne 0 ]]; then
    echo -e ${e_msg}" This script must be run as root, exiting."
    exit 1
fi

if [[ -z $(which systemd-nspawn) ]]; then
    echo -e ${e_msg}" The required command systemd-nspawn not found, exiting."
    exit 1
fi

imgfile_loc=${imgfile_dir}/${imgfile_name}
imgfile_MB=$((skip_MB +boot_MB +root_MB))
desired_MB=$((14*${imgfile_MB}/10)) # Approx. space for imgfile +imgfile.xz

echo -e "\n\033[92m -- Installing $distro_name ($distro_edition) -- \033[0m\n"

echo -e "The image container file will be at:"
echo $imgfile_loc

if [[ "$compressed_img" == "no" ]]; then
    required_MB=$imgfile_MB
else
    echo -e "\nThe finished (compressed) image file will be at:"
    echo ${imgfile_loc}.xz
    required_MB=$desired_MB
fi

echo -e "\nMake sure that you have enough space: ~${required_MB} MB +some.\n"
echo "This is what you have:"
df -h
echo -n -e "\nIs this enough? [N,y] "
read is_space_enough

if [[ "$is_space_enough" == "y" ]] ; then
    echo "OK, good, continuing."
else
    echo "OK, exiting."
    exit 1
fi

echo -n -e "\nGive a hostname for the new machine >"
read host_name

# Force setting up a local user (edit also ubuntu_custom_inst above).
# echo -n -e "\nEnter the user name of a local user (will be in adm,sudo groups) >"
# read user_name

echo -e "\n\033[92m -- Starting the installation -- \033[0m\n"

echo -n -e ${i_msg}" Making a directory for temporary files..."
mkdir -p $tmpfile_dir
echo " Done."

echo -e ${i_msg}" Setting up container file (${imgfile_MB} MB)..."
dd if=/dev/zero of=$imgfile_loc bs=1M count=$imgfile_MB \
   conv=fsync status=progress
sync
echo "Done."

echo -n -e ${i_msg}" Creating partitions in container file..."
parted -s $imgfile_loc mklabel msdos 2>/dev/null
parted -s $imgfile_loc mkpart primary fat32 \
       $((skip_MB))MiB $((skip_MB + boot_MB - 1))MiB 2>/dev/null
parted -s $imgfile_loc mkpart primary $rootfs_type \
       $((skip_MB + boot_MB))MiB 100% 2>/dev/null
sync
echo " Done."

echo -n -e ${i_msg}" Setting up loop device for container file..."
loop_dev=$(losetup -P -f --show ${imgfile_loc})
if [[ -z $loop_dev ]]; then
    echo -e "\n"${e_msg}" The command losetup $imgfile_loc failed, exiting."
    exit 1
fi
echo " Done."

echo -n -e ${i_msg}" Formatting the container file partitions..."
mkfs.vfat -n $bootfs_label ${loop_dev}p1 >/dev/null 2>&1
if [[ $rootfs_type == "btrfs" ]]; then
    mkfs.btrfs -f -U $rootfs_UUID -L $rootfs_label -m single ${loop_dev}p2 \
        >/dev/null 2>&1
else
    mkfs.ext4 -F -q -U $rootfs_UUID -L $rootfs_label -b 4k -m 0 ${loop_dev}p2 \
        >/dev/null 2>&1
fi
echo " Done."

echo -n -e ${i_msg}" Mounting the root partition inside the container file..."
mkdir -p $rootfs_mnt
if ! mount ${loop_dev}p2 $rootfs_mnt ; then
    echo -e ${e_msg}" The command mount ${loop_dev}p2 failed, exiting."
    exit 1
fi
sync
echo " Done."

echo -n -e ${i_msg}" Mounting the boot partition inside the container file..."
mkdir -p $bootfs_mnt
if ! mount ${loop_dev}p1 $bootfs_mnt ; then
    echo -e ${e_msg}" The command mount ${loop_dev}p1 failed, exiting."
    exit 1
fi
echo " Done."

echo -e ${i_msg}" Downloading the root (base) file system tarball..."
cd $tmpfile_dir && wget_exticode=$(wget $distro_buildurl)
if [[ $wget_exitcode -ne 0 ]]; then
    echo -e ${i_msg}" Unable to download the rootfs tarball, exiting"
    exit 1
fi
echo "Done."

echo -n -e ${i_msg}" Unpacking the root (base) file system tarball..."
cd $rootfs_mnt && tar -xf ${tmpfile_dir}/${distro_buildfile}
sync
echo " Done."

# The fstab file (0644) in the base tarball only holds a single comment line.
echo -n -e ${i_msg}" Setting up the fstab file..."
echo -e "$fstab_file" >${rootfs_mnt}/etc/fstab
# There is no UUID on a fat partition but in fstab the serial number works.
bootfs_UUID=$(blkid -s UUID -o value ${loop_dev}p1)
# Until we have figured out why this line in fstab stalls booting we comment it.
fstab_lastline="#UUID=${bootfs_UUID}  $bootfs_dir  vfat   defaults  0  2"
echo -e "$fstab_lastline" >>${rootfs_mnt}/etc/fstab
echo " Done."

# The hostname file (0644) in the base tarball reads localhost.localdomain.
echo -n -e ${i_msg}" Setting the hostname in /etc/hostname ..."
echo -e "$host_name" >${rootfs_mnt}/etc/hostname
echo " Done."

# The hosts file (0644) in the base tarball is empty.
echo -n -e ${i_msg}" Setting up local host mappings in /etc/hosts ..."
echo -e "$hosts_file" >${rootfs_mnt}/etc/hosts
echo " Done."

# The network directory does not exist in the base tarball.
echo -n -e ${i_msg}" Setting up net interfaces in /etc/network/interfaces ..."
mkdir -p -m 0755 ${rootfs_mnt}/etc/network
echo -e "$interfaces_file" >${rootfs_mnt}/etc/network/interfaces
echo " Done."

echo -e ${i_msg}" Downloading Ophub/Flippy/Unifreq kernel..."
cd $tmpfile_dir && wget_exticode=$(wget $kernel_urlboot)
if [[ $wget_exitcode -ne 0 ]]; then
    echo -e ${i_msg}" Unable to download the kernel boot files, exiting"
    exit 1
fi
wget_exticode=$(wget $kernel_urlmods)
if [[ $wget_exitcode -ne 0 ]]; then
    echo -e ${i_msg}" Unable to download the kernel modules, exiting"
    exit 1
fi
wget_exticode=$(wget $kernel_urldtbs)
if [[ $wget_exitcode -ne 0 ]]; then
    echo -e ${i_msg}" Unable to download the dtb files, exiting"
    exit 1
fi
echo " Done."

echo -n -e ${i_msg}" Installing Ophub/Flippy/Unifreq kernel..."
cd ${rootfs_mnt}/boot
tar -xzf ${tmpfile_dir}/boot-${kernel_release}.tar.gz
mkdir -p -m 0744 ${rootfs_mnt}/lib/modules
cd ${rootfs_mnt}/lib/modules
tar -xzf ${tmpfile_dir}/modules-${kernel_release}.tar.gz
mkdir -p -m 0755 ${rootfs_mnt}/boot/dtbs/amlogic
cd ${rootfs_mnt}/boot/dtbs/amlogic
tar -xzf ${tmpfile_dir}/dtb-amlogic-${kernel_release}.tar.gz
echo " Done."

# The flash-kernel package hangs installation on systems w/o flash storage.
# (Not needed when using ophub/flippy/unifreq's kernel but good to have.)
echo -n -e ${i_msg}" Preventing apt from installing the package flash-kernel..."
echo -e "$flashk_block_file" >\
	 ${rootfs_mnt}/etc/apt/preferences.d/no-flash-kernel
echo " Done."

echo -n -e ${i_msg}" Preparing for chroot jail..."
echo -e "$ubuntu_custom_inst" >${rootfs_mnt}/root/ubuntu_custom_inst.bash
chmod 0755 ${rootfs_mnt}/root/ubuntu_custom_inst.bash
echo " Done."

#echo -e ${i_msg}" Entering chroot jail. Installing kernel + some pkgs..."
echo -e ${i_msg}" Entering chroot jail. Installing/upgrading some packages..."
systemd-nspawn -q --resolv-conf=copy-host --timezone=off -D ${rootfs_mnt} \
	       /root/ubuntu_custom_inst.bash
rm ${rootfs_mnt}/root/ubuntu_custom_inst.bash
echo " Done."

# The resolv.conf file (0644) in the base tarball is empty.
echo -n -e ${i_msg}" Setting up /etc/resolv.conf ..."
rm -f ${rootfs_mnt}/etc/resolv.conf
echo -e "$resolver_file" >${rootfs_mnt}/etc/resolv.conf
echo " Done."

echo -n -e ${i_msg}" Setting up directory /boot/grub ..."
mkdir -p -m 0755 ${rootfs_mnt}/boot/grub
echo " Done."

echo -n -e ${i_msg}" Creating the file /boot/grub/grub.cfg ..."
cd ${rootfs_mnt}/boot
# Bare-hands minimal version of grub.cfg (loop in case we add several kernels).
for kernel_version in $(ls | grep -E "vmlinuz-" | cut -b 9-) ; do
    mk_grub_entry $kernel_version
done
echo " Done."

# echo -e ${i_msg}" This is the contents of the grub.cfg file:\n"
# cat ${rootfs_mnt}/boot/grub/grub.cfg
# echo " "

echo -e ${i_msg}" Installing script at /usr/local/bin/mkgrubcfg.bash ..."
cd ${rootfs_mnt}
echo -e "$mkgrubcfg" >usr/local/bin/mkgrubcfg.bash
chmod 0755 usr/local/bin/mkgrubcfg.bash
echo " Done."

echo -n -e ${i_msg}" Setting up script files and dtb on boot partition..."
cd ${bootfs_mnt}
touch aml_autoscript.zip
echo -e "$aml_autoscript" >aml_autoscript.txt
echo -e "$s905_autoscript" >s905_autoscript.txt
mkimage -A arm -O linux -T script -C none \
	-d aml_autoscript.txt aml_autoscript >/dev/null
mkimage -A arm -O linux -T script -C none \
	-d s905_autoscript.txt s905_autoscript >/dev/null
echo -e "$uEnv" >uEnv.ini
cp ${rootfs_mnt}/boot/dtbs/amlogic/${dtbfile_name} .
echo " Done."

echo -n -e ${i_msg}" Converting vmlinuz to u-boot format and copy uInitrd..."
# The vmlinuz kernels from ophub/flippy/unifreq are in fact in Image format.
mkimage -n "uImage" -A arm64 -O linux -T kernel -C none \
	-a 0x1080000 -e 0x1080000 \
	-d ${rootfs_mnt}/boot/vmlinuz-${kernel_release} \
	${bootfs_mnt}/uImage >/dev/null
cp ${rootfs_mnt}/boot/uInitrd-${kernel_release} ${bootfs_mnt}/uInitrd
echo " Done."

# For Ubuntu kernel +initramfs:
# echo -e ${i_msg}" Generating zImage and uInitrd on boot partition..."
# cp ${rootfs_mnt}/boot/vmlinuz ${bootfs_mnt}/zImage
# mkimage -n "ramdisk" -A arm64 -O linux -T ramdisk -C zstd \
# 	-d ${rootfs_mnt}/boot/initrd.img ${bootfs_mnt}/uInitrd 1>/dev/null
# echo " Done."
# Copy over dtb here also.

echo -n -e ${i_msg}" Unmounting the container file..."
cd $imgfile_dir
umount -f ${loop_dev}p1
sync && sleep 2
umount -f ${loop_dev}p2
sync && sleep 2
echo " Done."

echo -n -e ${i_msg}" Disconnecting and removing the loop devices..."
losetup -d $loop_dev 2>/dev/null 
echo " Done."


if [[ "$compressed_img" == "yes" ]]; then
    echo -e ${i_msg}" Compressing the image using xz compression..."
    xz -v $imgfile_loc
    echo "Done."
fi

echo -n -e ${i_msg}" Doing final cleanup of build area..."
if [[ "$docleanup_after" == "yes" ]]; then
    rm -rf $tmpfile_dir
    rmdir $rootfs_mnt
fi
echo " Done."

echo -e "\n\033[92m -- Finished -- \033[0m\n"
