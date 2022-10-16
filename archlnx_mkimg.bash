#!/bin/bash

# archlnx_mkimg.bash
# 22-10-16: v0.1
# Author: Tripole

# Script to generate an Arch Linux ARM64 (CLI, "server") image using the
# offical pre built tarball with rootfs (and kernel) from Arch Linux ARM.
# The script must be executed (as root) on an Ubuntu/Debian type machine,
# either natively on aarch64/ARM64 (e.g. Ubuntu Server Live booted via
# bootdisk) or virtualized (using qemu-aarch64-static) on x86_64/amd64.
# The generated image can be booted with resident/vendor u-boot (using the boot
# scripts on the fat partition) or via bootdisk (using the grub.cfg file on the
# rootfs partition). Another alternative is chainloader u-boot.ext (included).

# Tested on: Ugoos AM6 plus (s922x, for executing, booting and running) and on
# QEMU (qemu-system-x86_64 and qemu-system-aarch64, for developing/executing).

# Requires: Standard basic functionality incl. blkid, dd, losetup, mkfs, xz,
# wget and the package systemd-container (for systemd-nspawn). ArchLinux wiki:
# "systemd-nspawn is like the chroot command, but it is a chroot on steroids."
# For Arch Linux we also need the program bsdtar, which in Ubuntu is packaged
# in the package libarchive-tools. If you want to use the Arch Linux keyring
# to verify the rootfs tarball you must install the keyring, e.g. like so:
# gpg --keyserver keyserver.ubuntu.com \
# --recv-keys 68B3537F39A313B3E574D06777193F152BDBE6A6
# and manually verify the tarball like so:
# gpg --verify ArchLinuxARM-aarch64-latest.tar.gz.sig
# wget http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz{,.sig}
# For more info, see the Arch Linux Wiki at the link below.
# Most of the requirements are checked at runtime below. For "cross-scripting"
# (i.e. use on another architecture than aarch64) you need to install the
# package qemu-user-static (which recommends the package binfmt-support); this
# provides the required binary qemu-aarch64-static

# Typical usage: Edit the parameters below and run the script from a temp dir.
# (the image as well as all temporary files will be created in this dir.).

# Inspiration taken from
# https://archlinuxarm.org/
# https://wiki.pine64.org/wiki/Installing_Arch_Linux_ARM_On_The_Pinebook_Pro

# Notes:
# - The root password is "root" and there is a default user "alarm" set up.
#   Therefore, on first boot (as root) change the passwords for root and alarm.
# - On some boxes, when booting from USB using vendor u-boot and the boot
#   scripts, only the image stick can be attached to the USB bus. When booting
#   using a chainloader (u-boot.ext) it should not be a problem to have other
#   (non bootable) USB sticks attached. When using grub booting (e.g. with a
#   bootdisk on SD) having other USB sticks attached is not a problem.
# - The dtb file is only used when booting via u-boot (not when booting via
#   grub, currently).
# - The uImage and uInitrd (u-boot tagged) versions of the kernel and initramfs
#   that are on the fat partition are created by the mkbootlinux.bash script
#   (see below). Therefore, when updating the kernel or initramfs then uImage
#   uInitrd have to be recreated "manually" using this script (unless you rely
#   on grub booting, then only grub.cfg on the rootfs partition has to be
#   updated; see the scripts in /usr/local/bin).
# - A desktop environment can be obtained by installing e.g. plasma-meta (for a
#   full KDE plasma desktop). You may have to install separately the KDE
#   terminal program konsole separately and you may have to enable the
#   installed display manager manually: systemctl enable sddm.service --now
#   More info about e.g. desktop environments can be found in Arch Linux's very
#   comprehensive Wiki at https://wiki.archlinux.org
# - On some boxes it is necessary to run (as user) the script g12_sound.sh to
#   get sound working. (Afterwards, check for soundcards with e.g. aplay -L)
# - Run time for this script is about 2m or less (on a modern computer with
#   good network connectivity). Try this to check: time ./ubuntu_mkimg.bash
# - Pro tip: Generate the image cheaply, say 2G rootfs (so that burn to SD/USB
#   goes quickly). Then, (before first boot) enlarge the rootfs partition on
#   SD/USB to desired size, e.g. with (100% here uses all of the SD/USB):
#   parted /dev/sdX resizepart 2 50% ; e2fsck -f /dev/sdX2 ; resize2fs /dev/sdX2

# ------------------------------- parameters ---------------------------------

distro_name=ArchLinux  # Used for the image name and in grub.cfg
distro_edition=current # Arch Linux ARM is a rolling release distro.

# Host name for image.
host_name=arch

# Compression (xz) takes some extra time.
compressed_img=yes # {yes,no}

# The official rootfs tarball from Arch Linux ARM also contains a kernel.
archlnx_repo_url="http://os.archlinuxarm.org/os"
distro_buildfile="ArchLinuxARM-aarch64-latest.tar.gz"
distro_buildurl=${archlnx_repo_url}/${distro_buildfile}

# Ophub repo (dir.) with u-boot.bin files (for use as chainloader u-boot.ext).
ophub_repo_url="https://github.com/ophub"
ophub_uboot_url=${ophub_repo_url}"/amlogic-s9xxx-armbian/raw/main/build-armbian/amlogic-u-boot/overload"

# u-boot.bins from Ophub's repo for use as chainloader (u-boot.ext).
uboot_list=("u-boot-e900v22c.bin" "u-boot-gtking.bin"
    "u-boot-gtkingpro-rev-a.bin" "u-boot-gtkingpro.bin" "u-boot-n1.bin"
    "u-boot-odroid-n2.bin" "u-boot-p201.bin" "u-boot-p212.bin"
    "u-boot-s905.bin" "u-boot-s905x-s912.bin" "u-boot-s905x2-s922.bin"
    "u-boot-sei510.bin" "u-boot-sei610.bin" "u-boot-tx3-bz.bin"
    "u-boot-tx3-qz.bin" "u-boot-u200.bin" "u-boot-ugoos-x3.bin"
    "u-boot-x96max.bin" "u-boot-x96maxplus.bin" "u-boot-zyxq.bin"
)

# Link to g12_sound.sh for enabling sound on some boxes (run as local user).
g12_sound_url="https://gitlab.manjaro.org/manjaro-arm/packages/community/oc4-post-install/-/raw/master/g12_sound.sh"

# The string root=UUID=${rootfs_UUID} will be prepended below once UUID exists.
kernel_cmdline_opts="rootdelay=5 rootflags=data=writeback rw"

# dtb name in uEnv.ini/extlinux.conf (dtb must be in Ophub's boot-*.tar.gz pkg).
#dtbfile_name=meson-g12b-ugoos-am6.dtb
dtbfile_name=meson-g12b-gtking-pro.dtb

# File system sizes and types (unit MiB).
# - The partition table type on the image is MBR.
# - The min skip (gap) size (before 1st part) is 1MB (2048 sectors, 512B each).
# - The boot fs type is vfat/fat32 and the root fs type is one of {ext4,btrfs}.
# Note: The boot fs is only for u-boot formatted copies of kernel +initramfs.
skip_MB=1
boot_MB=150
root_MB=5000
rootfs_type=ext4
bootfs_label=ARCH_BOOT
rootfs_label=ARCH_ROOT

# These to parameters define the kernel memory load address and starting point,
# respectively, for u-boot. They are used in the script mkuimg.bash below to
# create uImage from Image. The values must be adapted to the box/SoC. For e.g
# some Amlogic s922x SoC (GT King pro, Ugoos AM6) both values are 0x1080000
k_load_addr=0x1080000
k_entry_addr=0x1080000

# Location (dir) of disk image container during install (for size, see below).
imgfile_dir=$PWD
tmpfile_dir=${imgfile_dir}/temp_files

# Temporary mount points (dirs) used during image creation.
rootfs_mnt=${imgfile_dir}/rootfs_tmp
bootfs_dir=/boot/aux
bootfs_mnt=${rootfs_mnt}/${bootfs_dir}

# Name of the container file used during image creation. After completion the
# image is renamed and the kernel version is included in the name.
imgfile_name=${distro_name}_${distro_edition}.img

# The image tag is added to the final image name. Edit to taste.
img_tag=3pole-$(date +"%y%m%d")

# Do we want to clean up all temporary files and directories afterwards?
docleanup_after=yes # {yes,no}

# Only used during install.
name_server_1=1.1.1.1
name_server_2=8.8.8.8

# Some (but not all) commands used below to create the image.
reqd_cmdlist=("blkid" "bsdtar" "dd" "losetup" "mkfs.vfat" "mkimage"
              "systemd-nspawn" "tar" "xz" "wget"
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

hosts_file=$(cat <<EOF
# Static table lookup for hostnames.
# See hosts(5) for details.
127.0.0.1    localhost
::1          localhost
127.0.1.1    $host_name
EOF
)

resolver_file=$(cat <<EOF
nameserver $name_server_1
nameserver $name_server_2
EOF
)

# If you want to add packages (to the default below), this is where to do it.
# (The double quotes around the limit string EOF prevents command substitution.)
archlnx_custom_extra=$(cat <<"EOF"
pacman -S --noconfirm man-db pacman-contrib alsa-utils
EOF
)

# This is the basic (default) set of packages installed on top of the rootfs.
# (If you want to add packages, edit the here-doc ubuntu_custom_extra above.)
ubuntu_custom_inst=$(cat <<EOF
#!/bin/bash

pacman-key --init
pacman-key --populate archlinuxarm
pacman -Sy
pacman -S --noconfirm uboot-tools
# timedatectl list-timezones
timedatectl set-timezone America/New_York
# localectl list-keymaps
localectl set-keymap us
$archlnx_custom_extra
# echo "Set password for \033[91mroot:\033[0m"
# until passwd; do echo "Try again."; done
echo "Setting up boot (2 items):"
echo "(1) Creating /boot/grub/grub.cfg"
/usr/local/bin/mkgrubcfg_arch.bash
echo "(2) Creating uImage, uInitrd on boot partition (from vmlinuz, Initrd)."
/usr/local/bin/mkbootlinux.bash ${ophub_krel} ${bootfs_dir} >/dev/null
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
# This file is only to be used if resident/vendor u-boot cannot boot via boot
# scripts (aml_autoscript, s905_autoscript and uEnv.ini) and you still want
# to use u-boot for booting (rather than e.g. bootdisk +grub.cfg). Usage:
# (1) Rename the file to extlinux.conf
# (2) Edit the text below (if needed) to match your box and add a chainloader
#     as u-boot.ext (see e.g. https://github.com/ophub/amlogic-s9xxx-armbian).

# For more info about this file see (and the links therein)
# https://wiki.syslinux.org/wiki/index.php?title=SYSLINUX
# (Note: u-boot's parsing of this file may be slightly different/incomplete.)

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
file extlinux/extlinux.conf.bak according to the instructions inside that file.
EOF
)

# We split this file in two; one part with parameter substitution and one w/o.
mkgrubcfg_arch_p1=$(cat <<EOF
#!/bin/bash

# Produces a very elementary grub.cfg for Arch Linux ARM kernels.
# It is intended to be run when bootfs is mounted under /boot on rootfs but
# the entries in grub.cfg refer to the situation when a bootloader searches
# on bootfs for grub.cfg and the kernel and initramfs referenced therein.

distro_name_=$distro_name
distro_edition_=$distro_edition
kernel_cmdline_="$kernel_cmdline"
dtbfile_name_=$dtbfile_name

EOF
)

mkgrubcfg_arch_p2=$(cat <<"EOF1"

cd /boot
if [[ -f grub/grub.cfg ]]; then
    mv grub/grub.cfg grub/grub.cfg.bak
fi

    kernel_version=$(ls --format=single-column ${rootfs_mnt}/lib/modules)
    kernel_name=Image
    initrd_name=initramfs-linux.img

    kernel_path=/boot/$kernel_name
    initrd_path=/boot/$initrd_name
    echo "Adding entry: $distro_name_ $distro_edition_ (kernel $kernel_version)"
    # Note: The leading tabs in the here-document below are important.
	cat <<-EOF >> grub/grub.cfg
	menuentry "$distro_name_ $distro_edition_ (kernel $kernel_version)" {
	
	linux  $kernel_path $kernel_cmdline_
	initrd $initrd_path
	# devicetree /dtbs/amlogic/${dtbfile_name_} # not used currently
	
	}
	EOF

    kernel_name=Image
    initrd_name=initramfs-linux-fallback.img

    kernel_path=/boot/$kernel_name
    initrd_path=/boot/$initrd_name
    echo "Adding entry: $distro_name_ $distro_edition_ (kernel $kernel_version (fallback))"
    # Note: The leading tabs in the here-document below are important.
	cat <<-EOF >> grub/grub.cfg
	menuentry "$distro_name_ $distro_edition_ (kernel $kernel_version (fallback))" {
	
	linux  $kernel_path $kernel_cmdline_
	initrd $initrd_path
	# devicetree /dtbs/amlogic/${dtbfile_name_} # not used currently
	
	}
	EOF
EOF1
)

mkgrubcfg_arch="${mkgrubcfg_arch_p1}""${mkgrubcfg_arch_p2}"

mkuimg_p1=$(cat <<EOF
#!/bin/bash

# Takes an ARM64 kernel Image and produces a u-boot tagged uImage from it.
# Usage: /usr/local/bin/mkuimg /path/to/Image /path/to/uImage

# Note: ARM64 vmlinuz kernels are often in fact in Image format.

# The values for -a (load address) and -e (entry point) may need to be adapted.
# For some s922x (e.g. GTK pro, AM6) std. values for for -a,-e are 0x1080000

k_load_addr_=$k_load_addr
k_entry_addr_=$k_entry_addr

EOF
)

mkuimg_p2=$(cat <<"EOF"

mkimage -n "uImage" -A arm64 -O linux -T kernel -C none \
    -a $k_load_addr_ -e $k_entry_addr_ -d $1 $2
EOF
)

mkuimg="${mkuimg_p1}""${mkuimg_p2}"

mkuird=$(cat <<"EOF"
#!/bin/bash

# Takes an ARM64 initrd.img and produces a u-boot tagged uImage from it.
# Usage: /usr/local/bin/mkuimg /path/to/initrd.img /path/to/uImage

mkimage -n "uInitrd" -A arm64 -O linux -T ramdisk -C gzip -d ${1} ${2}

EOF
)

mkbootlinux=$(cat <<"EOF"
#!/bin/bash

# Produces an uImage and uInitrd on the bootfs partition from Arch Linux ARM
# kernel and initramfs.
# Usage: /usr/local/bin/mkbootlinux /path/to/mounted_bootpart
# where /path/to/bootpart/mount is e.g. /boot/aux (and it is mounted).

/usr/local/bin/mkuimg.bash /boot/Image ${1}/uImage
/usr/local/bin/mkuird.bash /boot/initramfs-linux.img ${1}/uInitrd
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
    Copy also the existing boot scripts aml_autoscript*, s905_autoscript* and
    uEnv.ini to some backup location.
(4) Copy the Image (or zImage; it is an Image) from the tarball to Image on the
    bootfs and copy the uInitrd from the tarball to uInitrd on the bootfs.
    Copy also the boot scripts aml_autoscript*, s905_autoscript, uEnv.txt and
    boot.scr from the tarball to the bootfs. Rename uEnv.txt to uEnv.ini
(5) Reboot into Petitboot.

(The procedure is similar when starting Petitboot via chainloader u-boot.ext
check the scripts and structure in e.g. petit-bootdisk-0v24.tgz)
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

mkbootlinux.bash /boot/aux

(This makes a uImage and uInitrd of the existing Image and initramfs-linux.img
and places them in /boot/aux where the bootfs should be mounted.)
EOF
)

#----------------------------------- code -----------------------------------

cd $imgfile_dir

imgfile_loc=${imgfile_dir}/${imgfile_name}

# This is a rough estimate: We do not take into account temporary files etc.
imgfile_MB=$((skip_MB +boot_MB +root_MB))
desired_MB=$((14*${imgfile_MB}/10)) # Approx. space for imgfile +imgfile.xz

echo -e "\n\033[92m -- Making image for $distro_name ($distro_edition) -- \033[0m\n"

echo -e "The image container file will be at:"
echo $imgfile_loc

if [[ "$compressed_img" == "no" ]]; then
    required_MB=$imgfile_MB
else
    required_MB=$desired_MB
fi

# The actual used space is smaller, but I don't know how to estimate that.
echo -e "\nMake sure that you have enough space: up to ~${required_MB} MB +some.\n"
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
    echo -e ${i_msg}" Unable to download the rootfs tarball, exiting."
    exit 1
fi
echo "Done."

echo -n -e ${i_msg}" Unpacking the root (base) file system tarball..."
bsdtar -xpf ${tmpfile_dir}/${distro_buildfile} -C $rootfs_mnt
sync
echo " Done."

# The fstab file (0644) in the base tarball only holds some placeholders.
echo -n -e ${i_msg}" Setting up the fstab file..."
echo -e "$fstab_file" >${rootfs_mnt}/etc/fstab
# There is no UUID on a fat partition but in fstab the serial number works.
bootfs_UUID=$(blkid -s UUID -o value ${loop_dev}p1)
fstab_lastline="UUID=${bootfs_UUID}  $bootfs_dir  vfat   defaults  0  2"
echo -e "$fstab_lastline" >>${rootfs_mnt}/etc/fstab
echo " Done."

# The hostname file (0644) in the base tarball reads alarm.
echo -n -e ${i_msg}" Setting the hostname in /etc/hostname ..."
echo -e "$host_name" >${rootfs_mnt}/etc/hostname
echo " Done."

# The hosts file (0644) in the base tarball only holds some placeholders.
echo -n -e ${i_msg}" Setting up local host mappings in /etc/hosts ..."
echo -e "$hosts_file" >${rootfs_mnt}/etc/hosts
echo " Done."

# After leaving the chroot jail below there will also be a leftover
# resolv.conf but it will be fixed automagically by systemd-resolved.service
if [[ -f ${rootfs_mnt}/etc/resolv.conf ]]; then
    echo -n -e ${i_msg}" Replacing pre installed /etc/resolv.conf ..."
    rm -f ${rootfs_mnt}/etc/resolv.conf
    echo -e "$resolver_file" >${rootfs_mnt}/etc/resolv.conf
    echo " Done."
fi

# To enable sound on some boxes, edit and run this script as local user.
echo -e ${i_msg}" Installing script at /usr/local/bin/g12_sound.sh ..."
wget -P $tmpfile_dir -nv $g12_sound_url
if [[ $? -ne 0 ]]; then
    echo -e ${w_msg}" Unable to download the scrip g12_sound.sh"
else
    cp ${tmpfile_dir}/g12_sound.sh ${rootfs_mnt}/usr/local/bin
    chmod 0755 ${rootfs_mnt}/usr/local/bin/g12_sound.sh
fi
echo "Done."

# Pick up the kernel version here since it is used shortly (e.g. in grub.cfg).
kernel_version=$(ls --format=single-column ${rootfs_mnt}/lib/modules)

echo -n -e ${i_msg}" Setting up directory /boot/grub ..."
mkdir -p -m 0755 ${rootfs_mnt}/boot/grub
echo " Done."

echo -n -e ${i_msg}" Installing grub scripts in /usr/local/bin ..."
# This script produces a basic grub.cfg file and works inside a loop device.
echo -e "$mkgrubcfg_arch" >${rootfs_mnt}/usr/local/bin/mkgrubcfg_arch.bash
chmod 0755 ${rootfs_mnt}/usr/local/bin/mkgrubcfg_arch.bash
echo " Done."

echo -n -e ${i_msg}" Installing scripts to create uImage and uInitrd on bootfs..."
echo -e "$mkuimg" >${rootfs_mnt}/usr/local/bin/mkuimg.bash
chmod 0755 ${rootfs_mnt}/usr/local/bin/mkuimg.bash
echo -e "$mkuird" >${rootfs_mnt}/usr/local/bin/mkuird.bash
chmod 0755 ${rootfs_mnt}/usr/local/bin/mkuird.bash
echo -e "$mkbootlinux" >${rootfs_mnt}/usr/local/bin/mkbootlinux.bash
chmod 0755 ${rootfs_mnt}/usr/local/bin/mkbootlinux.bash
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
systemd-nspawn -q --timezone=off -D ${rootfs_mnt} /root/ubuntu_custom_inst.bash
rm ${rootfs_mnt}/root/ubuntu_custom_inst.bash
sleep 2 # Just to be able to read some of the messages.
echo "Done."

if [[ $arch_str != "aarch64" ]]; then
    echo -n -e ${i_msg}" Removing local qemu-aarch64-static binary..."
    rm ${rootfs_mnt}/usr/bin/qemu-aarch64-static
    echo " Done."
fi

echo -n -e ${i_msg}" Restoring the symlink for /etc/resolv.conf..."
rm ${rootfs_mnt}/etc/resolv.conf
ln -s /run/systemd/resolve/resolv.conf ${rootfs_mnt}/etc/resolv.conf
echo " Done."

cd ${bootfs_mnt}

echo -n -e ${i_msg}" Setting up script files and dtb on boot partition..."
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
    uboot_bin_url=${ophub_uboot_url}/${uboot_bin}
    wget -nv -P u-boot $uboot_bin_url
    if [[ $? -ne 0 ]]; then
        echo -e ${w_msg}" Unable to download $uboot_bin"
    fi
done
echo "Done."

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
