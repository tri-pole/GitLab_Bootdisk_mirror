#!/bin/bash

# ubuntu_mkimg.bash (a.k.a. {opbuntu,flibuntu}_mkimg.bash)
# 22-09-24: v0.16
# Author: Tripole

# Script to generate an Ubuntu ARM64 (CLI, "server") image with a custom kernel
# (flippy/unifreq) for Amlogic TV-boxes/SBCs. The Ubuntu system is based on
# daily builds of the rootfs of the latest LTS release 22.04 Jammy (or Focal).
# The script must be executed (as root) on an Ubuntu/Debian type machine,
# either natively on aarch64/ARM64 (e.g. Ubuntu Server Live booted via
# bootdisk) or virtualized (using qemu-aarch64-static) on x86_64/amd64.
# The generated image can be booted with resident/vendor u-boot (using the boot
# scripts on the fat partition) or via bootdisk (using the grub.cfg file on the
# rootfs partition). Another alternative is chainloader u-boot.ext (included).

# Tested on: Ugoos AM6 plus (s922x, for executing, booting and running) and on
# QEMU (qemu-system-x86_64 and qemu-system-aarch64, for developing/executing).
# Tested kernels: 5.15.70-flippy-77+, 5.19.10-flippy-77+, 5.15.0-48-generic
# This script is a template or proof-of-concept, nothing more (so please fork
# it, improve it).

# Requires: Standard basic functionality incl. blkid, dd, losetup, mkfs, xz,
# wget and the package systemd-container (for systemd-nspawn). ArchLinux wiki:
# "systemd-nspawn is like the chroot command, but it is a chroot on steroids."
# Most of the requirements are checked at runtime below. For "cross-scripting"
# (i.e. use on another architecture than aarch64) you need to install the
# package qemu-user-static (which recommends the package binfmt-support); this
# provides the required binary qemu-aarch64-static

# Typical usage: Edit the parameters below and run the script from a temp dir.
# (the image as well as all temporary files will be created in this dir.).

# Inspiration taken from
# https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/rebuild
# https://github.com/manjaro-arm/am6-plus-images/releases

# Notes:
# - The Ubuntu rootfs comes in a "minimized" state (see e.g. Ubuntu Wiki) for
#   most packages and therefore it is advisable to run the command unminimize
#   (and reboot) to restore the system into normal state at the first boot.
#   More generally, the system is "bare-bones", so e.g. no swap is set up.
# - During installation, on some terminals the keyboard and console font
#   configuration will be deferred and you will see a message about this.
#   (You can always later manually do dpkg-reconfigure keyboard-configuration)
# - On some boxes, when booting from USB using vendor u-boot and the boot
#   scripts, only the image stick can be attached to the USB bus. When booting
#   using a chainloader (u-boot.ext) it should not be a problem to have other
#   (non bootable) USB sticks attached. When using grub booting (e.g. with a
#   bootdisk on SD) having other USB sticks attached is not a problem.
# - The uImage and uInitrd (u-boot tagged) versions of the kernel and initramfs
#   that are on the fat partition are created by the mkbootlinux.bash script
#   (see below). Therefore, when updating the kernel or initramfs then uImage
#   uInitrd have to be recreated "manually" using this script (unless you rely
#   on grub booting, then only grub.cfg on the rootfs partition has to be
#   updated; see the scripts in /usr/local/bin). (The boot partition is not
#   mounted by default in /etc/fstab but it can be by uncommenting one line.)
# - A simple working desktop can be obtained by installing e.g. xubuntu-core
#   (with e.g. lightdm, chosen at install time) or ubuntu-desktop-minimal (gdm).
#   Another alternative is kubuntu-desktop.
# - On some boxes it is necessary to run (as user) the script g12_sound.sh
#   to get sound working. (Afterwards, check for soundcards with e.g. aplay -L)
# - The standard Ubuntu kernel linux-image-generic can also be installed (after
#   unminizing). It is then recommended to first install the dependency
#   package linux-firmware (ca 900M) and then the package linux-image-generic.
#   (This is to avoid problems with the package linux-firmware not being fully
#   configured which can apparently happen otherwise.) The installation scripts
#   for linux-image-generic will automatically generate a new valid grub.cfg
#   which will include also an entry for the ophub/flippy/unifreq kernel
#   (albeit without the desired kernel command line parameters).
# - Run time for this script is less than 10m on a modern computer with good
#   network connectivity. (Try this to check: time ./ubuntu_mkimg.bash)
# - Pro tip: Generate the image cheaply, say 1G rootfs (so that burn to SD/USB
#   goes quickly). Then, (before first boot) enlarge the rootfs partition on
#   SD/USB to desired size, e.g. with (100% here uses all of the SD/USB):
#   parted /dev/sdX resizepart 2 50% ; e2fsck -f /dev/sdX2 ; resize2fs /dev/sdX2

# ------------------------------- parameters ---------------------------------

distro_name=Ubuntu   # Used for the image name and in grub.cfg
distro_edition=Jammy # Tested with Jammy, Focal

# Host name for image.
host_name=opbu

# Compression (xz) takes some extra time.
compressed_img=no # {yes,no}

# Ophub kernel version (number), e.g. 5.19.10
ophub_kvers="5.19.10"

# Name string as in grub entries etc. w/ spec. chars. (e.g. 5.19.10-flippy-77+).
ophub_krel=${ophub_kvers}"-flippy-77+" # Kernel name/release string, plain text.
# For a list of encodings, see https://en.wikipedia.org/wiki/Percent-encoding
ophub_krel_url=${ophub_kvers}"-flippy-77%2B" # Name string URL encoded.

# Edit the image tag to your liking.
img_tag=${ophub_krel}_3pole-$(date +"%y%m%d")
imgfile_name=${distro_name}_${distro_edition}_${img_tag}.img

# Ophub repo w/ builds of flippy/unifreq kernels (incl. initramfs, thx. Ophub).
ophub_repo_url="https://github.com/ophub"
ophub_krepo_url=${ophub_repo_url}/kernel/raw/main/pub/stable
ophub_kboot_url=${ophub_krepo_url}/${ophub_kvers}/boot-${ophub_krel_url}.tar.gz
ophub_kmods_url=${ophub_krepo_url}/${ophub_kvers}/modules-${ophub_krel_url}.tar.gz
ophub_kdtbs_url=${ophub_krepo_url}/${ophub_kvers}/dtb-amlogic-${ophub_krel_url}.tar.gz

# Ophub repo (dir.) with u-boot.bin files (for use as chainloader u-boot.ext).
ophub_uboot_url=${ophub_repo_url}"/amlogic-s9xxx-armbian/blob/main/build-armbian/amlogic-u-boot/overload"

# u-boot.bins from Ophub's repo for use as chainloader (u-boot.ext).
uboot_list=("u-boot-e900v22c.bin" "u-boot-gtking.bin"
    "u-boot-gtkingpro-rev-a.bin" "u-boot-gtkingpro.bin" "u-boot-n1.bin"
    "u-boot-odroid-n2.bin" "u-boot-p201.bin" "u-boot-p212.bin"
    "u-boot-s905.bin" "u-boot-s905x-s912.bin" "u-boot-s905x2-s922.bin"
    "u-boot-sei510.bin" "u-boot-sei610.bin" "u-boot-tx3-bz.bin"
    "u-boot-tx3-qz.bin" "u-boot-u200.bin" "u-boot-ugoos-x3.bin"
    "u-boot-x96max.bin" "u-boot-x96maxplus.bin" "u-boot-zyxq.bin"
)

# Official Ubuntu rootfs tarball.
distro_release="$(tr [A-Z] [a-z] <<< "$distro_edition")" # To lowercase.
distro_urlbase="https://cdimage.ubuntu.com/ubuntu-base"/${distro_release}
distro_relstr=daily/current
distro_buildfile=${distro_release}-base-arm64.tar.gz
distro_buildurl=${distro_urlbase}/${distro_relstr}/${distro_buildfile}

# Link to g12_sound.sh for enabling sound on some boxes (run as local user).
g12_sound_url="https://gitlab.manjaro.org/manjaro-arm/packages/community/oc4-post-install/-/raw/master/g12_sound.sh"

# The string root=UUID=${rootfs_UUID} will be prepended below once UUID exists.
kernel_cmdline_opts="rootdelay=5 rootflags=data=writeback rw console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 loglevel=1"

# This is the dtb file name pointed to in uEnv.ini
dtbfile_name=meson-g12b-ugoos-am6.dtb

# File system sizes and types (unit MiB).
# - The partition table type on the image is MBR.
# - The min skip (gap) size (before 1st part) is 1MB (2048 sectors, 512B each).
# - The boot fs type is vfat/fat32 and the root fs type is one of {ext4,btrfs}.
# Note: The boot fs is only for u-boot formatted copies of kernel +initramfs.
skip_MB=1
boot_MB=150
root_MB=1000
rootfs_type=ext4
bootfs_label=UBNT_BOOT
rootfs_label=UBNT_ROOT

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
fstab_file=$(cat <<EOF
UUID=$rootfs_UUID  /  $rootfs_type   errors=remount-ro  0  1
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
apt-get -y install nano less aptitude usbutils
EOF
)

# This is the basic (default) set of packages installed on top of the rootfs.
# (If you want to add packages, edit the here-doc ubuntu_custom_extra above.)
ubuntu_custom_inst=$(cat <<EOF
apt-get update
apt-get -y install apt-utils
DEBIAN_FRONTEND=noninteractive apt-get -y install man-db kmod grub2-common network-manager ssh u-boot-tools
DEBIAN_FRONTEND=noninteractive apt-get -y install dialog locales keyboard-configuration kbd
DEBIAN_FRONTEND=noninteractive $ubuntu_custom_extra
dpkg-reconfigure tzdata
dpkg-reconfigure keyboard-configuration
echo "Set password for \033[91mroot:\033[0m"
until passwd; do echo "Try again."; done
echo "Setting up boot (2 items):"
echo "(1) Creating /boot/grub/grub.cfg"
/usr/local/bin/mkgrubcfg_simple.bash
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
	# devicetree /dtbs/amlogic/${dtbfile_name_} # not used currently
	
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

# Note: ARM64 vmlinuz kernels (e.g. flippy's) are often in fact in Image format.

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

mkbootlinux=$(cat <<"EOF"
#!/bin/bash

# Produces an uImage and uInitrd on the fat boot partition from flippy's
# kernel and initramfs.
# Usage: /usr/local/bin/mkbootlinux kernel_release /path/to/mounted_bootpart
# where kernel_release is e.g. 5.19.9-flippy-76+
# and /path/to/bootpart/mount is e.g. /boot/aux (and is mounted).

/usr/local/bin/mkuimg.bash /boot/vmlinuz-${1} ${2}/uImage
cp /boot/uInitrd-${1} ${2}/uInitrd

EOF
)

README_auxbootldr=$(cat <<EOF
It is easy to install Petitboot or u-root on this bootfs. With any of these two
bootloaders/bootmanagers you can boot "generic" UEFI+grub (and more generally
images with a valid grub config). If this image is installed on SD (so that it
is first in the boot chain, as defined by aml_autoscript), the bootloader will
start and scan the SD and other attached USB devices for bootable configurations
which can be conveniently selected and booted via a text based UI. For more
info on such "bootdisk" booting, see https://gitlab.com/tripole-inc/bootdisk

To install e.g. Petitboot on this bootfs (same for u-root), do the following:

(1) Download the latest tarball with Petitboot in the non chainloaded version,
    e.g. petit-bootdisk-nc_0v22-2.tgz
(2) Unpack the tarball in some temporary directory.
(3) Copy the existing Image and uInitrd on the bootfs to some backup location.
(4) Copy the Image (or zImage; it is an Image) from the tarball to Image on the
    bootfs and copy the uInitrd from the tarball to uInitrd on the bootfs.
(5) Reboot into Petitboot.
EOF
)
	      
#----------------------------------- code -----------------------------------

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
cd $tmpfile_dir && wget -nv $distro_buildurl
if [[ $? -ne 0 ]]; then
    echo -e ${i_msg}" Unable to download the rootfs tarball, exiting."
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

# To enable sound on some boxes, edit and run this script as local user.
echo -e ${i_msg}" Installing script at /usr/local/bin/g12_sound.sh ..."
cd $tmpfile_dir && wget -nv $g12_sound_url
if [[ $? -ne 0 ]]; then
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

echo -e ${i_msg}" Installing scripts to create uImage and uInitrd on bootfs..."
echo -e "$mkuimg" >${rootfs_mnt}/usr/local/bin/mkuimg.bash
chmod 0755 ${rootfs_mnt}/usr/local/bin/mkuimg.bash
echo -e "$mkbootlinux" >${rootfs_mnt}/usr/local/bin/mkbootlinux.bash
chmod 0755 ${rootfs_mnt}/usr/local/bin/mkbootlinux.bash
echo " Done."

echo -e ${i_msg}" Downloading Ophub/Flippy/Unifreq kernel..."
cd $tmpfile_dir && wget -nv $ophub_kboot_url
if [[ $? -ne 0 ]]; then
    echo -e ${i_msg}" Unable to download the kernel boot files, exiting."
    exit 1
fi
wget -nv $ophub_kmods_url
if [[ $? -ne 0 ]]; then
    echo -e ${i_msg}" Unable to download the kernel modules, exiting."
    exit 1
fi
wget -nv $ophub_kdtbs_url
if [[ $? -ne 0 ]]; then
    echo -e ${i_msg}" Unable to download the dtb files, exiting."
    exit 1
fi
echo " Done."

echo -n -e ${i_msg}" Installing Ophub/Flippy/Unifreq kernel..."
cd ${rootfs_mnt}/boot
tar -xzf ${tmpfile_dir}/boot-${ophub_krel}.tar.gz
mkdir -p -m 0744 ${rootfs_mnt}/lib/modules
cd ${rootfs_mnt}/lib/modules
tar -xzf ${tmpfile_dir}/modules-${ophub_krel}.tar.gz
mkdir -p -m 0755 ${rootfs_mnt}/boot/dtbs/amlogic
cd ${rootfs_mnt}/boot/dtbs/amlogic
tar -xzf ${tmpfile_dir}/dtb-amlogic-${ophub_krel}.tar.gz
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
