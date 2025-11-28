#!/bin/bash

# devuan_dbstrap.bash
# 23-07-16: v0.1
# Author: Tripole

# This is a script to create a Devuan Linux ARM64 (CLI, "server") image for
# Amlogic TV-boxes/SBCs. The base system is obtained using the debootstrap
# mechanism to access the Devuan repositories and install the packages.
# The script must be executed (as root) on an Ubuntu/Debian type machine,
# either natively on aarch64/ARM64 or virtualized (using qemu-aarch64-static)
# on x86_64/amd64.  The generated image can be booted with resident/vendor
# u-boot (using the boot scripts on the fat partition) or via bootdisk (using
# the grub.cfg file on the rootfs partition). Another alternative is
# chainloader u-boot.ext (included).

# Usage: ./devuan_dbstrap

# Tested on: Ugoos AM6 plus (s922x, for booting and running) and on QEMU
# (qemu-system-x86_64 and qemu-system-aarch64, for developing/executing).

# Requires: Standard basic functionality incl. blkid, dd, losetup, mkfs, xz,
# wget and the package systemd-container (for systemd-nspawn). ArchLinux wiki:
# "systemd-nspawn is like the chroot command, but it is a chroot on steroids."
# Most of the requirements are checked at runtime below. For "cross-scripting"
# (i.e. use on another architecture than aarch64) you need to install the
# package qemu-user-static (which recommends the package binfmt-support); this
# provides the required binary qemu-aarch64-static

# Typical usage: Edit the parameters below and run the script from a temp dir.
# (the image as well as all temporary files will be created in this dir.).
# (If the file specified by $uboot_ext_local is in this dir, it will be used as
# u-boot.ext but there are also several u-boot.bins from Ophub installed that
# may be used if booting is done via chainloading u-boot.ext)

# This script is heavily inspired by the script debuntu_dbstrap.bash at my
# Gitlab bootdisk repo (and that script is in turn inspired by some others).

# Notes:
# - Requires the latest Devuan keyring to be installed on the host machine.
#   https://pkgmaster.devuan.org/devuan/pool/main/d/devuan-keyring/
# - The installed system is "bare-bones"; e.g. no swap is set (only zram).
# - During installation, on some terminals the keyboard and console font
#   configuration will be deferred and you will see a message about this.
#   (You can always later manually do dpkg-reconfigure keyboard-configuration)
# - The image can always be booted via grub (e.g. using bootdisk) and most
#   often via (a recent) chainloader (uboot.ext, using extlinux/extlinux.conf
#   on the bootfs). However, it may not boot via resident/vendor u-boot
#   (loading uImage and uInitrd via boot scripts), unless the vendor u-boot is
#   recent. (One reason for this is that the standard initramfs compression
#   method (in /etc/initramfs-tools/initramfs.conf) is zstd, but older u-boot
#   (pre 2020) can only do gzip. A second reason is that some (old) u-boot
#   don't (even) support gzip compressed kernels (which is a little bit more
#   cumbersome to fix).
# - The kernel and initramfs files on the bootfs are not automatically updated
#   when the kernel is upgraded or the initramfs is rebuilt on the rootfs.
#   Therefore, if you are booting using u-boot and bootfs (e.g. w/ u-boot.ext),
#   then when upgrading the kernel or rebuilding the initramfs these components
#   have to be copied manually over to the bootfs (which is typically mounted
#   under /boot/aux on the rootfs).
#   If you are booting via grub.cfg on rootfs (e.g. using bootdisk) you only
#   need to update grub.cfg and this cane can be done by using grub-mkimage or
#   via scripts in /usr/local/bin e.g. mkgrubcfg_simple.bash
# - The dtb file is not specified in the grub.cfg file upon installation but
#   the script mkgrubcfg_simple.bash can be run post-install to include a dtb
#   specification in grub.cfg. However, bootloaders based on kexec, such as
#   Petitboot/u-root, typically let the booted Linux image inherit the dtb used
#   by the bootloader, cf. the README at Gitlab files about Petitboot/u-root.
# - A full working desktop can be obtained by installing e.g.
#   task-xfce-desktop, task-kde-desktop etc. (conveniently via e.g. aptitude).
#   (With a desktop install it is convenient to let NetworkManager handle the
#   network connections and to do this rename the file /etc/network/interfaces)
# - The package linux-firmware is installed but firmware for e.g. a specific
#   WiFi or Bluethooth chip might not be included and thus have to be sought
#   elsewhere.
# - On some boxes it is necessary to run (as user) the script g12_sound.sh to
#   get sound working. (Afterwards, check for soundcards with e.g. aplay -L)
# - Run time for this script is about 25m (incl. compression, on a modern
#   computer with good network connectivity). Check: time ./devuan_dbstrap.bash
# - You will be asked to configure three things at runtime (near the end):
#   time zone, keyboard and root password.
# - Basic configuration: You might want to configure zram (and optionally set
#   up swap), see e.g. /etc/default/zramswap and https://wiki.debian.org/ZRam
# - Pro tip: Generate the image cheaply, say 2G rootfs (so that burn to SD/USB
#   goes quickly). Then, (before first boot) enlarge the rootfs partition on
#   SD/USB to desired size, e.g. with (100% here uses all of the SD/USB):
#   parted /dev/sdX resizepart 2 50% ; e2fsck -f /dev/sdX2 ; resize2fs /dev/sdX2
#   Finally, to make sure that the resized partition will be recognized also as
#   a valid GPT partition, repair it with gdisk as follows. First, start gdisk;
#   gdisk /dev/sdX
#   and gdisk may tell you that it has found a valid MBR and a corrupt GPT,
#   and it will then ask you which one to use. You should chose to use the MBR.
#   At the gdisk prompt then enter the command "r" and you will be taken to the
#   recovery and transformation options. There, enter the command "f" to load
#   the MBR and build a fresh GPT from it. At last, exit gdisk with "w" (write).

# ToDo: Fix network setup (in particular the resolver setup) using sec 2.1 in
# https://wiki.archlinux.org/title/Systemd-resolved (it is applicable here too).

# ------------------------------- parameters ---------------------------------

distro_name=Devuan      # Used for the image name and in grub.cfg
distro_edition=Daedalus # Tested with Chimaera (Bullseye), Daedalus (Bookworm)

# Host name for image.
host_name=devu

# Compression (xz) takes some extra time.
compressed_img=yes # {yes,no}

# Location Devuan specific debootstrap scripts.
devuan_dbscripts_url="https://pkgmaster.devuan.org/devuan/pool/main/d/debootstrap"
# Current Devuan tarball with debootstrap scripts.
devuan_dbscripts_tgz="debootstrap_1.0.123+devuan5.tar.gz"

# debootstrap repo for packages. (A mirror can also be used.)
distro_repourl="http://deb.devuan.org/merged"

# Edit the image tag to your liking.
img_tag=3pole-$(date +"%y%m%d")

# Ophub repo (dir.) with u-boot.bin files (for use as chainloader u-boot.ext).
ophub_repo_url="https://github.com/ophub"
ophub_uboot_url=${ophub_repo_url}"/u-boot/blob/main/u-boot/amlogic/overload"

# u-boot.bins from Ophub's repo for use as chainloader (u-boot.ext).
# Note: Some of these may not be able to boot newer Ubuntu kernels or initramfs
# since they do not have support for decompression is zstd compressed files.
# (Such support is missing e.g. in u-boot-s905.bin, u-boot-s905x-s912.bin and
# u-boot-s905x2-s922.bin but seems to be present in the others.)
uboot_list=(
    "u-boot-e900v22c.bin" "u-boot-gtking.bin" "u-boot-gtkingpro-rev-a.bin"
    "u-boot-gtkingpro.bin" "u-boot-n1.bin" "u-boot-odroid-n2.bin"
    "u-boot-p201.bin" "u-boot-p212.bin" "u-boot-r3300l.bin" "u-boot-s905.bin"
    "u-boot-s905x-s905lb.bin" "u-boot-s905x-s912.bin" "u-boot-s905x2-s922.bin"
    "u-boot-s905x3.bin" "u-boot-sei510.bin" "u-boot-sei610.bin"
    "u-boot-skyworth-lb2004.bin" "u-boot-tx3-bz.bin" "u-boot-tx3-qz.bin"
    "u-boot-u200.bin" "u-boot-ugoos-x3.bin" "u-boot-x96max.bin"
    "u-boot-x96maxplus.bin" "u-boot-zyxq.bin"
)

# If the file $uboot_ext_local exists in $imgfile_dir (see below) then it will
# be installed on the image as the default u-boot.ext on the bootfs.
# uboot_ext_local=u-boot.bin-gtkp-pb
# uboot_ext_local_bldtag=u-boot-amlogic-20220809
uboot_ext_local=u-boot.bin-gtkp-pb-1s-ctrlc
uboot_ext_local_bldtag=u-boot-amlogic-v2023.10
uboot_ext_local_url="https://mega.nz/folder/bIdjwI6B#mojtTtZPufsHD9v7gTkjdQ"

# Link to g12_sound.sh for enabling sound on some boxes (run as local user).
g12_sound_url="https://gitlab.manjaro.org/manjaro-arm/packages/community/oc4-post-install/-/raw/master/g12_sound.sh"

# The string root=UUID=${rootfs_UUID} will be prepended below once UUID exists.
kernel_cmdline_opts="ro quiet"

# The dtb file name used in extlinux.conf (and uEnv.ini.bak).
# (dtb must be in local /usr/lib/firmware/{kernel-version}/device-tree/amlogic).
dtbfile_name=meson-g12b-gtking-pro.dtb

# File system sizes and types (unit MiB).
# - The partition table type on the image is MBR.
# - The min skip (gap) size (before 1st part) is 1MB (2048 sectors, 512B each).
# - The boot fs type is vfat/fat32 and the root fs type is one of {ext4,btrfs}.
# Note: The boot fs is only for u-boot formatted copies of kernel +initramfs.
gap_MiB=16
boot_MiB=500
root_MiB=6000
rootfs_type=ext4

# Location (dir) of disk image container during install (for size, see below).
imgfile_dir=$PWD
tmpfile_dir=${imgfile_dir}/temp_files

# Mount point for the debootstrap process.
# Temporary mount points (dirs) used during image creation.
rootfs_mnt=${imgfile_dir}/rootfs_tmp
bootfs_dir=/boot/aux
bootfs_mnt=${rootfs_mnt}/${bootfs_dir}

# Fils system labels.
bootfs_label=DEVU_BOOT
rootfs_label=DEVU_ROOT

# Do we want to clean up all temporary files and directories afterwards?
docleanup_after=yes # {yes,no}

# Basic network settings.
name_server_1=192.168.0.1 # Set to your router's IP address.
name_server_2=8.8.8.8     # Set to your backup DNS (8.8.8.8 is dns.google).

# Some (but not all) commands used below to create the image.
reqd_cmdlist=("blkid" "dd" "debootstrap" "losetup" "mkfs.vfat" "mkimage" 
              "systemd-nspawn" "tar" "wget" "xz"
)

reqd_cmdlist_virt=("qemu-aarch64-static")

# Keyring file for the Devuan archive(s). (Must be instlled on host, see above.)
keyring_file=/usr/share/keyrings/devuan-archive-keyring.gpg

# Bling? Yes, we like.
i_msg="[\033[94m Info \033[0m]"
w_msg="[\033[93m Warning \033[0m]"
e_msg="[\033[91m Error \033[0m]"
k_msg="[\033[92m OK \033[0m]"

# --------------------------- preparations/checks ----------------------------

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root, exiting."
    exit 1
fi

hostos_name=$(cat /etc/os-release | grep -E '^NAME' | cut -d '=' -f 2 | tr -d \")
if [[ "$hostos_name" != "Ubuntu" ]]; then
    echo "This script must be executed on Ubuntu Linux, exiting."
    exit 1
fi

# Apparently, these Debianisms are not adopted by Devuan.
# if [[ "$devuan_edition" == "Chimaera" ]] ; then
#     nonfree_list="non-free"
#     iface_name="eth0"
# else
#     nonfree_list="non-free non-free-firmware"
#     iface_name="end0"
# fi

iface_name="eth0"

# This is the name used on the container file during image creation.
# Before exit of this script, the kernel version is inserted into the name.
imgfile_name=${distro_name}_${distro_edition}_${img_tag}.img

# For the debootstrapping.
distro_release="$(tr [A-Z] [a-z] <<< "$distro_edition")" # To lowercase.

arch_str=$(uname -m)
if [[ "$arch_str" != "aarch64" && "$arch_str" != "x86_64" ]]; then
    echo ${e_msg}" The architecture is not one of x86_64 or aarch64, exiting."
    exit 1
fi

# The devuan-keyring package contains also the keys for the archives/repos.
devu_keyring_isinst=$(dpkg -l | awk '/devuan-keyring/ {print }' | wc -l)
if [[ $devu_keyring_isinst -eq 0 ]]; then
    echo 
fi

if [[ "$rootfs_type" == "ext4" ]]; then
    reqd_cmdlist=("${reqd_cmdlist[@]}" "mkfs.ext4")
elif [[ "$rootfs_type" == "btrfs" ]]; then
    reqd_cmdlist=("${reqd_cmdlist[@]}" "mkfs.btrfs")
else
    echo -e "The fstype for the rootfs must be one of ext4 or btrfs, exiting."
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
# (For swap we only add a stub, see https://help.ubuntu.com/community/SwapFaq)
fstab_file=$(cat <<EOF
UUID=$rootfs_UUID  /  $rootfs_type   errors=remount-ro  0  1
#/swapfile        none  swap        defaults  0  0
EOF
)

devuan_interfaces_file=$(cat <<EOF
allow-hotplug $iface_name
auto $iface_name
iface $iface_name inet dhcp
EOF
)

devuan_resolver_file=$(cat <<EOF
nameserver $name_server_1
nameserver $name_server_2
EOF
)

devuan_repo_list=$(cat <<EOF
deb http://deb.devuan.org/merged $distro_release main contrib $nonfree_list
deb http://deb.devuan.org/merged ${distro_release}-security main contrib $nonfree_list
deb http://deb.devuan.org/merged ${distro_release}-updates main contrib $nonfree_list
# deb http://deb.devuan.org/merged ${distro_release}-backports main contrib $nonfree_list
EOF
)

devuan_custom_extra=$(cat <<"EOF"
apt-get -y install aptitude usbutils zram-tools
EOF
)

devuan_custom_inst=$(cat <<EOF
#!/bin/bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt -y install linux-image-arm64
# DEBIAN_FRONTEND=noninteractive apt -y install linux-headers-arm64
DEBIAN_FRONTEND=noninteractive apt -y install locales ntp sudo u-boot-tools
DEBIAN_FRONTEND=noninteractive $devuan_custom_extra
dpkg-reconfigure tzdata
apt -y install console-setup

echo "Set password for \033[91mroot:\033[0m"
until passwd; do echo "Try again."; done

echo "Creating /boot/grub/grub.cfg"
rootfsUUID=$rootfs_UUID bash -c '/usr/local/bin/mkgrubcfg_simple.bash'
EOF
)

aml_autoscript=$(cat <<"EOF"
# Standard aml_autoscript to set boot order: mmc/SD, USB, emmc
# Search for *_autoscript on these device types and execute the first such script found.
# Sourced from Manjaro ARM.
# Recompile with mkimage -A arm -O linux -T script -C none -d aml_autoscript.txt aml_autoscript
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
# Standard s905_autoscript to set boot execution steps (for mmc/SD and USB).
# Sourced from Manjaro ARM.
# Recompile with mkimage -A arm -O linux -T script -C none -d s905_autoscript.txt s905_autoscript
# (1) Try chainloader u-boot.ext, typically with boot conf. in extlinux.conf
if fatload mmc 0 0x1000000 u-boot.ext; then go 0x1000000; fi;
if fatload usb 0 0x1000000 u-boot.ext; then go 0x1000000; fi;
# (2) If no chainloader found, continue using vendor u-boot:
# Search fat partitions (on mmc/SD and then USB) and look for uImage, uInitrd and boot conf. in uEnv.ini, and execute the first such combo found.
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
# This file defines the boot config. when using e.g. chainloader u-boot.ext
# Multiple entries can be added. Many chainloaders accept keyboard input just
# after the menu items below are presented on screen (you have to be fast) and
# you can then enter the number of the boot entry you wish to boot.

# For more info about this file see (and the links therein)
# https://wiki.syslinux.org/wiki/index.php?title=SYSLINUX
# (Note: u-boot's parsing of this file may be slightly different/incomplete.)

MENU TITLE <DEVUAN-BOOT>
DEFAULT DEVUAN_DEFAULT

# Timeout is in units of 0.1s (to wait before boot of default entry below).
TIMEOUT 10

LABEL DEVUAN_DEFAULT
  LINUX  /vmlinuz
  INITRD /initrd.img
  FDT    /$dtbfile_name
  APPEND $kernel_cmdline
EOF
)

README_uboot_ophub=$(cat <<EOF
The files in this directory are from $ophub_uboot_url
They are intended to be used as chainloader (u-boot.ext) when booting via this
method.
Usage: Find a binary here (u-boot-*) which matches your box and copy it to the
name u-boot.ext at the top level on the boot (fat) partition. Then edit the
file extlinux/extlinux.conf according to the instructions inside that file.

Note that some chainloaders can not boot newer kernels/initrfamfs.
EOF
)

README_uboot_aml=$(cat <<EOF
The file $uboot_ext_local is compiled from source using
https://source.denx.de/u-boot/custodians/u-boot-amlogic
using the tag $uboot_ext_local_bldtag
with gtk pro defconf and usb_start added as preboot command.
For more info about $uboot_ext_local and downloads of similar files see
$uboot_ext_local_url
EOF
)

README_kernels=$(cat <<"EOF"
The scripts in /usr/local/bin can be used to assist in kernel handling.

For booting via grub (e.g. via bootdisk) the script mkgrubcfg_simple.bash can
be used to generate simple grub entries for vmlinuz- kernels and accompanying
initramfs.img- files residing in /boot (see instructions inside the script).

Alternate kernels that work with TV-boxes and are packaged as deb files can be
found via https://apt.armbian.com
One mirror is https://mirrors.netix.net/armbian/apt/pool/main/l
The meson64 and arm64 (generic) kernels work well with s922x SOC.

Ophub's kernels can be installed manually and come with pre built initramfs
https://github.com/ophub/amlogic-s9xxx-armbian
and so do the kernels built by Tripole
https://gitlab.com/tripole-inc/bootdisk
EOF
)

mkgrubcfg=$(cat <<EOF
#!/bin/bash

# Wrapper around grub-mkconfig with /boot/grub as destination directory.
# Tailored to (i.e. command line arguments) for Debian/Ubuntu kernels.
# For other kernels, adapt the command line string below.
# Usage: /usr/local/bin/mkgrubcfg.bash

GRUB_DISTRIBUTOR="$distro_name $distro_edition"
GRUB_CMDLINE_LINUX="$kernel_cmdline_opts"

if [[ -f /boot/grub/grub.cfg ]]; then
    mv /boot/grub/grub.cfg /boot/grub/grub.cfg.bak
fi

grub-mkconfig -o /boot/grub/grub.cfg
EOF
)

# We split this file in two; one part with parameter substitution and one w/o.
mkgrubcfg_simple_p1=$(cat <<EOF
#!/bin/bash

# Scans for vmlinuz-* in /boot and makes a simple grub.cfg in /boot/grub
# Usage: /usr/local/bin/mkgrubcfg_simple.bash [path-to-dtb-file]
# If a dtb file is specified as the first argument, it is inserted together
# with a line specifying a devicetree line in each menu entry created. (The
# dtb name can be a symlink; the full dtb name will be inserted into grub.cfg)
# Normally, the script is run from a mounted rootfs and then the UUID of the
# rootfs is discovered using the blkid comand (see below). However, for use
# e.g. inside a chroot jail the rootfs UUID can also be given as an environment
# variable prepended on the command line, e.g. like so (note the single quotes):
# chroot . /bin/bash -c 'rootfsUUID=f3cab04c-...-faec36aace3f ; /usr/local/bin/mkgrubcfg_simple.bash [path-to-dtb-file]'

kernel_cmdline_pars_="$kernel_cmdline_opts"

EOF
)

mkgrubcfg_simple_p2=$(cat <<"EOF1"

distro_name_lc=$(cat /etc/os-release | grep -E "^ID=" | cut -d "=" -f2)
distro_edition_lc=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d "=" -f2)

# First letter to uppercase.
distro_name="$(tr '[:lower:]' '[:upper:]' <<< ${distro_name_lc:0:1})""${distro_name_lc:1}"
distro_edition="$(tr '[:lower:]' '[:upper:]' <<< ${distro_edition_lc:0:1})""${distro_edition_lc:1}"

if [[ -z "$rootfsUUID" ]]; then
    rootfs_uuid=$(blkid -s UUID $(mount | grep -E "/ " | cut -d " " -f 1) | cut -d "\"" -f2)
else
    rootfs_uuid=$rootfsUUID
fi
echo "Rootfs UUID: $rootfs_uuid"

# The next line is a default kernel command line and may have to be adjusted for each kernel.
kernel_cmdline_rootfsuuid="root=UUID="${rootfs_uuid}
kernel_cmdline=${kernel_cmdline_rootfsuuid}" "${kernel_cmdline_pars_}

devicetree_str="# devicetree /path/to/dtbfile # not used currently"
devicetree_msg="Devicetree:  No dtb file specified or dtb file missing."
if [[ "$#" -eq 1 ]]; then
    dtbfile_full=$(readlink -f $1)
    if [[ -f $dtbfile_full ]]; then
        devicetree_str="devicetree $dtbfile_full"
        devicetree_msg="Devicetree:  $dtbfile_full"
    fi
fi
echo $devicetree_msg

cd /boot

if [[ -f grub/grub.cfg ]]; then
    mv grub/grub.cfg grub/grub.cfg.bak
fi

for kernel_version in $(ls | grep -E "vmlinuz-" | cut -b 9-) ; do
    kernel_name=vmlinuz-${kernel_version}
    initrd_name=initrd.img-${kernel_version}

    kernel_path=/boot/$kernel_name
    initrd_path=/boot/$initrd_name
    echo "Adding menu entry: $distro_name $distro_edition (kernel $kernel_version)"
    # Note: The leading tabs in the here-document below are important.
	cat <<-EOF >> grub/grub.cfg
	menuentry "$distro_name $distro_edition (kernel $kernel_version)" {
	
	linux  $kernel_path $kernel_cmdline
	initrd $initrd_path
	$devicetree_str
	
	}
	
	EOF
done
EOF1
)

mkgrubcfg_simple="${mkgrubcfg_simple_p1}""${mkgrubcfg_simple_p2}"

README_auxbootldr=$(cat <<"EOF"
Petitboot and u-root
--------------------

It is easy to install the bootmanager/bootloader Petitboot or u-root onto this
bootfs and use the bootloader/bootmanager as a middle stage in the booting
process. With such an installation it is possible to have multiple kernels
installed to choose from at the bootmanager prompt. It is also possible to boot
kernels (and Linux OSes) installed on other attached removable media.
For more info on such "bootdisk" booting, see
https://gitlab.com/tripole-inc/bootdisk

Hidden bootloader
-----------------

To boot this disk image with u-boot requires a working resident/vendor u-boot
bootloader but this restriction can be removed if a "hidden" bootloader, i.e.
u-boot, is installed in the "gap" leading up to the first partition. With such
a hidden bootloader properly installed, the disk will always boot from SD or
USB on Amlogic devices, regardless of the state of the resident/vendor u-boot.
More inforomation about this can be found in README_diy-bootdisk.md at Gitlab.
EOF
)

README_altbootscr=$(cat <<"EOF"
The boot scripts on the bootfs (aml_autoscript, s905_autoscript and uEnv.ini)
are sourced from Manjaro ARM but this is certainly not the only setup possible.
Another setup (with aml_autoscript, s905_autoscript, boot.scr), with somewhat
different logic, can be found (along with some comments and explanations) at
https://github.com/FauthD/amlogic-u-boot-scripts
Yet another setup (which is probably more versatile but may require bootloader
u-boot.bin flashed to the boot sector and gap before first partition) is the
scripts used on Ophub's images https://github.com/ophub/amlogic-s9xxx-armbian
An in-depth description of how boot scripts work on Amlogic can be found in
https://7ji.github.io/embedded/2022/11/11/amlogic-booting.html
EOF
)

# ---------------------------------- code ------------------------------------

cd $imgfile_dir

imgfile_loc=${imgfile_dir}/${imgfile_name}

# This is a rough estimate: We do not take into account temporary files etc.
imgfile_MiB=$((gap_MiB +boot_MiB +root_MiB))
desired_MiB=$((14*${imgfile_MiB}/10)) # Approx. space for imgfile +imgfile.xz

echo -e "\n\033[92m -- Making image for $distro_name ($distro_edition) -- \033[0m\n"

echo -e "The image container file will be at:"
echo $imgfile_loc

if [[ "$compressed_img" == "no" ]]; then
    required_MiB=$imgfile_MiB
else
    echo -e "\nThe finished (compressed) image file will be at (w/ kernel version inserted):"
    echo ${imgfile_loc}.xz
    required_MiB=$desired_MiB
fi

# The actual used space is smaller, but I don't know how to estimate that.
echo -e "\nMake sure that you have enough space: up to ~${required_MiB} MB +some.\n"
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

echo -e ${i_msg}" Setting up container file (${imgfile_MiB} MB)..."
dd if=/dev/zero of=$imgfile_loc bs=1M count=$imgfile_MiB \
   conv=fsync status=progress
sync
echo "Done."

echo -n -e ${i_msg}" Creating partitions in container file..."
parted -s $imgfile_loc mklabel msdos 2>/dev/null
parted -s $imgfile_loc mkpart primary fat32 \
       $((gap_MiB))MiB $((gap_MiB + boot_MiB))MiB 2>/dev/null
parted -s $imgfile_loc mkpart primary $rootfs_type \
       $((gap_MiB + boot_MiB))MiB 100% 2>/dev/null
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

rootp_msg="\033[94mroot\033[0m"
echo -n -e ${i_msg}" Mounting the $rootp_msg partition inside the container file..."
mkdir -p $rootfs_mnt
if ! mount ${loop_dev}p2 $rootfs_mnt ; then
    echo -e ${e_msg}" The command mount ${loop_dev}p2 failed, exiting."
    exit 1
fi
sync
echo " Done."

bootp_msg="\033[94mboot\033[0m"
echo -n -e ${i_msg}" Mounting the $bootp_msg partition inside the container file..."
mkdir -p $bootfs_mnt
if ! mount ${loop_dev}p1 $bootfs_mnt ; then
    echo -e ${e_msg}" The command mount ${loop_dev}p1 failed, exiting."
    exit 1
fi
echo " Done."

echo -e ${i_msg}" Downloading the Devuan debootstrab scripts ... "
wget -P $tmpfile_dir -nv ${devuan_dbscripts_url}/${devuan_dbscripts_tgz}
if [[ $? -ne 0 ]]; then
    echo -e ${w_msg}" Unable to download the Devuan debootstrap scripts, exiting"
    exit 1
else
    tar -xzf ${tmpfile_dir}/${devuan_dbscripts_tgz} -C ${tmpfile_dir}
    echo -e ${k_msg}" Done."
fi

echo -e ${i_msg}" Debootstrapping ${distro_name} system to ${rootfs_mnt}"
source $tmpfile_dir/source/functions
${tmpfile_dir}/source/debootstrap --arch arm64 --keyring $keyring_file \
	    $distro_release $rootfs_mnt $distro_repourl \
	    ${tmpfile_dir}/source/scripts/${distro_release}
echo "Done."

echo -n -e ${i_msg}" Setting up the fstab file..."
echo -e "$fstab_file" >${rootfs_mnt}/etc/fstab
# There is no UUID on a fat partition but in fstab the serial number works.
bootfs_UUID=$(blkid -s UUID -o value ${loop_dev}p1)
fstab_lastline="UUID=${bootfs_UUID}  $bootfs_dir  vfat   defaults  0  2"
echo -e "$fstab_lastline" >>${rootfs_mnt}/etc/fstab
echo " Done."

echo -n -e ${i_msg}" Setting the hostname in /etc/hostname ..."
echo -e "$host_name" >${rootfs_mnt}/etc/hostname
echo " Done."

# To enable sound on some boxes, edit and run this script as local user.
echo -e ${i_msg}" Installing script at /usr/local/bin/g12_sound.sh ..."
wget -P $tmpfile_dir -nv $g12_sound_url
if [[ $? -ne 0 ]]; then
    echo -e ${w_msg}" Unable to download the script g12_sound.sh"
else
    cp ${tmpfile_dir}/g12_sound.sh ${rootfs_mnt}/usr/local/bin
    chmod 0755 ${rootfs_mnt}/usr/local/bin/g12_sound.sh
    echo -e ${k_msg}" Done."
fi

echo -n -e ${i_msg}" Setting up directory /boot/grub ..."
mkdir -p -m 0755 ${rootfs_mnt}/boot/grub
echo " Done."

echo -n -e ${i_msg}" Writing info about grub.cfg and alternate kernels..."
echo -e "$README_kernels" >${rootfs_mnt}/boot/README_kernels.txt
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

echo -n -e ${i_msg}" Setting up /etc/network/interfaces ..."
mkdir -p ${rootfs_mnt}/etc/network
echo -e "$devuan_interfaces_file" >${rootfs_mnt}/etc/network/interfaces
echo " Done."

echo -n -e ${i_msg}" Setting up /etc/apt/sources.list ..."
rm -f ${rootfs_mnt}/etc/apt/sources.list
echo -e "$devuan_repo_list" >${rootfs_mnt}/etc/apt/sources.list
echo " Done."

echo -n -e ${i_msg}" Preparing for chroot jail..."
echo -e "$devuan_custom_inst" >${rootfs_mnt}/root/devuan_custom_inst.bash
chmod 0755 ${rootfs_mnt}/root/devuan_custom_inst.bash
echo " Done."

if [[ $arch_str != "aarch64" ]]; then
    echo -n -e ${i_msg}" Installing local qemu-aarch64-static binary..."
    qemu_binary_loc=$(which qemu-aarch64-static)
    cp $qemu_binary_loc ${rootfs_mnt}/usr/bin
    echo " Done."
fi

echo -e ${i_msg}" Entering chroot jail. Installing some pkgs., running some scripts..."
systemd-nspawn -q --resolv-conf=copy-host --timezone=off -D ${rootfs_mnt} \
               /root/devuan_custom_inst.bash
rm ${rootfs_mnt}/root/devuan_custom_inst.bash
sleep 2 # Just to be able to read some of the messages.
echo -e ${k_msg}" Done in chroot jail."

if [[ $arch_str != "aarch64" ]]; then
    echo -n -e ${i_msg}" Removing local qemu-aarch64-static binary..."
    rm ${rootfs_mnt}/usr/bin/qemu-aarch64-static
    echo " Done."
fi

echo -n -e ${i_msg}" Installing kernel, initramfs and (chosen) dtb file to bootfs..."
devuan_kern_vers=$(ls ${rootfs_mnt}/boot | grep vmlinuz- | cut -d '-' -f 2- )
cp ${rootfs_mnt}/boot/vmlinuz-${devuan_kern_vers} $bootfs_mnt/vmlinuz
cp ${rootfs_mnt}/boot/initrd.img-${devuan_kern_vers} $bootfs_mnt/initrd.img
dtbfile_dir=${rootfs_mnt}/usr/lib/linux-image-${devuan_kern_vers}/amlogic
dtbfile_loc=${dtbfile_dir}/${dtbfile_name}
if [[ -f $dtbfile_loc ]]; then
    cp $dtbfile_loc $bootfs_mnt
    echo " Done."
else
    echo -e ${e_msg}"\nCould not find $dtbfile_name"
    echo " in $dtbfile_dir"
    echo " Exiting."
    exit 1
fi

echo -n -e ${i_msg}" Setting up /etc/resolv.conf ..."
if [[ -f ${rootfs_mnt}/etc/resolv.conf ]]; then
    rm ${rootfs_mnt}/etc/resolv.conf
fi
echo -e "$devuan_resolver_file" >${rootfs_mnt}/etc/resolv.conf
echo " Done."

cd ${bootfs_mnt}

echo -e ${i_msg}" Setting up chainloader (u-boot.ext)..."
mkdir extlinux
echo -e "$extlinux_conf" >extlinux/extlinux.conf

mkdir u-boot-ophub
echo -e "$README_uboot_ophub" >u-boot-ophub/README_u-boot-ophub.txt
for uboot_bin in ${uboot_list[*]}; do
    uboot_bin_url=${ophub_uboot_url}/${uboot_bin}
    wget -nv -P u-boot-ophub $uboot_bin_url
    if [[ $? -ne 0 ]]; then
        echo -e ${w_msg}" Unable to download $uboot_bin"
    fi
done
echo -e ${k_msg}" Done setting up chainloader u-boot.ext."

if [[ -f ${imgfile_dir}/${uboot_ext_local} ]]; then
    echo -n -e ${i_msg}" Found $uboot_ext_local, installing it as default u-boot.ext ..."
    mkdir u-boot-3pole
    echo -e "$README_uboot_aml" >u-boot-3pole/README_u-boot-aml.txt
    cp ${imgfile_dir}/${uboot_ext_local} u-boot-3pole
    cp ${imgfile_dir}/${uboot_ext_local} u-boot.ext
fi

echo " Done."

echo -n -e ${i_msg}" Setting up script files on boot partition..."
touch aml_autoscript.zip
echo -e "$aml_autoscript" >aml_autoscript.txt
echo -e "$s905_autoscript" >s905_autoscript.txt
mkimage -A arm -O linux -T script -C none \
        -d aml_autoscript.txt aml_autoscript >/dev/null
mkimage -A arm -O linux -T script -C none \
        -d s905_autoscript.txt s905_autoscript >/dev/null
# Typically, vendor u-boot cannot boot newer kernels/initramfs via boot scripts.
# However, uEnv.ini can be used to boot via bootdisk (e.g. petit-*), see below.
echo -e "$uEnv" >uEnv.ini.bak
echo " Done."

# A small sales pitch for the bootdisk.
echo -n -e ${i_msg}" Writing instructions for installing Petitboot/u-root..."
echo -e "$README_auxbootldr" >README_auxbootldr.txt
echo " Done."

# Some info about alternate boot scripts.
echo -n -e ${i_msg}" Writing instructions for alternate boot scripts..."
echo -e "$README_altbootscr" >README_altbootscr.txt
echo " Done."

# Pick up the kernel version before we leave /boot.
kernel_version=$(ls ${rootfs_mnt}/boot | grep -E "vmlinuz-" | cut -b 9-)

cd $imgfile_dir

echo -n -e ${i_msg}" Unmounting the container file..."
umount -f ${loop_dev}p1
sync && sleep 2
umount -f ${loop_dev}p2
sync && sleep 2
echo " Done."

echo -n -e ${i_msg}" Disconnecting and removing the loop devices..."
losetup -d $loop_dev 2>/dev/null 
echo " Done."

imgfile_name_full=${distro_name}_${distro_edition}_${kernel_version}_${img_tag}.img
echo -n -e ${i_msg}" Renaming image file to $imgfile_name_full"
imgfile_loc_full=${imgfile_dir}/${imgfile_name_full}
mv $imgfile_loc $imgfile_loc_full
echo " Done."

if [[ "$compressed_img" == "yes" ]]; then
    echo -e ${i_msg}" Compressing the image using xz compression..."
    xz -v $imgfile_loc_full
    sleep 1
    echo "Done."
fi

if [[ "$docleanup_after" == "yes" ]]; then
    echo -n -e ${i_msg}" Doing final cleanup of build area..."
    rm -rf $tmpfile_dir
    rmdir $rootfs_mnt
    echo " Done."    
fi

echo -e "\n\033[92m -- Finished -- \033[0m\n"
