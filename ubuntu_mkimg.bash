#!/bin/bash

# ubuntu_mkimg.bash (a.k.a. {opbuntu,flibuntu}_mkimg.bash)
# 22-09-21: v0.14
# Author: Tripole

# Script to generate an Ubuntu ARM64 (CLI, "server") image with a custom kernel
# (flippy-76) for Amlogic TV-boxes/SBCs. The Ubuntu infrastructure is based in
# daily builds of the rootfs of the latest LTS release (currently 22.04 Jammy).
# The script must be executed (as root) on an Ubuntu/Debian type machine,
# either natively on aarch64/ARM64 (e.g. Ubuntu Server Live booted via
# bootdisk) or virtualized on x86_64/amd64.
# The generated image can be booted using resident/vendor u-boot (using the
# boot scripts on the fat partition) or via bootdisk (using the grub.cfg file
# on the rootfs partition). (Another alternative is chainloader u-boot.ext)
# Tested on Ugoos AM6 plus (s922x, for booting and running) and on QEMU
# (qemu-system-x86_64 and qemu-system-aarch64, for developing/executing).
# This script is a template or proof-of-concept, nothing more (so please fork
# it, improve it).

# Requires: Standard basic functionality incl. blkid, dd, losetup, mkfs, xz,
# wget and the packages u-boot-tools, systemd-container (for systemd-nspawn)
# (most of the requirments are checked at runtime below). ArchLinux wiki:
# "systemd-nspawn is like the chroot command, but it is a chroot on steroids."
# For "cross-scripting" (i.e. usage on another architecture than aarch64) you
# need to install the package qemu-user-static (which recommends the package
# binfmt-support) which provides the required binary qemu-aarch64-static

# Typical usage: Edit the parameters below and run the script from a temp dir
# (the image as well as all temporary files will be created in this dir).

# Inspiration taken from
# https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/rebuild
# https://github.com/manjaro-arm/am6-plus-images/releases

# Notes:
# - The rootfs is installed in "minimized" state for many packages.
#   Therefore, it is advisable to run the command unminimize (and reboot) to
#   restore the system into normal state at the first boot.
# - In general, the installed system is "bare-bones", so e.g. no swap is set up.
# - On some boxes, when booting from USB using the boot scripts, only the image
#   stick can be attached to the USB bus. When booting using a chainloader
#   (u-boot.ext) it should not be a problem to have other non bootable USB
#   sticks attached. When booting using grub.cfg (e.g. using a  bootdisk on SD)
#   it is possible to have also other bootable USB sticks attached.
# - The uImage and uInitrd (u-boot tagged) versions of the kernel and initramfs
#   that are on the fat partition are created "once and for all" by the mkimage
#   command in the script below. Thus, when updating the kernel or initramfs
#   then also uImage and uInitrd have to be recreated manually (unless you rely
#   on grub booting e.g. via bootdisk, then only /boot/grub/grub.cfg on the
#   rootfs partition has to be updated; see scripts in /usr/local/bin).
# - Run time for the script is less than 10m on a modern computer with good
#   network connectivity.

# ------------------------------- parameters ---------------------------------

# Do not edit the next two, for now.
distro_name=Ubuntu
distro_edition=Jammy

distro_release="$(tr [A-Z] [a-z] <<< "$distro_edition")" # To lowercase.

# Official Ubuntu rootfs tarball.
distro_urlbase="https://cdimage.ubuntu.com/ubuntu-base"/${distro_release}
distro_relstr=daily/current
distro_buildfile=${distro_release}-base-arm64.tar.gz
distro_buildurl=${distro_urlbase}/${distro_relstr}/${distro_buildfile}

# Ophub repo w/ builds of Flippy/Unifreq kernels (incl. initramfs, thx. Ophub).
kernel_release="5.19.9-flippy-76+" # Name string with special characters.
kernel_urlboot="https://github.com/ophub/kernel/raw/main/pub/stable/5.19.9/boot-5.19.9-flippy-76%2B.tar.gz"
kernel_urlmods="https://github.com/ophub/kernel/raw/main/pub/stable/5.19.9/modules-5.19.9-flippy-76%2B.tar.gz"
kernel_urldtbs="https://github.com/ophub/kernel/raw/main/pub/stable/5.19.9/dtb-amlogic-5.19.9-flippy-76%2B.tar.gz"

# Ophub repo with u-boot.bin files (for use as chainloader u-boot.ext).
uboot_repo="https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/build-armbian/amlogic-u-boot/overload"

# Link to g12_sound.sh for enabling sound on some boxes (run as local user).
g12_sound_url="https://gitlab.manjaro.org/manjaro-arm/packages/community/oc4-post-install/-/raw/master/g12_sound.sh"

# Edit the tag to your liking.
img_tag=${kernel_release}_3pole-$(date +"%y%m%d")
imgfile_name=${distro_name}_${distro_edition}_${img_tag}.img

# Host name for image.
host_name=opbu

# The string root=UUID=${rootfs_UUID} will be prepended below once UUID exists.
kernel_cmdline_opts="rootdelay=3 rootflags=data=writeback rw console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 loglevel=1"

# This is the dtb file name pointed to in uEnv.ini
dtbfile_name=meson-g12b-ugoos-am6.dtb

# File system sizes and types (unit MiB).
# - The partition table type on the image is MBR.
# - The min skip (gap) size (before 1st part) is 1MB (2048 sectors, 512B each).
# - The boot fs type is vfat/fat32 and the root fs type is one of {ext4,btrfs}.
# Note: The boot fs is only for u-boot formatted copies of kernel +initramfs.
skip_MB=1
boot_MB=150
root_MB=3500
rootfs_type=ext4
bootfs_label=UBNT_BOOT
rootfs_label=UBNT_ROOT

# Compression (xz) takes some extra time.
compressed_img=no # {yes,no}

# Location (dir) of disk image container during install (for size, see below).
imgfile_dir=$PWD
tmpfile_dir=${imgfile_dir}/temp_files

# Temporary mount points (dirs) used during image creation.
rootfs_mnt=${imgfile_dir}/rootfs_tmp
bootfs_dir=/boot/aux
bootfs_mnt=${rootfs_mnt}/${bootfs_dir}

# These two are only (possibly) used on the installed image.
name_server_1=192.168.0.1 # Set to your router's IP address.
name_server_2=8.8.8.8     # Set to your backup DNS (8.8.8.8 is dns.google).

# Do we want to clean up all temporary files and directories afterwards?
docleanup_after=yes # {yes,no}

# Some (but not all) commands used below.
reqd_cmdlist=("blkid" "dd" "losetup" "mkfs.vfat" "mkfs.ext4" "mkfs.btrfs"
              "mkimage" "systemd-nspawn" "tar" "xz" "wget"
)

reqd_cmdlist_virt=("qemu-aarch64-static")

# u-boot.bins from Ophub's repo for use as chainloader (u-boot.ext).
uboot_list=("u-boot-e900v22c.bin" "u-boot-gtking.bin"
    "u-boot-gtkingpro-rev-a.bin" "u-boot-gtkingpro.bin" "u-boot-n1.bin"
    "u-boot-odroid-n2.bin" "u-boot-p201.bin" "u-boot-p212.bin"
    "u-boot-s905.bin" "u-boot-s905x-s912.bin" "u-boot-s905x2-s922.bin"
    "u-boot-sei510.bin" "u-boot-sei610.bin" "u-boot-tx3-bz.bin"
    "u-boot-tx3-qz.bin" "u-boot-u200.bin" "u-boot-ugoos-x3.bin"
    "u-boot-x96max.bin" "u-boot-x96maxplus.bin" "u-boot-zyxq.bin"
)

# Bling? Yes, we like.
i_msg="[\033[94m Info \033[0m]"
w_msg="[\033[93m Warning \033[0m]"
e_msg="[\033[91m Error \033[0m]"
k_msg="[\033[92m OK \033[0m]"

# --------------------------- preparations/checks ----------------------------

if [[ $EUID -ne 0 ]]; then
    echo -e ${e_msg}" This script must be run as root, exiting."
    exit 1
fi

arch_str=$(uname -m)
if [[ "$arch_str" != "aarch64" && "$arch_str" != "x86_64" ]]; then
    echo ${e_msg}" The architecture is not one of x86_64 or aarch64, exiting."
    exit 1
fi

have_all_cmds=yes
if [[ "$arch_str" == "aarch64" ]]; then
  chk_cmdlist=${reqd_cmdlist[*]}
else
  chk_cmdlist=(${reqd_cmdlist[*]} ${reqd_cmdlist_virt[*]})
fi
for chk_cmd in ${chk_cmdlist[*]}; do
    cmd_loc=$(which $chk_cmd)
    if [[ -z $cmd_loc ]]; then
        echo -e "The required command $chk_cmd is \033[91mmissing \033[0m"
	have_all_cmds=no
    fi
done
if [[ "$have_all_cmds" == "no" ]]; then
    echo -e ${e_msg}" Some required commands are missing, exiting."
    exit 1
fi

# UUIDs can also be generated with the cmd uuidgen from the pkg uuid-runtime.
rootfs_UUID=$(cat /proc/sys/kernel/random/uuid)
eth0nm_UUID=$(cat /proc/sys/kernel/random/uuid)
if [[ -z $rootfs_UUID || -z $eth0nm_UUID ]]; then
    echo ${e_msg}" Cannot generate valid UUIDs from kernel random source, exiting."
    exit 1
fi

# Full kernel command line.
kernel_cmdline="root=UUID=${rootfs_UUID} "${kernel_cmdline_opts}

# ------------------------------- here-docs ----------------------------------

# Below we add also a line for the vfat boot partition.
fstab_file=$(cat <<EOF
UUID=$rootfs_UUID  /  $rootfs_type   errors=remount-ro  0  1
EOF
)

# The interfaces and resolv.conf files are only needed if you choose to install
# the package ifupdown instead of the default networkmanager package.
# interfaces_file=$(cat <<EOF
# allow-hotplug eth0
# auto eth0
# iface eth0 inet dhcp
# EOF
# )
#
# resolver_file=$(cat <<EOF
# nameserver $name_server_1
# nameserver $name_server_2
# EOF
# )

# This conf file may need some tweaking, currently it provides only basic conn.
eth0_nmconf_file=$(cat <<EOF
[connection]
id=Wired connection 1
uuid=$eth0nm_UUID
type=ethernet
interface-name=eth0

[ethernet]

[ipv4]
method=auto

[ipv6]
addr-gen-mode=stable-privacy
method=auto

[proxy]
EOF
)

# This may be useful, see https://jbit.net/NetworkManager_Strictly_Unmanaged
alloweth_nmconf_file=$(cat <<EOF
[keyfile]
unmanaged-devices=*,except:type:wifi,except:type:gsm,except:type:cdma,except:type:ethernet
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

# In case we later want to install e.g. linux-image-generic (see comment below).
flashk_block_file=$(cat <<EOF
Package: flash-kernel
Pin: release *
Pin-Priority: -1
EOF
)

# If you want to add packages (to the default below), this is where to do it.
# To add the generic (ARM64) kernel add: apt -y install linux-image-generic
# (The double quotes around the limit string EOF prevents command substitution.)
ubuntu_custom_extra=$(cat <<"EOF"
apt-get -y install nano less aptitude
EOF
)

# This is the basic (default) set of packages installed on top of the rootfs.
# (If you want to add packages, edit the here-doc ubuntu_custom_extra above.)
ubuntu_custom_inst=$(cat <<EOF
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y install man-db apt-utils kmod grub2-common network-manager ssh
DEBIAN_FRONTEND=noninteractive apt-get -y install dialog locales keyboard-configuration kbd
dpkg-reconfigure tzdata
dpkg-reconfigure keyboard-configuration
echo "Set password for \033[91mroot:\033[0m"
until passwd; do echo "Try again."; done
echo "Setting up grub.cfg"
mkgrubcfg_simple.bash
$ubuntu_custom_extra
EOF
)

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

extlinux_conf=$(cat <<EOF
# This file is only to be used if resident/vendor u-boot cannot boot via boot
# scripts (aml_autoscript, s905_autoscript and uEnv.ini) and you still want
# to use u-boot foor booting (rather than e.g. bootdisk +grub.cfg). Usage:
# (1) Rename the file to extlinux.conf
# (2) Edit the text below (if needed) to match your box and add a chainloader
#     as u-boot.ext (see e.g. https://github.com/ophub/amlogic-s9xxx-armbian).

MENU TITLE <UBUNTU-BOOT>
DEFAULT <UBNT_DEFAULT>

LABEL UBNT_DEFAULT
  LINUX  /uImage
  INITRD /uInitrd
  FDT    /$dtbfile_name
  APPEND $kernel_cmdline
EOF
)

README_uboot=$(cat <<EOF
The files in this directory are intended to be used as chainloader when booting
via this method. (The default boot methods are grub.cfg and boot script.)
Usage: Find a binary here (u-boot-*) which matches your box and copy it to the
name u-boot.ext at the top level on the boot (fat) partition. Then edit the
file extlinux/extlinux.conf.bak according to the instructions inside that file.
EOF
)

mkgrubcfg=$(cat <<EOF
#!/bin/bash

GRUB_DISTRIBUTOR="$distro_name $distro_edition"
GRUB_CMDLINE_LINUX="$kernel_cmdline_opts"

if [[ -f /boot/grub/grub.cfg ]]; then
    mv /boot/grub/grub.cfg /boot/grub/grub.cfg.bak
fi

grub-mkconfig -o /boot/grub/grub.cfg
EOF
)

mkgrubcfg_simple_p1=$(cat <<EOF
#!/bin/bash

distro_name_=$distro_name
distro_edition_=$distro_edition
kernel_cmdline_="$kernel_cmdline"
dtbfile_name_=$dtbfile_name

EOF
)

mkgrubcfg_simple_p2=$(cat <<"EOF1"

cd /boot

for kernel_version in $(ls | grep -E "vmlinuz-" | cut -b 9-) ; do
    kernel_name=vmlinuz-${kernel_version}
    initrd_name=initrd.img-${kernel_version}

    kernel_path=/boot/$kernel_name
    initrd_path=/boot/$initrd_name
    echo "Adding entry $distro_name_ $distro_edition_ (kernel $kernel_version)"
    # Note: The leading tabs in the here-document below are important.
	cat <<-EOF >> grub/grub.cfg
	menuentry "$distro_name_ $distro_edition_ (kernel $kernel_version)" {
	
	linux  $kernel_path $kernel_cmdline_
	initrd $initrd_path
	# devicetree /dtbs/amlogic/${dtbfile_name_} # not used currently
	
	}
	EOF
done
EOF1
)

mkgrubcfg_simple="${mkgrubcfg_simple_p1}""${mkgrubcfg_simple_p2}"

#----------------------------------- code -----------------------------------

imgfile_loc=${imgfile_dir}/${imgfile_name}

# This is a rough estimate: We do not take into account temp files etc.
imgfile_MB=$((skip_MB +boot_MB +root_MB))
desired_MB=$((14*${imgfile_MB}/10)) # Approx. space for imgfile +imgfile.xz

echo -e "\n\033[92m -- Making image for $distro_name ($distro_edition) -- \033[0m\n"

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

# The interfaces and resolv.conf files are only needed if you choose to install
# the package ifupdown instead of the default network manager package.
#
# # The network directory (0755) does not exist in the base tarball.
# echo -n -e ${i_msg}" Setting up net interfaces in /etc/network/interfaces ..."
# mkdir -p -m 0755 ${rootfs_mnt}/etc/network
# echo -e "$interfaces_file" >${rootfs_mnt}/etc/network/interfaces
# echo " Done."
#
# # The resolv.conf file (0644) in the base tarball is empty.
# echo -n -e ${i_msg}" Setting up /etc/resolv.conf ..."
# rm -f ${rootfs_mnt}/etc/resolv.conf
# echo -e "$resolver_file" >${rootfs_mnt}/etc/resolv.conf
# echo " Done."

# To enable sound on some boxes, edit and run this script as local user.
echo -e ${i_msg}" Installing script at /usr/local/bin/g12_sound.sh ..."
cd $tmpfile_dir && wget_exticode=$(wget $g12_sound_url)
if [[ $wget_exitcode -ne 0 ]]; then
    echo -e ${w_msg}" Unable to download the scrip g12_sound.sh"
else
    cp g12_sound.sh ${rootfs_mnt}/usr/local/bin
    chmod 0755 ${rootfs_mnt}/usr/local/bin/g12_sound.sh
fi
echo "Done."

echo -n -e ${i_msg}" Setting up directory /boot/grub ..."
mkdir -p -m 0755 ${rootfs_mnt}/boot/grub
echo " Done."

echo -n -e ${i_msg}" Installing grub scripts in /usr/local/bin ..."
# This script uses grub-mkconfig but it doesn't work inside a loop device.
# (It is installed for later use, to produce fancier grub menus.)
echo -e "$mkgrubcfg" >${rootfs_mnt}/usr/local/bin/mkgrubcfg.bash
chmod 0755 ${rootfs_mnt}/usr/local/bin/mkgrubcfg.bash
# This script produces a basic grub.cfg file and works inside a loop device.
echo -e "$mkgrubcfg_simple" >${rootfs_mnt}/usr/local/bin/mkgrubcfg_simple.bash
chmod 0755 ${rootfs_mnt}/usr/local/bin/mkgrubcfg_simple.bash
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

# The flash-kernel package causes problems on systems w/o flash storage (when
# installing Ubuntu kernels) so it is good to block to aviod future problems.
echo -n -e ${i_msg}" Preventing apt from installing the package flash-kernel..."
echo -e "$flashk_block_file" >\
	 ${rootfs_mnt}/etc/apt/preferences.d/no-flash-kernel
echo " Done."

echo -n -e ${i_msg}" Preparing for chroot jail..."
echo -e "$ubuntu_custom_inst" >${rootfs_mnt}/root/ubuntu_custom_inst.bash
chmod 0755 ${rootfs_mnt}/root/ubuntu_custom_inst.bash
echo " Done."

if [[ $arch_str != "aarch64" ]]; then
    echo -n -e ${i_msg}" Installing local qemu-aarch64-static binary..."
    qemu_binary_loc=$(which qemu-aarch64-static)
    cp $qemu_binary_loc ${rootfs_mnt}/usr/bin
    echo " Done."
fi

echo -e ${i_msg}" Entering chroot jail. Installing/upgrading some packages..."
systemd-nspawn -q --resolv-conf=copy-host --timezone=off -D ${rootfs_mnt} \
	       /root/ubuntu_custom_inst.bash
rm ${rootfs_mnt}/root/ubuntu_custom_inst.bash
sleep 1 # Just to be able to read some of the messages.
echo "Done."

if [[ $arch_str != "aarch64" ]]; then
    echo -e ${i_msg}" Removing local qemu-aarch64-static binary..."
    rm ${rootfs_mnt}/usr/bin/qemu-aarch64-static
    echo " Done."
fi

echo -n -e ${i_msg}" Installing Network Manager configuration files for eth0 ..."
nm_conf_dir=${rootfs_mnt}/etc/NetworkManager
eth0_nmconf_name=Wired_connection_1.nmconnection
eth0_nmconf_loc=${nm_conf_dir}/system-connections/${eth0_nmconf_name}
echo -e "$eth0_nmconf_file"> $eth0_nmconf_loc
chmod 0600 $eth0_nmconf_loc
alloweth_nmconf_name=allow-ethernet.conf
alloweth_nmconf_loc=${nm_conf_dir}/conf.d/${alloweth_nmconf_name}
echo -e "$alloweth_nmconf_file" >$alloweth_nmconf_loc
chmod 0644 $alloweth_nmconf_loc
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

# Only as a backup, in case vendor u-boot cannot boot via bootscripts.
echo -e ${i_msg}" Setting up backup boot method (chainloader)..."
mkdir extlinux
echo -e "$extlinux_conf" >extlinux/extlinux.conf.bak
mkdir u-boot
echo -e "$README_uboot" >u-boot/README_u-boot.txt
for uboot_bin in ${uboot_list[*]}; do
    uboot_bin_url=${uboot_repo}/${uboot_bin}
    wget_exticode=$(wget -nv -P u-boot $uboot_bin_url)
    if [[ $wget_exitcode -ne 0 ]]; then
        echo -e ${w_msg}" Unable to download $uboot_bin"
    fi
done
echo "Done."

# The vmlinuz kernels from ophub/flippy/unifreq are in fact in Image format.
echo -n -e ${i_msg}" Converting vmlinuz to u-boot format and copy uInitrd..."
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
#       -d ${rootfs_mnt}/boot/initrd.img ${bootfs_mnt}/uInitrd 1>/dev/null
# echo " Done."

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

if [[ "$docleanup_after" == "yes" ]]; then
    echo -n -e ${i_msg}" Doing final cleanup of build area..."
    rm -rf $tmpfile_dir
    rmdir $rootfs_mnt
    echo " Done."    
fi

echo -e "\n\033[92m -- Finished -- \033[0m\n"
