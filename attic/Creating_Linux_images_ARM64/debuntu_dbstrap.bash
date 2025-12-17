#!/bin/bash

# debuntu_dbstrap.bash
# 23-06-12: v0.13
# 25-12-08: v0.15
# Author: Tripole

# Usage: ./debuntu_dbstrap <distro>
#        where distro is one of: ubuntu, debian

# * This is a script to build a small Debian or Ubuntu Linux (CLI, "server")
#   image for ARM64 based SCBs, mainly intended for Amlogic based TV-boxes/SBCs.
# * The base system is created with the debootstrap mechanism using the official
#   repositories of Debian or Ubuntu and the resulting image has only a small
#   number of add-ons compared to pristine Debian/Ubuntu:
#   (1) Boot scripts for u-boot on the boot partition and a couple of related
#       scripts under /etc/kernel/postinst.d and /etc/initramfs/postupdate.d for
#       automatic updating of vmlinuz/initrd.img on the boot partition.
#   (2) Some optional utility scripts under /usr/local/bin (for grub.cfg etc).
# * The images can be put on e.g. SD or USB and be booted with two methods:
#   (1) Booting with resident/vendor (on eMMMC) u-boot using boot scripts and/or
#       extlinux.conf. This method defaults to chainloading with u-boot.ext.
#   (2) Booting can also be done with e.g. Petitboot/u-root (placed on the same
#       or separate medium) since the images have a valid grub.cfg.
# * This build script is designed to be run (as root) on an Ubuntu build host,
#   either natively on aarch64/ARM64 or virtualized (using qemu-aarch64-static)
#   on x86_64/amd64. The build host must have Debian keys installed (see below).
#   (It is quite possible it runs on Debian too, but this is not tested.)
# * Requirements: Basic functionality incl. blkid, dd, losetup, mkfs, xz, wget
#   and the package systemd-container (for systemd-nspawn). Most of the
#   requirements are checked at runtime below. For "cross-scripting" (i.e. build
#   on another architecture than aarch64/ARM64) it is required to install the
#   package qemu-user-static (for qemu-aarch64-static).
# * Typical usage: Edit the parameters below and run the script from a temporary
#   directory (the image as well as all temp files will be created in this dir).
#   If the file specified by $uboot_ext_local exists in this dir, it will be
#   used as u-boot.ext but there are also several versions of u-boot.bin from
#   Ophub installed that may serve as u-boot.ext when booting via chainloading.
#   A root ssh key file specified by $root_sshkey_loc can also be supplied.
# * Tested on: Ugoos AM6 plus (s922x) for booting and running the image, and on
#   QEMU (qemu-system-x86_64 (host) and qemu-system-aarch64 (chroot jail)) for
#   developing/building the image.

# Notes:
# - The installed system is fairly "bare-bones"; e.g. no swap is set (only zram).
#   A swapfile is easy to set up and can coexist with zram (see /etc/fstab).
#   Info about (re)configuring zram (and optionally set up swap) can be found
#   e.g. in /etc/default/zramswap and https://wiki.debian.org/ZRam
# - During execution of the script (near the end) you will be asked to configure
#   (dpkg-reconfigure) some items: time zone, locale, keyboard and set root pw.
# - Booting via u-boot boot scripts: This involves chainloading with u-boot.ext
#   (see below; several variants are supplied on the images). Chainloading is
#   the first boot method in the boot configuration file s905_autoscript on the
#   boot partition. If u-boot env of the resident/vendor u-boot (on eMMC) is not
#   set up to parse s905_autoscript then the boot scripts in env on eMMC can be
#   updated with the scripts in aml_autoscript on the boot partition. Such an
#   update is done by recovery boot ("reset/toothpick" boot). (In this boot mode
#   the reset pin is pushed and held during the first part of the boot process
#   which forces boot from SD and thereby parsing of aml_autoscript and loading
#   of new scripts into u-boot env. This has been a standard procedure used to
#   get Linux running on TV-boxes.) The chainloader u-boot.ext is a binary file
#   placed on the boot partition. Many candidates (for different SoCs) that can
#   be used as u-boot.ext are included on the image in the /u-boot-* directories
#   on the bootfs. Note: chainloading is also useful when the resident u-boot is
#   not capable of handling newer compression methods of kernel and intramfs.
#   In order to boot without chainloading it is general (for TV-boxes) necessary
#   to set up legacy (u-boot) boot scripts (boot.scr, boot.ini, uEnv.ini etc.)
#   and generate u-boot tagged versions of the kernel and initramfs (this is the
#   fallback boot method in s906_autoscript). (For info about this, see e.g. the
#   Armbian folder in https://github.com/FauthD/amlogic-u-boot-scripts/tree/main
#   and check boot.scr which is a text file with a u-boot tag (binary) header.)
#   On the other hand, if a newer version of u-boot is installed on eMMC, e.g.
#   a mainline version, it is likely that it can use extlinux.conf directly for
#   booting and chainloading as well as legacy boot scripts become unnecessary.
# - When booting via grub.cfg on rootfs (e.g. using bootdisk) the file grub.cfg
#   needs updating after upgrading the kernel and this can can be done by using
#   grub-mkimage or via scripts in /usr/local/bin e.g. mkgrubcfg_simple.bash
#   (Scripts for automating this task can be put in /etc/kernel/post{inst,rm}.)
# - The dtb file is not specified in the grub.cfg file upon installation but
#   the script mkgrubcfg_simple.bash can be run post-install to include a dtb
#   specification in grub.cfg. However, bootloaders based on kexec, such as
#   Petitboot/u-root, typically let the booted Linux image inherit the dtb used
#   by the bootloader, cf. the README files at Gitlab about Petitboot/u-root.
# - The automatic copying of vmlinuz,initrd.img to the bootfs partition after
#   kernel upgrade or initramfs rebuild always copies the newest kernel,initrd
#   (the one with the highest version number), as determined by the sort -V
#   command (cf. scripts in /etc/{kernel/postinst.d,initramfs/postupdate.d}).
# - Ubuntu: A simple working desktop can be obtained by installing e.g.
#     xubuntu-core (with e.g. lightdm, chosen at install time) or
#     ubuntu-desktop-minimal (gdm). Another alternative is kubuntu-desktop.
#     The snap system can cause trouble so it might be worth purging it.
# - The package linux-firmware is installed but firmware for e.g. a specific
#   WiFi or Bluethooth chip might not be included and thus have to be sought
#   elsewhere.
# - On some boxes it is necessary to run (as user) the script g12_sound.sh to
#   get sound working. (Afterwards, check for soundcards with e.g. aplay -L)
# - Run time for this script, for Debian, is about 15m (excl. compression, on a
#   modern computer with good network connectivity). For Ubloatu, it can take
#   almost three times that. (To check do: time ./debuntu_dbstrap.bash debian)
# - Pro tip: Generate the image cheaply, say 6G rootfs (so that burn to SD/USB
#   goes quickly). Then, enlarge the rootfs partition on the SD/USB. This can be
#   done on first boot by using growpart tool (see below). Alternatively, it can
#   be done before first boot by using either gparted (GUI) or (CLI) with the
#   combo of parted, e2fsck and resize2fs like so:
#   parted /dev/sdX resizepart 2 50% ; e2fsck -f /dev/sdX2 ; resize2fs /dev/sdX2
# - The disk (resized or not) is valid as an MBR partitoned disk but it can
#   easily be converted to GPT: First, start gdisk; gdisk /dev/sdX, and gdisk
#   will tell you that it has found a valid MBR and a missing (or corrupt GPT),
#   and it will ask you which one to use. Choose the MBR. At the gdisk prompt
#   then enter the command "r" which will take you to the recovery and
#   transformation options. There, enter the command "f" to load the MBR and
#   build a fresh GPT from it. At last, exit gdisk with "w" (write).
#   - Domain name resolution is now handled (also on Debian) by systemd, see
#   e.g. sec 2.1 in https://wiki.archlinux.org/title/Systemd-resolved
#   - A recent version of debian-archive-keyring is required on the host.

# ------------------------------- parameters ---------------------------------

# Top level directory in several file hierarchies used below and also the
# location of the disk image container during build (for size, see below).
# (Typically this is the directory in which the current script is located.)
imgfile_dir=$PWD

ubuntu_name=Ubuntu      # Used for the image name and in grub.cfg
ubuntu_edition=Noble    # Tested with Focal, Jammy, Noble
debian_name=Debian      # Used for the image name and in grub.cfg
debian_edition=Trixie   # Tested with Bullseye, Bookworm, Trixie

# The image tag will be added to img. name after distro name and kernel version.
img_tag=3pole-$(date +"%y%m%d")

# Host name for image.
host_name=debu

# The dtb file name used in extlinux.conf for booting. (File must exist in the
# aarch64 tree under /usr/lib/firmware/{kernel-version}/device-tree/amlogic)
dtbfile_name=meson-g12b-gtking-pro.dtb

# As an alternative to manual setup of u-boot.ext on the bootfs you can install
# a u-boot.ext automatically during image creation. If $uboot_ext_local contains
# the file path to a u-boot.ext then this file will be installed on the bootfs
# of the image as the default u-boot.ext.
uboot_ext_local=u-boot.bin-gtkp-pb-1s-ctrlc # See $uboot_ext_local_url below.

# If the file $root_sshkey_loc exists in $imgfile_dir then it will be installed
# on the image as /root/.ssh/authorized_keys (for passwordless ssh root login).
root_sshkey_loc="mysshkey.pub"

# File system sizes and types (unit MiB).
# - The partition table type on the image is MBR.
# - The min skip (gap) size (before 1st part) is 1MB (2048 sectors, 512B each).
# - The boot fs type is vfat/fat32 and the root fs type is one of {ext4,btrfs}
#   (btrfs is not really tested and is more of a placeholder for now).
# - The boot fs holds (mostly) one new and one old copy of vmlinuz, initrd.img.

gap_MiB=16
boot_MiB=500
root_MiB=6000
rootfs_type=ext4

# Compression (xz) of the finished image takes some extra time.
compressed_img=no # {yes,no}

# Do we want to clean up all temporary files and directories afterwards?
docleanup_after=yes # {yes,no}

# Of course, it is often better to use a mirror for the repo downloads, see e.g.
# https://www.debian.org/mirror/list and http://mirrors.ubuntu.com
ubuntu_repourl="http://ports.ubuntu.com/ubuntu-ports"
debian_repourl="http://ftp.debian.org/debian"

# Ophub repo (dir.) with u-boot.bin files for use as chainloader u-boot.ext.
ophub_repo_url="https://github.com/ophub"
ophub_raw_path="/u-boot/raw/refs/heads/main/u-boot/amlogic/overload"
ophub_uboot_url=${ophub_repo_url}${ophub_raw_path}

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

# This build tag and URL (for a GTKP u-boot.bin) are only used in a README file.
uboot_ext_local_bldtag=u-boot-amlogic-v2023.10
uboot_ext_local_url="https://mega.nz/folder/bIdjwI6B#mojtTtZPufsHD9v7gTkjdQ"

# Link to growpart for resizing second partition (rootfs) to desired size.
growpart_url="https://raw.githubusercontent.com/canonical/cloud-utils/main/bin/growpart"

# Link to g12_sound.sh for enabling sound on some boxes (run as local user).
g12_sound_url="https://gitlab.manjaro.org/manjaro-arm/packages/community/oc4-post-install/-/raw/master/g12_sound.sh"

# The string root=UUID=${rootfs_UUID} will be prepended below once UUID exists.
kernel_cmdline_opts="quiet splash"

# Holds downloads etc.
tmpfile_dir=${imgfile_dir}/temp_files

# Temporary mount points (dirs) used during image creation.
bootfs_dir=/boot/bootfs # Mount point in image, incl. leading slash.
rootfs_mnt=${imgfile_dir}/rootfs_tmp  # Mount point on build host, rootfs.
bootfs_mnt=${rootfs_mnt}${bootfs_dir} # Mount point on build host, bootfs.

# Some (but not all) commands used below to create the image.
reqd_cmdlist=("blkid" "dd" "debootstrap" "losetup" "mkfs.vfat" "mkimage" 
              "fsck.fat" "systemd-nspawn" "tar" "wget" "xz"
)

reqd_cmdlist_virt=("qemu-aarch64-static")

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

case $1 in
"ubuntu")
    distro_name=$ubuntu_name
    distro_edition=$ubuntu_edition
    distro_repourl=$ubuntu_repourl
    keyring_file=/usr/share/keyrings/ubuntu-archive-keyring.gpg
    bootfs_label=UBNT_BOOT
    rootfs_label=UBNT_ROOT
    ;;
"debian")
    distro_name=$debian_name
    distro_edition=$debian_edition
    distro_repourl=$debian_repourl
    keyring_file=/usr/share/keyrings/debian-archive-keyring.gpg
    bootfs_label=DEBN_BOOT
    rootfs_label=DEBN_ROOT
    if [[ "$debian_edition" == "Bullseye" ]] ; then
        nonfree_list="non-free"
        iface_name="eth0"
    else
        nonfree_list="non-free non-free-firmware"
        iface_name="end0"
    fi
    if [[ "$debian_edition" == "Trixie" ]] ; then
        time_pkg=systemd-timesyncd
    else
        time_pkg=ntp
    fi
    ;;
*)
    echo "Usage: debuntu_inst.bash <distro>"
    echo "       where distro is one of: ubuntu,debian"
    echo "       For more customizable parameters, see inside the script."
    echo "       (Must be run as root.)"
    exit 0
    ;;
esac

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

# The debian-keyring package contains also the keys for the archives/repos.
if [[ "$1" == "debian" ]]; then
deb_keyring_isinst=$(dpkg -l | awk '/debian-keyring/ {print }' | wc -l)
    if [[ $deb_keyring_isinst -eq 0 ]]; then
        echo ${e_msg}" The Debian keyring is not installed, exiting."
        exit 1
    fi
fi

if [[ "$rootfs_type" == "ext4" ]]; then
    reqd_cmdlist=("${reqd_cmdlist[@]}" "mkfs.ext4" "e2fsck")
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

# For processing in the here-docs below.
ubuntu_release="$(tr [A-Z] [a-z] <<< "$ubuntu_edition")" # To lowercase.
debian_release="$(tr [A-Z] [a-z] <<< "$debian_edition")" # To lowercase.

# ------------------------------- here-docs ----------------------------------

# Below we add also a line for the vfat boot partition.
# (For swap we only add a stub, see https://help.ubuntu.com/community/SwapFaq)
fstab_file=$(cat <<EOF
UUID=$rootfs_UUID  /  $rootfs_type   errors=remount-ro  0  1
# zram is normally handled by systemd, so the next line should be commented out
# /dev/zram0      none       swap   defaults,pri=100 0 0
# A regular swap file can also be used (also together with zram). To use a swap
# file follow the instructions in https://help.ubuntu.com/community/SwapFaq
# and uncomment the next line
#/swapfile        none  swap        defaults,pri=50  0  0
EOF
)

debian_interfaces_file=$(cat <<EOF
allow-hotplug $iface_name
auto $iface_name
iface $iface_name inet dhcp
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
alloweth_nmconf_file=$(cat <<"EOF"
[keyfile]
unmanaged-devices=*,except:type:wifi,except:type:gsm,except:type:cdma,except:type:ethernet
EOF
)

ubuntu_repo_list=$(cat <<EOF
deb http://ports.ubuntu.com/ubuntu-ports/ $ubuntu_release main restricted
deb http://ports.ubuntu.com/ubuntu-ports/ ${ubuntu_release}-updates main restricted

deb http://ports.ubuntu.com/ubuntu-ports/ $ubuntu_release universe
deb http://ports.ubuntu.com/ubuntu-ports/ ${ubuntu_release}-updates universe

deb http://ports.ubuntu.com/ubuntu-ports/ ${ubuntu_release} multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ ${ubuntu_release}-updates multiverse

# deb http://ports.ubuntu.com/ubuntu-ports/ ${ubuntu_release}-backports main restricted universe multiverse

deb http://ports.ubuntu.com/ubuntu-ports/ ${ubuntu_release}-security main restricted
deb http://ports.ubuntu.com/ubuntu-ports/ ${ubuntu_release}-security universe
deb http://ports.ubuntu.com/ubuntu-ports/ ${ubuntu_release}-security multiverse
EOF
)

flashk_block_file=$(cat <<"EOF"
Package: flash-kernel
Pin: release *
Pin-Priority: -1
EOF
)

# If you want to add packages (to the default below), this is where to do it.
ubuntu_custom_extra=$(cat <<"EOF"
apt-get -y install nano aptitude usbutils zram-tools sudo
EOF
)

# This is the basic (default) set of packages installed on top of the rootfs.
# (If you want to add packages, edit the here-doc ubuntu_custom_extra above.)
ubuntu_custom_inst=$(cat <<EOF
#!/bin/bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y install linux-image-generic
# DEBIAN_FRONTEND=noninteractive apt-get -y install linux-headers-generic
DEBIAN_FRONTEND=noninteractive apt-get -y install man-db network-manager ssh dialog u-boot-tools
DEBIAN_FRONTEND=noninteractive $ubuntu_custom_extra
dpkg-reconfigure tzdata
dpkg-reconfigure locales
dpkg-reconfigure keyboard-configuration

echo "Set password for \033[91mroot:\033[0m"
until passwd; do echo "Try again."; done

echo "Creating /boot/grub/grub.cfg"
rootfsUUID=$rootfs_UUID bash -c '/usr/local/bin/mkgrubcfg_simple.bash'

sync
EOF
)

debian_repo_list=$(cat <<EOF
deb http://deb.debian.org/debian $debian_release main contrib $nonfree_list
deb http://deb.debian.org/debian ${debian_release}-updates main contrib $nonfree_list
# deb http://deb.debian.org/debian ${debian_release}-backports main contrib $nonfree_list
deb http://security.debian.org/debian-security/ ${debian_release}-security main contrib $nonfree_list
EOF
)

debian_repo_list_deb822=$(cat <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: $debian_release ${debian_release}-updates
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: ${debian_release}-security
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
)

debian_custom_extra=$(cat <<"EOF"
apt-get -y install aptitude usbutils zram-tools
EOF
)

debian_custom_inst=$(cat <<EOF
#!/bin/bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt -y install linux-image-arm64
# DEBIAN_FRONTEND=noninteractive apt -y install linux-headers-arm64
DEBIAN_FRONTEND=noninteractive apt -y install locales $time_pkg sudo ssh u-boot-tools
DEBIAN_FRONTEND=noninteractive $debian_custom_extra
dpkg-reconfigure tzdata
dpkg-reconfigure locales
apt -y install console-setup

echo "Set password for \033[91mroot:\033[0m"
until passwd; do echo "Try again."; done

echo "Creating /boot/grub/grub.cfg"
rootfsUUID=$rootfs_UUID bash -c '/usr/local/bin/mkgrubcfg_simple.bash'

sync
EOF
)

aml_autoscript=$(cat <<"EOF"
# Standard aml_autoscript to set u-boot boot (script) order: mmc/SD, USB, emmc
# Search for {emmc,s905}_autoscript on these device types and execute the first found.
# Sourced from Manjaro ARM.
# Note: On newer u-boot, the autoscr is replaced by the source command.
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

# This is just intended as a template (it is fallback in s905_autoscript).
uEnv=$(cat <<EOF
# For default names and formats of kernel and initramfs, see s905_autoscript.
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

MENU TITLE <DEBUNTU-BOOT>
DEFAULT DEBNT_DEFAULT

# Timeout is in units of 0.1s (to wait before boot of default entry below).
TIMEOUT 10

LABEL DEBNT_DEFAULT
  LINUX  /vmlinuz
  INITRD /initrd.img
  FDT    /$dtbfile_name
# More possible/useful options for APPEND (kernel command line):
# rootflags=data=writeback rw rootwait rootfstype=ext4
# console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0
# fsck.fix=yes fsck.repair=yes loglevel=1
# vout=hdmi disablehpd=false overscan=100 sdrmode=auto
  APPEND $kernel_cmdline
EOF
)

# We split this file in two; one part with parameter substitution and one w/o.
upd_bootfs_common=$(cat <<EOF
#!/bin/sh

set -e

bootpart_dir_=$bootfs_dir
EOF
)

# https://kernel-team.pages.debian.net/kernel-handbook/ch-update-hooks.html
# $1 for any script under /etc/kernel or /etc/initramfs is version of "calling"
# kernel in in ABI format (as from uname -r).
upd_bootfs_kernel_p2=$(cat <<"EOF"

# Copies vmlinuz to the boot partition. No check for available space.

kern_ver=$1

echo "Copying vmlinuz to boot partition..."
if [ -f ${bootpart_dir_}/vmlinuz ] ; then
  mv ${bootpart_dir_}/vmlinuz ${bootpart_dir_}/vmlinuz.old
fi

cp -v /boot/vmlinuz-$kern_ver ${bootpart_dir_}/vmlinuz

echo " Done."
EOF
)

upd_bootfs_kernel="${upd_bootfs_common}""${upd_bootfs_kernel_p2}"

upd_bootfs_initrd_p2=$(cat <<"EOF"

# Copies initramfs.img to the boot partition. No check for available space.

kern_ver=$1

echo "Copying initrd.img to boot partition..."
if [ -f ${bootpart_dir_}/initrd.img ] ; then
  mv ${bootpart_dir_}/initrd.img ${bootpart_dir_}/initrd.img.old
fi

cp -v /boot/initrd.img-$kern_ver ${bootpart_dir_}/initrd.img

echo " Done."
EOF
)

upd_bootfs_initrd="${upd_bootfs_common}""${upd_bootfs_initrd_p2}"

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
installed to choose from at the bootmanager prompt and to boot kernels (and
Linux OSes) installed on other attached removable media. For more info on such
"bootdisk" booting, see https://gitlab.com/tripole-inc/bootdisk

Hidden bootloader
-----------------

To boot this disk image with u-boot requires a working resident/vendor u-boot
bootloader but this restriction can be removed if a "hidden" bootloader, i.e.
u-boot, is installed in the "gap" leading up to the first partition. With such
a hidden bootloader properly installed, the disk will always boot from SD or USB
on Amlogic devices when the resident/vendor u-boot is missing or non-functional.
More information about this can be found in README_diy-bootdisk.md at Gitlab.
EOF
)

README_altbootscr=$(cat <<"EOF"
The boot scripts on the bootfs (aml_autoscript, s905_autoscript, etc.) are
sourced from Manjaro ARM but this is certainly not the only setup possible.
Another setup (with aml_autoscript, s905_autoscript and legacy boot.scr),
with somewhat different logic, can be found (along with some comments and
explanations) at
https://github.com/FauthD/amlogic-u-boot-scripts
Yet another setup is the scripts used on Ophub's images
https://github.com/ophub/amlogic-s9xxx-armbian
An in-depth description of how boot scripts work on Amlogic can be found in
https://7ji.github.io/embedded/2022/11/11/amlogic-booting.html
EOF
)

README_uboot_ophub=$(cat <<"EOF"
The files in this directory are intended to be used as chainloader (i.e. last
stage) of u-boot, when booting via the chainloading method (on an Amlogic SoC).
(The default boot methods are grub.cfg and boot script.) Usage: Find here a
binary u-boot-* which matches your box and copy it to the name u-boot.ext at
the top level on the boot (fat) partition. Then edit extlinux/extlinux.conf
according to the instructions inside that file. The files here are from
Ophub's repo at https://github.com/ophub/u-boot where also suitable candidates
for u-boot.ext for other platforms (e.g. Allwinner, Rockchip) can be found.
Note: Some chainloaders here can not boot newer kernels/initramfs.
EOF
)

README_uboot_aml=$(cat <<EOF
The file $uboot_ext_local is compiled from source using
https://source.denx.de/u-boot/custodians/u-boot-amlogic
using the tag $uboot_ext_local_bldtag
with gtk pro defconf and usb_start added as preboot command.
For more info about $uboot_ext_local and downloads of similar files see
$uboot_ext_local_url
Finally, an excellent exposition of the boot flow for Amlogic can be found at
https://7ji.github.io/embedded/2022/11/11/amlogic-booting.html
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


# ---------------------------------- code ------------------------------------

cd $imgfile_dir

imgfile_loc=${imgfile_dir}/${imgfile_name}

# This is a rough estimate: We do not take into account temporary files etc.
imgfile_MiB=$((gap_MiB +boot_MiB +root_MiB))
desired_MiB=$((14*${imgfile_MiB}/10)) # Approx. space for imgfile +imgfile.xz

echo -e "\n\033[92m -- Making image for $distro_name ($distro_edition, arm64) -- \033[0m\n"

echo -e "Image container file path (during build):"
echo $imgfile_loc

if [[ "$compressed_img" == "no" ]]; then
    required_MiB=$imgfile_MiB
else
    echo -e "\nFinished (compressed) image file path (w/ kernel version inserted):"
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
    exit 0
fi

echo -e "\n\033[92m -- Starting the installation -- \033[0m\n"

umask 022

echo -n -e ${i_msg}" Making a directory for temporary files..."
mkdir -p $tmpfile_dir
echo " Done."

echo -e ${i_msg}" Setting up container file (${imgfile_MiB} MB)..."
dd if=/dev/zero of=$imgfile_loc bs=1M count=$imgfile_MiB \
   conv=fsync status=progress
sync
echo "Done."

echo -n -e ${i_msg}" Creating partitions (MBR) in container file..."
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

echo -e ${i_msg}" Debootstrapping the ${distro_name} system to ${rootfs_mnt}"
debootstrap --arch arm64 --keyring $keyring_file \
$distro_release $rootfs_mnt $distro_repourl
echo -e ${k_msg}" Done."

echo -n -e ${i_msg}" Setting up the fstab file..."
mkdir -p ${rootfs_mnt}/etc
echo -e "$fstab_file" >${rootfs_mnt}/etc/fstab
# There is no UUID on a fat partition but in fstab the serial number works.
bootfs_UUID=$(blkid -s UUID -o value ${loop_dev}p1)
fstab_lastline="UUID=${bootfs_UUID}  $bootfs_dir  vfat   defaults  0  2"
echo -e "$fstab_lastline" >>${rootfs_mnt}/etc/fstab
echo " Done."

echo -n -e ${i_msg}" Setting the hostname in /etc/hostname ..."
echo -e "$host_name" >${rootfs_mnt}/etc/hostname
echo " Done."

echo -n -e ${i_msg}" Installing bootfs scripts in /etc/{kernel,initramfs} ..."
mkdir -p ${rootfs_mnt}/etc/kernel/postinst.d
echo -e "$upd_bootfs_kernel" >${rootfs_mnt}/etc/kernel/postinst.d/upd_bootfs_kernel
chmod 0755 ${rootfs_mnt}/etc/kernel/postinst.d/upd_bootfs_kernel
mkdir -p ${rootfs_mnt}/etc/initramfs/post-update.d
echo -e "$upd_bootfs_initrd" >${rootfs_mnt}/etc/initramfs/post-update.d/upd_bootfs_initrd
chmod 0755 ${rootfs_mnt}/etc/initramfs/post-update.d/upd_bootfs_initrd
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

# This script (Canonical) provides an alternative method for resizing rootfs.
echo -e ${i_msg}" Installing growpart script in /usr/local/bin ..."
if ! wget -P $tmpfile_dir -nv $growpart_url ; then
    echo -e ${w_msg}" Unable to download the script growpart.sh"
else
    cp ${tmpfile_dir}/growpart ${rootfs_mnt}/usr/local/bin/growpart.sh
    chmod 0755 ${rootfs_mnt}/usr/local/bin/growpart.sh
    echo -e ${k_msg}" Done."
fi

echo -n -e ${i_msg}" Setting up directory /boot/grub ..."
mkdir -p ${rootfs_mnt}/boot/grub
echo " Done."

echo -e ${i_msg}" Installing g12_sound script in /usr/local/bin ..."

if ! wget -P $tmpfile_dir -nv $g12_sound_url ; then
    echo -e ${w_msg}" Unable to download the script g12_sound.sh"
else
    cp ${tmpfile_dir}/g12_sound.sh ${rootfs_mnt}/usr/local/bin
    chmod 0755 ${rootfs_mnt}/usr/local/bin/g12_sound.sh
    echo -e ${k_msg}" Done."
fi

dtbfile_dir=""

case $1 in
    "ubuntu")
        echo -n -e ${i_msg}" Setting up local host mappings in /etc/hosts ..."
        echo -e "$ubuntu_hosts_file" >${rootfs_mnt}/etc/hosts
        echo " Done."

        echo -n -e ${i_msg}" Installing Network Manager configuration files for eth0 ..."

        nm_conf_dir=${rootfs_mnt}/etc/NetworkManager
        nm_syscon_dir=${nm_conf_dir}/system-connections
        mkdir -p $nm_syscon_dir
        eth0_nmconf_loc=${nm_syscon_dir}/Wired_connection_1.nmconnection
        echo -e "$eth0_nmconf_file"> $eth0_nmconf_loc
        chmod 0600 $eth0_nmconf_loc

        alloweth_nmconf_dir=${nm_conf_dir}/conf.d
        mkdir -p $alloweth_nmconf_dir
        alloweth_nmconf_loc=${alloweth_nmconf_dir}/allow-ethernet.conf
        echo -e "$alloweth_nmconf_file" >$alloweth_nmconf_loc

        echo " Done."

        # From debootstrap there will be an interfering resolv.conf file which
        # we remove. After leaving the chroot jail below there will also be a
        # leftover resolv.conf but it will be fixed automagically by the
        # systemd-resolved.service
        if [[ -f ${rootfs_mnt}/etc/resolv.conf ]]; then
            echo -n -e ${i_msg}" Removing (interfering) pre installed /etc/resolv.conf ..."
            rm ${rootfs_mnt}/etc/resolv.conf
            echo " Done."
        fi

        # The flash-kernel package causes problems on syst. w/o flash storage.
        echo -n -e ${i_msg}" Preventing apt from installing package flash-kernel..."
        echo -e "$flashk_block_file" >\
            ${rootfs_mnt}/etc/apt/preferences.d/no-flash-kernel
        echo " Done."

        echo -n -e ${i_msg}" Setting up /etc/apt/sources.list ..."
        rm -f ${rootfs_mnt}/etc/apt/sources.list
        echo -e "$ubuntu_repo_list" >${rootfs_mnt}/etc/apt/sources.list
        echo " Done."

        echo -n -e ${i_msg}" Preparing for chroot jail..."
        echo -e "$ubuntu_custom_inst" >${rootfs_mnt}/root/custom_inst.bash
        echo " Done."
    ;;
    "debian")
        echo -n -e ${i_msg}" Setting up /etc/network/interfaces ..."
        mkdir -p ${rootfs_mnt}/etc/network
        echo -e "$debian_interfaces_file" >${rootfs_mnt}/etc/network/interfaces
        echo " Done."

        if [[ "$debian_edition" == "Trixie" ]]; then
            echo -n -e ${i_msg}" Setting up /etc/apt/sources.list.d/debian.sources ..."
	    rm -f ${rootfs_mnt}/etc/apt/sources.list
            rm -f ${rootfs_mnt}/etc/apt/sources.list.d/debian.sources
            echo -e "$debian_repo_list_deb822" > ${rootfs_mnt}/etc/apt/sources.list.d/debian.sources
        else
            echo -n -e ${i_msg}" Setting up /etc/apt/sources.list ..."
            rm -f ${rootfs_mnt}/etc/apt/sources.list
            echo -e "$debian_repo_list" >${rootfs_mnt}/etc/apt/sources.list
        fi
        echo " Done."

        echo -n -e ${i_msg}" Preparing for chroot jail..."
        echo -e "$debian_custom_inst" >${rootfs_mnt}/root/custom_inst.bash
        echo " Done."
    ;;
esac

if [[ $arch_str != "aarch64" ]]; then
    echo -n -e ${i_msg}" Installing local qemu-aarch64-static binary..."
    qemu_binary_loc=$(which qemu-aarch64-static)
    cp $qemu_binary_loc ${rootfs_mnt}/usr/bin
    echo " Done."
fi

echo -e ${i_msg}" Entering \033[94mchroot jail\033[0m. Running installation scripts..."
chmod 0755 ${rootfs_mnt}/root/custom_inst.bash
systemd-nspawn -q --resolv-conf=copy-host --timezone=off -D ${rootfs_mnt} \
               /root/custom_inst.bash
rm ${rootfs_mnt}/root/custom_inst.bash
sleep 2 # Just to be able to read some of the messages.
echo "Done. Exited \033[94mchroot jail\033[0m."

if [[ $arch_str != "aarch64" ]]; then
    echo -n -e ${i_msg}" Removing local qemu-aarch64-static binary..."
    rm ${rootfs_mnt}/usr/bin/qemu-aarch64-static
    echo " Done."
fi

cd ${bootfs_mnt}

echo -e ${i_msg}" Setting up chainloader u-boot.ext ..."
mkdir extlinux
echo -e "$extlinux_conf" >extlinux/extlinux.conf

mkdir u-boot-ophub
echo -e "$README_uboot_ophub" >u-boot-ophub/README_u-boot-ophub.txt
for uboot_bin in ${uboot_list[*]}; do
    uboot_bin_url=${ophub_uboot_url}/${uboot_bin}
    if ! wget -nv -P u-boot-ophub $uboot_bin_url ; then
        echo -e ${w_msg}" Unable to download $uboot_bin"
    fi
done
echo -e ${k_msg}" Done setting up chainloader u-boot.ext."

if [[ -f ${imgfile_dir}/${uboot_ext_local} ]]; then
    echo -n -e ${i_msg}" Found \033[94m${uboot_ext_local}\033[0m, installing it as default u-boot.ext ..."
    mkdir u-boot-3pole
    echo -e "$README_uboot_aml" >u-boot-3pole/README_u-boot-aml.txt
    cp ${imgfile_dir}/${uboot_ext_local} u-boot-3pole
    cp ${imgfile_dir}/${uboot_ext_local} u-boot.ext
fi
echo " Done."

echo -n -e ${i_msg}" Setting up boot script files on boot partition..."
touch aml_autoscript.zip
echo -e "$aml_autoscript" >aml_autoscript.txt
echo -e "$s905_autoscript" >s905_autoscript.txt
mkimage -A arm -O linux -T script -C none \
        -d aml_autoscript.txt aml_autoscript >/dev/null
mkimage -A arm -O linux -T script -C none \
        -d s905_autoscript.txt s905_autoscript >/dev/null
echo " Done."

echo -n -e ${i_msg}" Copying the \033[94m${dtbfile_name}\033[0m file to bootfs..."
kern_vers=$(ls ${rootfs_mnt}/boot | grep vmlinuz- | cut -d '-' -f 2- )
case $1 in
    "ubuntu")
        dtbfile_dir=${rootfs_mnt}/usr/lib/firmware/${kern_vers}/device-tree/amlogic
    ;;
    "debian")
        dtbfile_dir=${rootfs_mnt}/usr/lib/linux-image-${kern_vers}/amlogic
    ;;
esac
dtbfile_dist=${dtbfile_dir}/${dtbfile_name}
if [[ -f $dtbfile_dist ]]; then
    cp $dtbfile_dist $bootfs_mnt
    echo " Done."
else
    echo -e " Fail!"
    echo -e ${w_msg}" Could not find the device tree file $dtbfile_name in"
    echo " $dtbfile_dir"
    echo -e ${w_msg}" Device tree file must be set up manually on the image."
fi

echo -n -e ${i_msg}" Writing instructions for alternate boot scripts..."
echo -e "$README_altbootscr" >README_altbootscr.txt
echo " Done."

echo -n -e ${i_msg}" Writing info about grub.cfg and alternate kernels..."
echo -e "$README_kernels" >README_kernels.txt
echo " Done."

echo -n -e ${i_msg}" Writing instructions for installing Petitboot/u-root..."
echo -e "$README_auxbootldr" >README_auxbootldr.txt
echo " Done."

# Pick up the kernel version for later use.
kernel_version=$(ls ${rootfs_mnt}/boot | grep -E "vmlinuz-" | cut -b 9-)

cd $imgfile_dir

if [[ -f $root_sshkey_loc ]]; then
    echo -e -n ${i_msg}" Installing key in file \033[94m${root_sshkey_loc}\033[0m as ssh key for root..."
    mkdir -p ${rootfs_mnt}/root/.ssh
    chmod 0700 ${rootfs_mnt}/root/.ssh
    cp $root_sshkey_loc ${rootfs_mnt}/root/.ssh/authorized_keys
    chmod 0600 ${rootfs_mnt}/root/.ssh/authorized_keys
    # Typically, the defaults in sshd_config are
    # "PermitRootLogin prohibit-password"
    # "PubkeyAuthentication yes"
    # so the only thing we need to do change the line with
    # "PasswordAuthentication".
    sed -i '/.*PasswordAuthentication.*/c\PasswordAuthentication no' \
        ${rootfs_mnt}/etc/ssh/sshd_config
    echo " Done."
fi

echo -e ${i_msg}" Unmounting the container file (and file system check)..."
sync
umount -f ${loop_dev}p1
sleep 2
fsck.fat -a ${loop_dev}p1
umount -f ${loop_dev}p2
sleep 2
if [[ $rootfs_type == "ext4" ]]; then
    e2fsck -p ${loop_dev}p2
fi
echo " Done."

echo -n -e ${i_msg}" Disconnecting and removing the loop devices..."
losetup -d $loop_dev 2>/dev/null
echo " Done."

imgfile_name_full=${distro_name}_${distro_edition}_${kernel_version}_${img_tag}.img
echo -n -e ${i_msg}" Adding kernel version to image name..."
imgfile_loc_full=${imgfile_dir}/${imgfile_name_full}
mv $imgfile_loc $imgfile_loc_full
echo " Done."

echo -e ${i_msg}" Output file: \033[94m${imgfile_name_full}\033[0m"

if [[ "$docleanup_after" == "yes" ]]; then
    echo -n -e ${i_msg}" Doing final cleanup of build area..."
    rm -rf $tmpfile_dir
    rmdir $rootfs_mnt
    echo " Done."
fi

if [[ "$compressed_img" == "yes" ]]; then
    echo -e ${i_msg}" Compressing the image using xz compression..."
    xz -v $imgfile_loc_full
    sleep 1
    echo "Done."
fi

echo -e "\n\033[92m -- $0 finished -- \033[0m\n"
