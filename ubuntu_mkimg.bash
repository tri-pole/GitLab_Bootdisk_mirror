#!/bin/bash

# ubuntu_mkimg.bash (a.k.a. {op,tri}buntu_mkimg.bash)
# 23-05-08: v0.25
# Author: Tripole

# Script to generate an Ubuntu ARM64 (CLI, "server") image with a custom kernel
# (e.g. ophub or 3pole) for Amlogic TV-boxes/SBCs. The Ubuntu base system is
# from daily builds of the rootfs of the Jammy, Focal, or Kinetic releases.
# The script must be executed (as root) on an Ubuntu/Debian type machine,
# either natively on aarch64/ARM64 or virtualized (using qemu-aarch64-static)
# on x86_64/amd64.
# The generated image can be booted with resident/vendor u-boot (using the boot
# scripts on the fat partition) or via bootdisk (using the grub.cfg file on the
# rootfs partition). Another alternative is chainloader u-boot.ext (included).

# Prerequisites: A donwloaded an unpacked tarball of Ophub's or Tripole's
# kernel (into sub-tarballs) in the local kernel directory (specified below).

# Usage: ./ubuntu_mkimg.bash
#        (i.e. no arguments, but check the parameters/options below)

# Tested on: Ugoos AM6 plus and Beelink GT King Pro (s922x, for executing,
# booting and running) and on QEMU (qemu-system-x86_64 and qemu-system-aarch64,
# for developing/executing). This script should be considered as a template or
# proof-of-concept, nothing more (so please fork it, adapt it, improve it).

# Requires: Standard basic functionality incl. blkid, dd, losetup, mkfs, xz,
# wget and the package systemd-container (for systemd-nspawn). ArchLinux wiki:
# "systemd-nspawn is like the chroot command, but it is a chroot on steroids."
# Most of the requirements are checked at runtime below. For "cross-scripting"
# (i.e. use on another architecture than aarch64) you need to install the
# package qemu-user-static (which recommends the package binfmt-support); this
# provides the required binary qemu-aarch64-static

# Typical usage: Edit the parameters below and run the script from a temporary
# directory (the image as well as all temp. files will be created in this dir.).

# Inspiration taken from:
# https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/rebuild
# https://github.com/manjaro-arm/am6-plus-images/releases

# Notes:
# - The kernel files in the local kernel direectory (see below) should be the
#   same as the sub-tarballs found in Ophub's and Tripole's main tarball, like
#   boot-<krnver_str>-tar.gz ,
#   modules-<krnver_str>-tar.gz ,
#   header-<krnver_str>-tar.gz or headers-<krnver_str>-tar.gz ,
#   dtb-amlogic-<krnver_str>-tar.gz ,
#   dtb-allwinner-<krnver_str>-tar.gz ,
#   dtb-rockchip-<krnver_str>-tar.gz .
# - The Ubuntu rootfs comes in a "minimized" state (see e.g. Ubuntu Wiki) for
#   most packages and therefore it is advisable to run the command unminimize
#   (and reboot) to restore the system into normal state at the first boot.
#   More generally, the system is "bare-bones"; e.g. no swap is set (only zram).
# - During installation, on some terminals the keyboard and console font
#   configuration will be deferred and you will see a message about this.
#   (You can always later manually do dpkg-reconfigure keyboard-configuration)
# - On some boxes, when booting from USB using vendor u-boot and the boot
#   scripts, only the image stick can be attached to the USB bus. When booting
#   using a chainloader (u-boot.ext) it should not be a problem to have other
#   (non bootable) USB sticks attached. When using grub booting (e.g. with a
#   bootdisk on SD) having other USB sticks attached is not a problem. There
#   are also links to alternate boot scripts in a README file on bootfs.
# - The dtb file is only used when booting via u-boot. When booting via grub
#   (e.g. using bootdisk) it is assumed that a dtb file is loaded by other
#   means (e.g. by the bootdisk software; see the bootdisk documantation).
# - The uImage and uInitrd (u-boot tagged) versions of the kernel and initramfs
#   that are on the boot partition (for booting via vendor u-boot) are created
#   by the mkbootlinux.bash script (see below). Therefore, when updating the
#   kernel or initramfs the uImage uInitrd have to be recreated "manually"
#   using this script (unless you rely on grub booting, then only grub.cfg on
#   the rootfs partition has to be updated; see the scripts in /usr/local/bin).
# - Tripole kernels built with source directly from kernel.org can be found at
#   https://mega.nz/folder/GJNjjSAY#Zru4DqCa6hyYnnkGuw02Rw
# - The installed kernel pkg. files are saved also in /var/cache/kernel.pkg
# - The standard Ubuntu kernel linux-image-generic can also be installed (after
#   unminizing). It is then recommended to first install the dependency package
#   linux-firmware (ca 900M) and then the package linux-image-generic.
#   (This is to avoid problems with the package linux-firmware not being fully
#   configured which can apparently happen otherwise.) The installation scripts
#   for linux-image-generic will automatically generate a new valid grub.cfg
#   which will include also an entry for the Ophub/local kernel (albeit with
#   the Ubuntu generic kernel command line parameters). (Alternatively, there
#   is the script /usr/local/bin/mkgrubcfg_simple.bash which creates a simple
#   grub.cfg for all kernels with a different command line; check it out.)
# - A simple working desktop can be obtained by installing e.g. xubuntu-core
#   (with e.g. lightdm, chosen at install time) or ubuntu-desktop-minimal (gdm).
#   Another alternative is kubuntu-desktop (nice and polished but larger).
# - On some boxes it is necessary to run (as user) the script g12_sound.sh to
#   get sound working. (Afterwards, check for soundcards with e.g. aplay -L)
# - Run time for this script (excl. compression) is less than 10m (on a modern
#   computer with good network connectivity). Check: time ./ubuntu_mkimg.bash
# - You will be asked to configure three things at runtime (near the end):
#   time zone, keyboard and root password.
# - Basic configuration: You might want to configure zram (and optionally set
#   up swap), see e.g. https://wiki.debian.org/ZRam and also the info and links
#   inside the config. file /etc/default/zramswap (try e.g. with PERCENT=35).
#   Also, you can remove/disable unnecessary packages/functionality, e.g.
#   # systemctl disable spice-vdagent.service --now
#   # apt remove snapd && apt autoremove
# - Pro tip: Generate the image cheaply, say 3G rootfs (so that burn to SD/USB
#   goes quickly). Then, (before first boot) enlarge the rootfs partition on
#   SD/USB to desired size, e.g. with (100% here uses all of the SD/USB):
#   parted /dev/sdX resizepart 2 50% ; e2fsck -f /dev/sdX2 ; resize2fs /dev/sdX2

# ------------------------------- parameters ---------------------------------

# Q: Which parameters do I (really) need to edit?
# A: Well, as always, "it depends". (Best to browse through them all, I guess.)

distro_name=Ubuntu   # Used for the image name and in grub.cfg
distro_edition=Lunar # Tested with Focal, Jammy, Kinetic, Lunar

# Host name for image.
host_name=opbu

# Compression (xz) takes some extra time (beyond the estimate above).
compressed_img=yes # {yes,no}

# Name and tag for resulting disk image (uncomment and edit to taste).
# Example for Ophub/Flippy kernel.
krnver_str="6.1.27-ophub" # Kernel name/release str., plain text.
# Example for koop-3pole kernel.
# krnver_str="6.1.27-koop-3pole" # Kernel name/release str., plain text.

# This is the name used on the container file during image creation.
# Before exit of this script, the kernel version is inserted into the name.
img_tag=${krnver_str}_$(date +"%y%m%d") # Edit to your liking.
imgfile_name=${distro_name}_${distro_edition}_${img_tag}.img

# List of names for the SoC vendors for which you wish to download and install
# the dtb package (the selected dtb below must be in one of these packages).
# Ophub packages dtbs for amlogic, allwinner and rockchip w/ his kernels.
# (The paths to the dtb packages (defined below) are of the form
# ${ophub_krepo_url}/dtb-${socdtbs_name}-${krnver_str_url}.tar.gz)
socdtbs_list=("amlogic" "allwinner" "rockchip")

# dtb name in uEnv.ini/extlinux.conf (dtb must be in boot-*.tar.gz pkg).
dtbfile_name=meson-g12b-gtking-pro.dtb

# Ophub repo (dir.) with u-boot.bin files (for use as chainloader u-boot.ext).
ophub_repo_url="https://github.com/ophub"
ophub_uboot_url=${ophub_repo_url}"/amlogic-s9xxx-armbian/raw/main/build-armbian/u-boot/amlogic/overload"

# u-boot.bins from Ophub's repo for use as chainloader (u-boot.ext).
uboot_list=(
    "u-boot-e900v22c.bin" "u-boot-gtking.bin" "u-boot-gtkingpro-rev-a.bin"
    "u-boot-gtkingpro.bin" "u-boot-n1.bin" "u-boot-odroid-n2.bin"
    "u-boot-p201.bin" "u-boot-p212.bin" "u-boot-r3300l.bin" "u-boot-s905.bin"
    "u-boot-s905x-s912.bin" "u-boot-s905x2-s922.bin" "u-boot-sei510.bin"
    "u-boot-sei610.bin" "u-boot-skyworth-lb2004.bin" "u-boot-tx3-bz.bin"
    "u-boot-tx3-qz.bin" "u-boot-u200.bin" "u-boot-ugoos-x3.bin"
    "u-boot-x96max.bin" "u-boot-x96maxplus.bin" "u-boot-zyxq.bin"
)

# Official Ubuntu rootfs tarball.
distro_release="$(tr [A-Z] [a-z] <<< "$distro_edition")" # To lowercase.
distro_urlbase="https://cdimage.ubuntu.com/ubuntu-base"
# At cdimage.ubuntu.com, three different formats for URLs seem to be used:
# (1) Daily build of a development edition (e.g. Lunar).
# (2) Release build of a non LTS release (e.g. Kinetic).
# (3) Daily build of an LTS release (e.g. Focal, Jammy).
case "$distro_release" in
    "lunar")
        distro_buildfile=ubuntu-base-23.04-base-arm64.tar.gz
        distro_urlbase=$distro_urlbase/releases
        distro_buildurl=${distro_urlbase}/lunar/release/${distro_buildfile}
    ;;
    "kinetic")
        distro_buildfile=ubuntu-base-22.10-base-arm64.tar.gz
        distro_urlbase=$distro_urlbase/releases
        distro_buildurl=${distro_urlbase}/kinetic/release/${distro_buildfile}
    ;;
    "focal" | "jammy")
        distro_buildfile=${distro_release}-base-arm64.tar.gz
        distro_urlbase=$distro_urlbase/${distro_release}
        distro_buildurl=${distro_urlbase}/daily/current/${distro_buildfile}
    ;;
    *)
        echo "The distro release $distro_release is unknown, exiting."
        exit 1
    ;;
esac

# Link to g12_sound.sh for enabling sound on some boxes (run as local user).
g12_sound_url="https://gitlab.manjaro.org/manjaro-arm/packages/community/oc4-post-install/-/raw/master/g12_sound.sh"

# The string root=UUID=${rootfs_UUID} will be prepended below once UUID exists.
kernel_cmdline_opts="rootdelay=5 rootflags=data=writeback rw console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 loglevel=1"

# File system sizes and types (unit MiB).
# - The partition table type on the image is MBR.
# - The min skip (gap) size (before 1st part) is 1MB (2048 sectors, 512B each).
# - The boot fs type is vfat/fat32 and the root fs type is one of {ext4,btrfs}.
# Note: The boot fs is only for u-boot formatted copies of kernel +initramfs.
gap_MiB=2
boot_MiB=200
root_MiB=5000
rootfs_type=ext4
bootfs_label=UBNT_BOOT
rootfs_label=UBNT_ROOT

# These two parameters define the kernel memory load address and starting point,
# respectively, for u-boot. They are used in the script mkuimg.bash below to
# create uImage from Image. The values must be adapted to the box/SoC. For e.g
# some Amlogic s922x SoC (GT King pro, Ugoos AM6) both values are 0x1080000
# see https://linux-meson.com/howto.html
# and also https://www.kernel.org/doc/html/latest/arm64/booting.html
# Note: When booting mainline (kernel.org) kernel using uImage there is a
# warning about the kernel being misaligned at boot (when using these values).
k_load_addr=0x1080000
k_entry_addr=0x1080000

# Location (dir) of disk image container during install (for size, see below).
imgfile_dir=$PWD
tmpfile_dir=${imgfile_dir}/temp_files

# Location of local kernel package files (sub-tarballs, see notes above).
krnfile_dir=${imgfile_dir}/my_kernel

# Temporary mount points (dirs) used during image creation.
rootfs_mnt=${imgfile_dir}/rootfs_tmp
bootfs_dir=/boot/aux
bootfs_mnt=${rootfs_mnt}/${bootfs_dir}

# Do we want to clean up all temporary files and directories afterwards?
docleanup_after=yes # {yes,no}

# Some (but not all) commands used below to create the image.
reqd_cmdlist=("blkid" "dd" "losetup" "mkfs.vfat" "mkimage" "systemd-nspawn"
              "tar" "xz" "wget"
)

reqd_cmdlist_virt=("qemu-aarch64-static")

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

if [[ "$rootfs_type" == "ext4" ]]; then
    reqd_cmdlist=("${reqd_cmdlist[@]}" "mkfs.ext4")
elif [[ "$rootfs_type" == "btrfs" ]]; then
    reqd_cmdlist=("${reqd_cmdlist[@]}" "mkfs.btrfs")
else
    echo -e ${e_msg}" The fstype for the rootfs must be one of ext4 or btrfs, exiting."
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

# Full kernel command line (goes into uEnv.ini, extlinux.conf and grub.cfg).
kernel_cmdline="root=UUID=${rootfs_UUID} "${kernel_cmdline_opts}

# ------------------------------- here-docs ----------------------------------

# Below we add also a line for the vfat boot partition.
# (For swap we only add a stub, see https://help.ubuntu.com/community/SwapFaq)
fstab_file=$(cat <<EOF
UUID=$rootfs_UUID  /  $rootfs_type   errors=remount-ro  0  1
#/swapfile        none  swap        defaults  0  0
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
flashk_block_file=$(cat <<"EOF"
Package: flash-kernel
Pin: release *
Pin-Priority: -1
EOF
)

# If you want to add packages (to the default below), this is where to do it.
# To add the generic (ARM64) kernel add: apt -y install linux-image-generic
# (The double quotes around the limit string EOF prevents command substitution.)
ubuntu_custom_extra=$(cat <<"EOF"
apt-get -y install nano less aptitude usbutils zram-tools sudo linux-firmware
# To be able to boot with old (e.g. vendor/resident) u-boot we can use gzip
# compression instead for the initramfs (which, however, will become bigger).
sed -i 's/COMPRESS=zstd/COMPRESS=gzip/g' /etc/initramfs-tools/initramfs.conf
EOF
)

# This is the basic (default) set of packages installed on top of the rootfs.
# (If you want to add packages, edit the here-doc ubuntu_custom_extra above.)
ubuntu_custom_inst=$(cat <<EOF
#!/bin/bash

apt-get update
apt-get -y install apt-utils
DEBIAN_FRONTEND=noninteractive apt-get -y install man-db kmod grub2-common network-manager ssh initramfs-tools u-boot-tools
DEBIAN_FRONTEND=noninteractive apt-get -y install dialog locales keyboard-configuration kbd
DEBIAN_FRONTEND=noninteractive $ubuntu_custom_extra
dpkg-reconfigure tzdata
dpkg-reconfigure keyboard-configuration
echo "Set password for \033[91mroot:\033[0m"
until passwd; do echo "Try again."; done
echo "Setting up boot (2 items):"
echo "(1) Creating /boot/grub/grub.cfg"
/usr/local/bin/mkgrubcfg_simple.bash
echo "(2) Creating uImage, uInitrd on boot partition (from vmlinuz, uInitrd)."
/usr/local/bin/mkbootlinux.bash ${krnver_str} ${bootfs_dir} >/dev/null
EOF
)

aml_autoscript=$(cat <<"EOF"
# Standard aml_autoscript to set u-boot boot order: mmc/SD, USB, emmc
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
# Standard s905_autoscript to set u-boot execution steps for SD and USB.
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

# This is not used for ordinary SD/USB install (only here for advanced users).
emmc_autoscript=$(cat <<"EOF"
# Standard emmc_autoscript to set u-boot execution steps for emmc.
# Sourced from Manjaro ARM.
# Recompile with mkimage -A arm -O linux -T script -C none -d emmc_autoscript.txt emmc_autoscript
# Performs the same actions as under step (2) in s905_autoscript but for emmc (i.e. only for devtype mmc and devnum 1).
setenv env_addr 0x1040000
setenv initrd_addr 0x13000000
setenv boot_start 'bootm ${loadaddr} ${initrd_addr} ${dtb_mem_addr}'
setenv addmac 'if printenv mac; then setenv bootargs ${bootargs} mac=${mac}; elif printenv eth_mac; then setenv bootargs ${bootargs} mac=${eth_mac}; fi'
setenv try_boot_start 'if fatload ${devtype} ${devnum} ${loadaddr} uImage; then if fatload ${devtype} ${devnum} ${initrd_addr} uInitrd; then fatload ${devtype} ${devnum} ${env_addr} uEnv.ini && env import -t ${env_addr} ${filesize} && run addmac; fatload ${devtype} ${devnum} ${dtb_mem_addr} ${dtb_name} && run boot_start; fi;fi'
setenv devtype mmc
setenv devnum 1
run try_boot_start
EOF
)

uEnv=$(cat <<EOF
dtb_name=/$dtbfile_name
bootargs=$kernel_cmdline
EOF
)

extlinux_conf=$(cat <<EOF
# This file has two uses, for old and new resident/vendor u-boot, respectively:
# (1) For old vendor u-boot (which does not know about extlinux.conf) a
#     chainloader u-boot.ext (with newer u-boot code) can be used which reads
#     and parses this file, and loads the kernel, initramfs and dtb acordingly.
# (2) Newer vendor u-boot should be able to read, parse and use this file
#     directly.
#
# For more info about extlinux.conf see (and the links therein)
# https://wiki.syslinux.org/wiki/index.php?title=SYSLINUX
# (Note: u-boot's parsing of this file may be slightly different/incomplete.)
# Note also that the versions of u-boot (e.g. in a chainloader) that can read
# and parse this file can also (most likely) use several other formats for
# kernel and initrfamfs, such as Image/zImage, vmlinuz and initrd.img
#
# For an assortment of chainloaders u-boot.ext suitable for TV-boxes, see
# https://github.com/ophub/amlogic-s9xxx-armbian).

MENU TITLE <UBUNTU-BOOT>
DEFAULT UBNT_DEFAULT

# Timeout is in units of 0.1s (to wait before boot of default entry below).
TIMEOUT 10

LABEL UBNT_DEFAULT
  LINUX  /uImage
  INITRD /uInitrd
  FDT    /$dtbfile_name
  APPEND $kernel_cmdline
EOF
)

README_uboot=$(cat <<"EOF"
The files in this directory are intended to be used as chainloader when booting
via this method. (The default boot methods are grub.cfg and boot script.)
Usage: Find a binary here (u-boot-*) which matches your box and copy it to the
name u-boot.ext at the top level on the boot (fat) partition. Then edit the
file extlinux/extlinux.conf according to the instructions inside that file.
EOF
)

mkgrubcfg=$(cat <<EOF
#!/bin/bash

# Wrapper around grub-mkconfig with /boot/grub as destination directory.
# Tailored to (i.e. command line arguments) for ophub/flippy/unifreq kernels.
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
# Usage: /usr/local/bin/mkgrubcfg_simple.bash

distro_name_=$distro_name
distro_edition_=$distro_edition
kernel_cmdline_="$kernel_cmdline"
dtbfile_name_=$dtbfile_name

EOF
)

mkgrubcfg_simple_p2=$(cat <<"EOF1"

cd /boot
if [[ -f grub/grub.cfg ]]; then
    mv grub/grub.cfg grub/grub.cfg.bak
fi

for kernel_version in $(ls | grep -E "vmlinuz-" | cut -b 9-) ; do
    kernel_name=vmlinuz-${kernel_version}
    initrd_name=initrd.img-${kernel_version}

    kernel_path=/boot/$kernel_name
    initrd_path=/boot/$initrd_name
    echo "Adding entry: $distro_name_ $distro_edition_ (kernel $kernel_version)"
    # Note: The leading tabs in the here-document below are important.
	cat <<-EOF >> grub/grub.cfg
	menuentry "$distro_name_ $distro_edition_ (kernel $kernel_version)" {
	
	linux  $kernel_path $kernel_cmdline_
	initrd $initrd_path
	# devicetree /boot/dtbs/amlogic/${dtbfile_name_} # not used currently
	
	}
	
	EOF
done
EOF1
)

mkgrubcfg_simple="${mkgrubcfg_simple_p1}""${mkgrubcfg_simple_p2}"

mkuimg_p1=$(cat <<EOF
#!/bin/bash

# Takes an ARM64 kernel Image and produces a u-boot tagged uImage from it.
# Usage: /usr/local/bin/mkuimg /path/to/Image /path/to/uImage

# Note: ARM64 vmlinuz kernels are often in fact in (uncompressed) Image format.

# To make also a uInitrd from a initrd.img do like so
# mkimage -A arm64 -O linux -T ramdisk -C gzip -d initrd.img uInitrd
# (assuming that initrd.img is gzip compressed).

# The values for -a (load address) and -e (entry point) may need to be adapted.
# For some s922x (e.g. GTK pro, AM6) std. values for -a,-e are 0x1080000
# see https://linux-meson.com/howto.html
# and also https://www.kernel.org/doc/html/latest/arm64/booting.html

k_load_addr_=$k_load_addr
k_entry_addr_=$k_entry_addr

EOF
)

mkuimg_p2=$(cat <<"EOF"

if [[ -f $2 ]]; then
    mv $2 ${2}.bak
fi

mkimage -n "uImage" -A arm64 -O linux -T kernel -C none \
    -a $k_load_addr_ -e $k_entry_addr_ -d $1 $2
EOF
)

mkuimg="${mkuimg_p1}""${mkuimg_p2}"

mkuird=$(cat <<"EOF"
#!/bin/bash

# Takes an ARM64 initrd.img and produces a u-boot tagged uImage from it.
# Usage: /usr/local/bin/mkuimg /path/to/initrd.img /path/to/uImage

if [[ -f $2 ]]; then
    mv $2 ${2}.bak
fi

mkimage -n "uInitrd" -A arm64 -O linux -T ramdisk -C gzip -d ${1} ${2}

EOF
)

mkbootlinux=$(cat <<"EOF"
#!/bin/bash

# Produces an uImage and uInitrd on the fat boot partition from flippy's
# kernel and initramfs.
# Usage: /usr/local/bin/mkbootlinux kernel_release /path/to/bootpart/mount
# where kernel_release is e.g. 5.19.9-flippy-76+
# and /path/to/bootpart/mount is e.g. /boot/aux (and is mounted).

if [[ -f ${2}/uImage ]]; then
    mv ${2}/uImage ${2}/uImage.bak
fi

/usr/local/bin/mkuimg.bash /boot/vmlinuz-${1} ${2}/uImage

if [[ -f ${2}/uInitrd ]]; then
    mv ${2}/uInitrd ${2}/uInitrd.bak
fi

cp /boot/uInitrd-${1} ${2}/uInitrd
EOF
)

README_auxbootldr=$(cat <<"EOF"
It is easy to install Petitboot or u-root on this bootfs. With any of these two
bootloaders/bootmanagers you can boot "generic" UEFI+grub (and more generally
images with a valid grub config). If this image is installed on SD (so that it
is first in the boot chain, as defined by aml_autoscript), the bootloader will
start and scan the SD and other attached USB devices for bootable configurations
which can be conveniently selected and booted via a text based UI. For more
info on such "bootdisk" booting, see https://gitlab.com/tripole-inc/bootdisk

To install e.g. Petitboot on this bootfs (same for u-root), do the following:

(1) Download the latest tarball with Petitboot in the non chainloaded version,
    e.g. petit-bootdisk-nc_0v24.tgz
(2) Unpack the tarball in some temporary directory.
(3) Copy the existing Image and uInitrd on the bootfs to some backup location.
(4) Copy the Image (or zImage; it is an Image) from the tarball to Image on the
    bootfs and copy the uInitrd from the tarball to uInitrd on the bootfs.
(5) Make a uImage from Image/zImage using the script /usr/local/bin/mkuimg.bash
(6) Reboot into Petitboot.

(The procedure is similar when starting Petitboot via chainloader u-boot.ext
check the scripts and structure in e.g. petit-bootdisk-0v24.tgz)

To boot this disk image with u-boot requires a working resident/vendor u-boot
bootloader but this restriction can be removed if a "hidden" bootloader, i.e.
u-boot, is installed in the gap leading up to the first partition. With such a
bootloader properly installed, the disk will always boot from SD or USB on
Amlogic devices, regardless of the state of the resident/vendor u-boot. More
inforomation about this can be found in README_diy-bootdisk.md at Gitlab.
EOF
)

README_altbootscr=$(cat <<"EOF"
The boot scripts on the bootfs (aml_autoscript, s905_autoscript and uEnv.ini)
are sourced from Manjaro ARM but this is certainly not the only setup possible.
Another setup (with aml_autoscript, s905_autoscript, boot.scr), with somewhat
different logic, can be found (along with some comments and explanations) at
https://github.com/FauthD/amlogic-u-boot-scripts
Yet another setup is the scripts used on Ophub's images
https://github.com/ophub/amlogic-s9xxx-armbian
EOF
)

README_altkernels=$(cat <<"EOF"
There is no mechanism implemented for automatically updating the kernel (unless
the Ubuntu kernel is used, see below). However, updating the kernel manually is
easy since Ophub provides tarballs with kernels (and pre built initramfs) from
several branches at https://github.com/ophub/amlogic-s9xxx-armbian
The Ubuntu kernel can also be installed in the usual way via e.g. apt or
aptitude (the package name is linux-image-generic).
There are also some Tripole builds of kernels (using kernel.org source)
available at
https://mega.nz/folder/GJNjjSAY#Zru4DqCa6hyYnnkGuw02Rw
EOF
)

README_initramfs=$(cat <<"EOF"
We have not imlemented any mechanism for automatic rebuilding of the initramfs
when the kernel is updated. (However, the ordinary triggers for rebuilding of
the initramfs when certain packages are updates is in place and should work as
usual.) The initramfs is simple to rebuild manually, however. For example, to
rebuild the initramfs to the running kernel do (as root):

update-initramfs -c -k $(uname -r)

If you also want to update uInitrd (and uImage) on the bootfs do (as root):

mkbootlinux.bash $(uname -r) /boot/aux
EOF
)

#----------------------------------- code -----------------------------------

cd $imgfile_dir

imgfile_loc=${imgfile_dir}/${imgfile_name}

# This is a rough estimate: We do not take into account temporary files etc.
imgfile_MiB=$((gap_MiB +boot_MiB +root_MiB))
desired_MiB=$((14*${imgfile_MiB}/10)) # Approx. space for imgfile +imgfile.xz

echo -e "\n\033[92m -- Making image for $distro_name $distro_edition with kernel $krnver_str -- \033[0m\n"

echo -e "The image container file will be at:"
echo $imgfile_loc

if [[ "$compressed_img" == "no" ]]; then
    required_MiB=$imgfile_MiB
else
    echo -e "\nThe finished (compressed) image file will be at:"
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

echo -e ${i_msg}" Downloading the root (base) file system tarball..."
wget -P $tmpfile_dir -nv $distro_buildurl
if [[ $? -ne 0 ]]; then
    echo -e ${e_msg}" Unable to download the rootfs tarball, exiting."
    exit 1
fi
echo -e ${k_msg}" Done."

echo -n -e ${i_msg}" Unpacking the root (base) file system tarball..."
tar -xf ${tmpfile_dir}/${distro_buildfile} -C $rootfs_mnt
sync
echo " Done."

# The fstab file (0644) in the base tarball only holds a single comment line.
echo -n -e ${i_msg}" Setting up the fstab file..."
echo -e "$fstab_file" >${rootfs_mnt}/etc/fstab
# There is no UUID on a fat partition but in fstab the serial number works.
bootfs_UUID=$(blkid -s UUID -o value ${loop_dev}p1)
fstab_lastline="UUID=${bootfs_UUID}  $bootfs_dir  vfat   defaults  0  2"
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

# To enable sound on some boxes, edit and run this script as local user.
echo -e ${i_msg}" Installing script at /usr/local/bin/g12_sound.sh ..."
wget -P $tmpfile_dir -nv $g12_sound_url
if [[ $? -ne 0 ]]; then
    echo -e ${w_msg}" Unable to download the scrip g12_sound.sh"
else
    cp ${tmpfile_dir}/g12_sound.sh ${rootfs_mnt}/usr/local/bin
    chmod 0755 ${rootfs_mnt}/usr/local/bin/g12_sound.sh
    echo -e ${k_msg}" Done."
fi

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

echo -n -e ${i_msg}" Installing scripts to create uImage and uInitrd on bootfs..."
echo -e "$mkuimg" >${rootfs_mnt}/usr/local/bin/mkuimg.bash
chmod 0755 ${rootfs_mnt}/usr/local/bin/mkuimg.bash
# mkuird.bash is not used on a standard Opbuntu install but good to have.
echo -e "$mkuird" >${rootfs_mnt}/usr/local/bin/mkuird.bash
chmod 0755 ${rootfs_mnt}/usr/local/bin/mkuird.bash
echo -e "$mkbootlinux" >${rootfs_mnt}/usr/local/bin/mkbootlinux.bash
chmod 0755 ${rootfs_mnt}/usr/local/bin/mkbootlinux.bash
echo " Done."

echo -n -e ${i_msg}" Saving kernel pkg. files to /var/cache/kernel.pkg ..."
opsave_dir=${rootfs_mnt}/var/cache/kernel.pkg
mkdir $opsave_dir
cp ${krnfile_dir}/boot-${krnver_str}.tar.gz $opsave_dir
cp ${krnfile_dir}/modules-${krnver_str}.tar.gz $opsave_dir
for socdtbs_name in ${socdtbs_list[*]}; do
    cp ${krnfile_dir}/dtb-${socdtbs_name}-${krnver_str}.tar.gz $opsave_dir
done
cp ${krnfile_dir}/head*-${krnver_str}.tar.gz $opsave_dir
echo " Done."

echo -n -e ${i_msg}" Installing kernel, initramfs, modules and dtb files..."
tar -xzf ${krnfile_dir}/boot-${krnver_str}.tar.gz -C ${rootfs_mnt}/boot
mkdir -p -m 0744 ${rootfs_mnt}/lib/modules
tar -xzf ${krnfile_dir}/modules-${krnver_str}.tar.gz -C ${rootfs_mnt}/lib/modules
for socdtbs_name in ${socdtbs_list[*]}; do
    mkdir -p -m 0755 ${rootfs_mnt}/boot/dtbs/${socdtbs_name}
    tar -xzf ${krnfile_dir}/dtb-${socdtbs_name}-${krnver_str}.tar.gz -C ${rootfs_mnt}/boot/dtbs/${socdtbs_name}
done
echo " Done."

# The flash-kernel package causes problems on systems w/o flash storage (when
# installing Ubuntu kernels) so it is good to block to aviod future problems.
echo -n -e ${i_msg}" Preventing apt from installing the package flash-kernel..."
echo -e "$flashk_block_file" >${rootfs_mnt}/etc/apt/preferences.d/no-flash-kernel
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

echo -e ${i_msg}" Entering chroot jail. Installing some pkgs., running some scripts..."
systemd-nspawn -q --resolv-conf=copy-host --timezone=off -D ${rootfs_mnt} \
               /root/ubuntu_custom_inst.bash
rm ${rootfs_mnt}/root/ubuntu_custom_inst.bash
sleep 2 # Just to be able to read some of the messages.
echo "Done."

if [[ $arch_str != "aarch64" ]]; then
    echo -n -e ${i_msg}" Removing local qemu-aarch64-static binary..."
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

cd ${bootfs_mnt}

echo -n -e ${i_msg}" Setting up script files and dtb on boot partition..."
touch aml_autoscript.zip
echo -e "$aml_autoscript" >aml_autoscript.txt
echo -e "$s905_autoscript" >s905_autoscript.txt
echo -e "$emmc_autoscript" >emmc_autoscript.txt # Not used on std. SD/USB inst.
mkimage -A arm -O linux -T script -C none \
        -d aml_autoscript.txt aml_autoscript >/dev/null
mkimage -A arm -O linux -T script -C none \
        -d s905_autoscript.txt s905_autoscript >/dev/null
mkimage -A arm -O linux -T script -C none \
        -d emmc_autoscript.txt emmc_autoscript >/dev/null
echo -e "$uEnv" >uEnv.ini
dtbfile_loc=$(find ${rootfs_mnt}/boot/dtbs -name ${dtbfile_name})
if [[ -f $dtbfile_loc ]]; then
    cp $dtbfile_loc .
else
    echo -e ${e_msg}" Unable to find the dtb file ${dtbfile_name}, exiting."
    exit 1
fi
echo " Done."

# Only as a backup, in case vendor u-boot cannot boot via bootscripts.
echo -e ${i_msg}" Setting up backup boot method (chainloader)..."
mkdir extlinux
echo -e "$extlinux_conf" >extlinux/extlinux.conf
mkdir u-boot
echo -e "$README_uboot" >u-boot/README_u-boot.txt
have_all_uboots=yes
for uboot_bin in ${uboot_list[*]}; do
    uboot_bin_url=${ophub_uboot_url}/${uboot_bin}
    wget -nv -P u-boot $uboot_bin_url
    if [[ $? -ne 0 ]]; then
        echo -e ${w_msg}" Unable to download $uboot_bin"
        have_all_uboots=no
    fi
done
if [[ "$have_all_uboots" == "yes" ]] ; then
    echo -e ${k_msg}" Done."
else
    echo -e ${w_msg}" Could not download all u-boot.bin files."
fi

# A small sales pitch for the bootdisk.
echo -n -e ${i_msg}" Writing instructions for installing Petitboot/u-root..."
echo -e "$README_auxbootldr" >README_auxbootldr.txt
echo " Done."

# Some info about alternate boot scripts.
echo -n -e ${i_msg}" Writing instructions for alternate boot scripts..."
echo -e "$README_altbootscr" >README_altbootscr.txt
echo " Done."

# Some info about how to rebuild initramfs.
echo -n -e ${i_msg}" Writing instructions for rebuilding initramfs..."
echo -e "$README_initramfs" >README_initramfs.txt
echo " Done."

# Some info about alternate kernels.
echo -n -e ${i_msg}" Writing information about updating/alternate kernels..."
echo -e "$README_altkernels" >README_altkernels.txt
echo " Done."

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

if [[ "$compressed_img" == "yes" ]]; then
    echo -e ${i_msg}" Compressing the image using xz compression..."
    xz -v $imgfile_loc
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
