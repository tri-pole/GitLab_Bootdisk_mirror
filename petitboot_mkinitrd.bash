#!/bin/bash

# petitboot_mkinitrd.bash
# 23-10-12: v0.11
# Author: Tripole

# Script to compile and pack Petitboot for ARM64 in the form of an initramfs.

# Requirements: ARM64 build host with normal build environment (see below)
# where the user running the script must be in the sudo group.

# Tested on: Ubuntu Jammy and Debian Bookworm build hosts running in
# qemu-system-aarch64 on x86_64. (Cross compilation is not directly possible
# since some libs are copied from the build host to the initramfs, see below.)

# Dependencies: GNU build tools w/ compiler suite, installed dependencies for
# the packages kexec, busybox, iproute2, e2fsprogs, petitboot and eudev.
# For example, on a default installation of debian-12.8.0-arm64-netinst.iso
# all the dependencies could be satisfied by installing the following packages
# (which, in turn, will install additional packages so satisfy dependencies):
# build-essential, autoconf, pkg-config, bison, flex, gettext, libncurses-dev,
# libudev-dev, zlib1g-dev, liblzma-dev, libelf-dev, libdw-dev, libblkid-dev,
# libdevmapper-dev, libgpgme-dev, libssl-dev, gperf, gawk, tree, u-boot-tools

# Usage: The script can be run as an ordinary user but near the end it will ask
# for the user password to execute a sudo command to change ownership of the
# files in the initramfs. During execution of this script, two directories will
# be created in the same directory as this script; one result directory and one
# temporary file directory hearchy. (Near the end of this script you will be
# asked which of the temp dirs you want to delete.)

# Inspiration: https://www.raptorengineering.com/content/kb/1.html

# About the build: By default, the build config files etc. for each component
# are stored also in the resulting initramfs; search for build.tgz in the code
# below (these files are small, but you can omit them to save space).

# Things to note about Petitboot:
# - The dmidecode command is fake and is just a link to /sbin/sysinfo which is
#   a hacky shell script to extract info from /proc/device-tree. This script
#   may need tweaking for different platforms in order to correctly show the
#   Manufacturer, Model and Board data in the top margin of the Petitboot menu.
# - gpg (which is only needed for verifying signed or encrypted boot) is not
#   properly setup (missing certificates and libraries); for instructions, see
#   e.g. the notes at raptorengineering.com in the link above.
# - Some files (the libraries and gpg, cf. below) are just copied from the host.
# - Sometimes it is necessary to hit "Rescan devices" in Petitboot in order to
#   see all bootable devices attached.
# - There are two kernel command line options that can be used to control
#   autoboot and to lock Petitboot into a netns jail, see the init script below.
#   (With the patches applied to Petitboot the autoboot timeout is set to 60s.)

# Things to note about Busybox and other utils:
# - When entering the Busybox command line you will see an error message like
#   "can't access tty; job control turned off". This is due to the choice of
#   /dev/console which will be serial; thus cannot be a controlled tty, see e.g.
#   https://raw.githubusercontent.com/brgl/busybox/master/shell/cttyhack.c
# - The commands reboot, halt, poweroff are available in Busybox but must be
#   used with the -f flag (force; do not go through init).
# - The pb-discover process may interfere with some e2fsprogs such as e2fsck
#   (giving error messages about busy devices etc.) so it is advisable to first
#   kill pb-discover before e.g. attempting to repair file systems from the
#   Busybox shell.

# ToDo (feel free to pitch in here):
# - Figure out why the initial scan does not always detect all bootable devices.
#   Will further fiddling with udevd or udevadm e.g. with delays fix it
#   (e.g. in order to wait for USB devices)?
# - There seems to be an option for Petitboot named petitboot.debug that can
#   be passed via the kernel command line, what is it? Investigate...

# Final note: I'm aware (now, D'oh!) that the name of the program is a bit of a
# misnomer since the program creates an initramfs (file system), not an initrd
# (ramdisk). However, in bootloader contexts (e.g. u-boot) the two (initramfs
# and initrd) are often collectively referred to as "initrd".

# --------------------------------- Parameters -------------------------------

# If used, this tag  is inserted inside the header in the Petitboot main menu
# where it normally says e.g. Petitboot (v1.13) so that instead it will say
# something like Petitboot (v1.13 (mytaglinehere))
to_day=$(date +"%y%m%d")
mytag="3pole-${to_day}"
build_ver_tag="${mytag}"
# If the next line is set to true, the build_ver_tag is shown in the top
# margin in the Petitboot main menu (after the Petitboot version number)
# and the tag is also applied to the resulting initramfs(s) (see +100 lines).
use_build_ver_tag=true # {true_false}

# The initramfs can be built also in a smaller version where the e2fsprogs
# tools are omitted (file file system tools are still available in Busybox).
# (Note: The name tage format of the generated initrd is still the same though.)
no_e2fsprogs=false # {true,false}

# In the download parameter settings below the setting dload_<pkg>_tarball
# can be set to true or false. If set to false it is assumed that the 
# correctly named tarball is already placed in ${temp_dir}/downloads and if
# set to true it will be downloaded there.
kexectools_ver="2.0.29"
kexectools_url_base="https://github.com/horms/kexec-tools/archive/refs/tags"
kexectools_tarball_rpo=v${kexectools_ver}.tar.gz
kexectools_tarball_loc=kexectools-v${kexectools_ver}.tar.gz
dload_kexectools_tarball=true

busybox_ver="1.36.1"
busybox_url_base="https://busybox.net/downloads"
busybox_tarball_rpo=busybox-${busybox_ver}.tar.bz2
busybox_tarball_loc=busybox-v${busybox_ver}.tar.bz2
# busybox_bch=$(sed -e 's/\./_/g' <<< $busybox_ver)
# busybox_git_url="https://git.busybox.net/busybox"
dload_busybox_tarball=true

iproute2_ver="6.11.0"
iproute2_url_base="https://github.com/iproute2/iproute2/archive/refs/tags"
# iproute2_url_base="https://git.kernel.org/pub/scm/network/iproute2/iproute2.git/snapshot"
iproute2_tarball_rpo=v${iproute2_ver}.tar.gz
iproute2_tarball_loc=iproute2-$iproute2_tarball_rpo
dload_iproute2_tarball=true

e2fsprogs_ver="1.47.1"
e2fsprogs_url_base="https://github.com/tytso/e2fsprogs/archive/refs/tags"
e2fsprogs_tarball_rpo=v${e2fsprogs_ver}.tar.gz
e2fsprogs_tarball_loc=e2fsprogs-$e2fsprogs_tarball_rpo
dload_e2fsprogs_tarball=true

petitboot_ver="1.15"
petitboot_url_base="https://github.com/open-power/petitboot/releases/download"/v${petitboot_ver}
petitboot_tarball_rpo=petitboot-v${petitboot_ver}.tar.gz
petitboot_tarball_loc=$petitboot_tarball_rpo
dload_petitboot_tarball=true
pb_patch_dir="petitboot_patches" # Relative to dir of this script.
pb_1v13_add_grubcfg_path_patch_fname="pb_1v13_add_grubcfg_path_patch.patch"
pb_1v13_ui_and_bootcfg_patch_fname="pb_1v13_ui_and_bootcfg_patch.patch"

eudev_ver="3.2.14"
eudev_url_base="https://github.com/eudev-project/eudev/releases/download"/v${eudev_ver}
eudev_tarball_rpo=eudev-${eudev_ver}.tar.gz
eudev_tarball_loc=eudev-v${eudev_ver}.tar.gz
dload_eudev_tarball=true
eudev_udev_rules_list=("50-udev-default.rules" "60-autosuspend.rules"
                       "60-block.rules" "60-cdrom_id.rules" "60-drm.rules"
                       "60-evdev.rules" "60-fido-id.rules" "60-input-id.rules"
                       "60-persistent-input.rules" "60-persistent-storage.rules"
                       "60-serial.rules" "64-btrfs.rules" "64-btrfs.rules.in"
                       "70-memory.rules" "70-mouse.rules" "75-probe_mtd.rules")

# Libraries used by these executables will be copied from the host.
dyn_linked_exe_list_noe2fs=("/sbin/kexec"
                            "/usr/bin/udevd" "/usr/bin/udevadm" "/usr/bin/collect"
                            "/bin/ip" "/usr/sbin/pb-event" "/usr/sbin/pb-config"
                            "/usr/sbin/pb-discover" "/usr/sbin/petitboot-nc"
                            "/usr/bin/gpg" "/usr/lib/udev/scsi_id"
                            "/usr/lib/udev/ata_id" "/usr/lib/udev/cdrom_id"
                            "/usr/lib/udev/dmi_memory_id" "/usr/lib/udev/fido_id")
dyn_linked_exe_list_e2fs=("/sbin/mke2fs" "/sbin/e2fsck" "/sbin/badblocks"
                          "/sbin/tune2fs" "/sbin/resize2fs" "/sbin/dumpe2fs"
)
if [[ $no_e2fsprogs == true ]]; then
    dyn_linked_exe_list=${dyn_linked_exe_list_noe2fs[@]}
else
    dyn_linked_exe_list=(${dyn_linked_exe_list_noe2fs[@]}
                         ${dyn_linked_exe_list_e2fs[@]})
fi

stat_linked_exe_list=("/bin/busybox")

# Tag to be applied to the name of the resulting initrd (and the uInitrd).
if [[ $use_build_ver_tag == true ]]; then
    initrd_pb_tag=v${petitboot_ver}-${build_ver_tag}
else
    initrd_pb_tag=v${petitboot_ver}
fi
initrd_pb_name=initrd-petitboot-${initrd_pb_tag}
uInitrd_pb_name=uInitrd-petitboot-${initrd_pb_tag}


# Bling? Yes, we like.
i_msg="[\033[94m Info \033[0m]"
w_msg="[\033[93m Warning \033[0m]"
e_msg="[\033[91m Error \033[0m]"
k_msg="[\033[92m OK \033[0m]"

# ---------------------------------- Host info -------------------------------

host_info=$(uname -rsm)
os_info=$(cat /etc/os-release)
this_script_dir=$PWD
this_script=$(basename $0)

no_comp_cores=$(nproc)
if [[ $no_comp_cores -gt 1 ]]; then
    no_comp_cores=$(($no_comp_cores -1))
    else
    no_comp_cores=1
fi

# ---------------------------------- Here docs -------------------------------

README_petitboot_initrd=$(cat << EOF

This Petitboot initramfs is built with $this_script from

https://gitlab.com/tripole-inc/bootdisk

The following source versions have been used

kexec-tools: $kexectools_ver
Busybox:     $busybox_ver
iproute2:    $iproute2_ver
e2fsprogs:   $e2fspgrogs_ver (optional)
Petitboot:   $petitboot_ver
eudev:       $eudev_ver

to build the initramfs on a $host_info host running

$os_info

EOF
)

README_PB_Busybox=$(cat << EOF
Notes for Busybox $busybox_ver on Petitboot $petitboot_ver :

  When entering the Busybox command line you will see an error message like
  "can't access tty; job control turned off". This is due to the choice of
  /dev/console which will be serial; thus cannot be a controlled tty, see e.g.
  https://raw.githubusercontent.com/brgl/busybox/master/shell/cttyhack.c

  The commands reboot, halt, poweroff are available in Busybox but must be
  used with the -f flag (force; do not go through init).

  The pb-discover process may interfere with some e2fsprogs such as e2fsck
  (giving error messages about busy devices etc.) so it is advisable to first
  kill pb-discover before e.g. attempting to repair file systems from the
  Busybox shell.
EOF
)

etc_motd=$(cat << "EOF"
This is the Busybox shell. Standard UNIX/shell-isms apply.
Please see also /usr/share/busybox/README_PB_Busybox
EOF
)

etc_group=$(cat << "EOF"
root:x:0:
daemon:x:1:
tty:x:5:
disk:x:6:
lp:x:7:
kmem:x:15:
dialout:x:20:
cdrom:x:24:
tape:x:26:
audio:x:29:
video:x:44:
input:x:122:
EOF
)

etc_nsswitch_conf=$(cat << "EOF"
root:x:0:
daemon:x:1:
tty:x:5:
disk:x:6:
lp:x:7:
kmem:x:15:
dialout:x:20:
cdrom:x:24:
tape:x:26:
audio:x:29:
video:x:44:
input:x:122:
EOF
)

usr_share_udhcpc_default_script=$(cat << "EOF"
#!/bin/sh

/usr/share/udhcpc/simple.script "$@"
/usr/sbin/pb-udhcpc "$@"
EOF
)

init_script=$(cat << "EOF"
#!/bin/sh

# Adapted after Raptor Engineering's How-To note on Petitboot.
# 22-07-29, 23-10-07, Tripole

# This script can collect and use two arguments from the (trailing part of the)
# kernel command line; pb_no_autoboot and pb_nonet. If pb_no_autoboot=true
# the autoboot function is disabled and if pb_nonet=true then pb-discover is
# started in a netns network jail so that only the loopback interface works.

if [ "${pb_no_autoboot}" != "false"] && [ "${pb_no_autoboot}" != "true" ]; then
    pb_no_autoboot=false
fi
if [ "${pb_nonet}" != "false"] && [ "${pb_nonet}" != "true" ]; then
    pb_nonet=false
fi

/bin/busybox --install -s

CURRENT_TIMESTAMP=$(date '+%s')
if [ $CURRENT_TIMESTAMP -lt $(date '+%s') ] ; then
     date -s "@$(date '+%s')"
fi

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

echo 0 > /proc/sys/kernel/printk
clear

/usr/bin/udevd -d
sleep 1s
/usr/bin/udevadm hwdb --update
sleep 1s
/usr/bin/udevadm trigger

if [ "${pb_no_autoboot}" == "true" ]; then
   pb_discover_cmd="/usr/sbin/pb-discover -a"
else
   pb_discover_cmd="/usr/sbin/pb-discover"
fi

if [ "${pb_nonet}" == "true" ] ; then
    # Set up a network namespace to deny Petiboot access to external networks.
    /bin/ip netns add mininet
    /bin/ip netns exec mininet /bin/ip link set dev lo up
    /bin/ip netns exec mininet $pb_discover_cmd 2>/dev/null &
else
    $pb_discover_cmd 2>/dev/null &
fi

# This hack with a delay + some writing to the tty seems to be necessary for
# the ncurses menu/UI to come up correctly. Also, some time may be needed for
# pb-discover to detect all devices and read partitions properly.
echo -n "Starting Petitboot UI in ...3..."
sleep 1s
echo -n "2..."
sleep 1s
echo -n "1..."
sleep 1s

if [ "${pb_nonet}" == "true" ] ; then
    /bin/ip netns exec mininet /usr/sbin/petitboot-nc
else
    /usr/sbin/petitboot-nc
fi

if [ -e /etc/pb-lockdown ] ; then
    echo "Failed to launch petitboot, rebooting!"
    echo 1 > /proc/sys/kernel/sysrq
    echo b > /proc/sysrq-trigger
else
    echo "Failed to launch petitboot, dropping to a shell."
    exec sh
fi

EOF
)

# Bash does not support null characters '\0' (they will be mangled when a here
# doc is written to file). Therefore, we apply sed below to replace Q -> '\0'
sbin_sysinfo=$(cat << "EOF"
#!/bin/sh

# 22-07-29, 23-10-05, Tripole
# Hack to provide the most basic sysinfo from the device tree. (May well need
# to be adapted for other boxes. Easy to try out new hacks in Petitboot shell.)
# pb-discover queries /sbin/dmidecode with the following request specifiers:
# --string=system-manufacturer
# --string=system-product-name
# --string=system-uuid
# For Ugoos AM6, cat gives the following results (w/ null bytes in strings):
# /proc/device-tree/compatible :  "ugoos,am6\0amlogic,s922x\0amlogic,g12b"
# /proc/device-tree/name       :  <empty>
# /proc/device-tree/model      :  "Ugoos AM6" # With a \0 somewhere.

# Note: In the pipe filters below using tr we cannot use the null character \0
# explicity since Bash does not allow nulls inside strings (only at the end).

if [ "$1" == "--string=system-manufacturer" ] ; then
  sysmfg_str=$(tr [:cntrl:] ' ' </proc/device-tree/model | cut -d ' ' -f 1)
  echo "Manufacturer: "$sysmfg_str"  "
fi

if [ "$1" == "--string=system-product-name" ] ; then
  prodname_str=$(tr [:cntrl:] ' ' </proc/device-tree/model | cut -d ' ' -f 2)
  echo "Model: "$prodname_str"  "
fi

if [ "$1" == "--string=system-uuid" ] ; then
  board_str=$(tr [:cntrl:] ' ' </proc/device-tree/compatible | awk -F ' ' '{print $NF}')
  echo "Board: "$board_str"  "
fi
EOF
)

# --------------------------------- Functions -------------------------------

do_download() {
    bundle_name=$1
    bundle_pkg_url=$2
    bundle_pkg_loc=$3
    echo -e ${i_msg}" Downloading $bundle_name tarball from"
    echo "         $bundle_pkg_url"
    echo "         to local directory/name"
    echo "         $bundle_pkg_loc"
    wget $bundle_pkg_url -O $bundle_pkg_loc
    if [[ $? == 0 ]]; then
        echo -e ${k_msg}" Done. $bundle_name source tarball successfully downloaded."
    else
        echo -e ${e_msg}" Failed to download $bundle_name source, exiting."
        exit 1
    fi
}

# ------------------------------- Preliminaries -----------------------------

if [[ $no_e2fsprogs != true ]]; then
    echo -e ${i_msg}" -- Builting the Petitboot initramfs (with e2fsprogs) --"
else
    echo -e ${i_msg}" -- Builting the Petitboot initramfs (without e2fsprogs) --"
fi

echo -e -n ${i_msg}" Setting up initramfs directory structure ..."
result_dir=${PWD}/result
mkdir $result_dir
temp_dir=${PWD}/temp_files
mkdir ${temp_dir}
mkdir ${temp_dir}/downloads
mkdir ${temp_dir}/kexectools
mkdir ${temp_dir}/busybox
mkdir ${temp_dir}/iproute2
mkdir ${temp_dir}/e2fsprogs
mkdir ${temp_dir}/petitboot
mkdir ${temp_dir}/eudev
mkdir ${temp_dir}/initramfs
mkdir ${temp_dir}/initramfs/bin
mkdir ${temp_dir}/initramfs/etc
mkdir ${temp_dir}/initramfs/etc/netns
mkdir ${temp_dir}/initramfs/etc/netns/mininet
mkdir ${temp_dir}/initramfs/newroot
mkdir ${temp_dir}/initramfs/proc
mkdir ${temp_dir}/initramfs/run
mkdir ${temp_dir}/initramfs/run/udev
mkdir ${temp_dir}/initramfs/sbin
mkdir ${temp_dir}/initramfs/sys
mkdir ${temp_dir}/initramfs/tmp
mkdir ${temp_dir}/initramfs/usr
mkdir ${temp_dir}/initramfs/usr/bin
mkdir ${temp_dir}/initramfs/usr/lib
mkdir ${temp_dir}/initramfs/usr/lib/aarch64-linux-gnu
mkdir ${temp_dir}/initramfs/usr/lib/udev
mkdir ${temp_dir}/initramfs/usr/lib/udev/rules.d
mkdir ${temp_dir}/initramfs/usr/lib/terminfo
mkdir ${temp_dir}/initramfs/usr/sbin
mkdir ${temp_dir}/initramfs/usr/share
mkdir ${temp_dir}/initramfs/usr/share/kexectools
mkdir ${temp_dir}/initramfs/usr/share/busybox
mkdir ${temp_dir}/initramfs/usr/share/iproute2
mkdir ${temp_dir}/initramfs/usr/share/e2fsprogs
mkdir ${temp_dir}/initramfs/usr/share/petitboot
mkdir ${temp_dir}/initramfs/usr/share/eudev
mkdir ${temp_dir}/initramfs/usr/share/udhcpc
mkdir ${temp_dir}/initramfs/var
mkdir ${temp_dir}/initramfs/var/log
mkdir ${temp_dir}/initramfs/var/log/petitboot
mkdir ${temp_dir}/initramfs/var/run
mkdir ${temp_dir}/initramfs/var/run/netns
cd ${temp_dir}/initramfs
ln -s usr/lib lib
echo " Done."

echo -e -n ${i_msg}" Setting up init script in initramfs ..."
echo -e "$init_script" >${temp_dir}/initramfs/init
chmod +x ${temp_dir}/initramfs/init
echo " Done."

echo -e -n ${i_msg}" Setting up basic configuration files in initramfs tree ..."
echo -e "$etc_group" >${temp_dir}/initramfs/etc/group
touch ${temp_dir}/initramfs/etc/mdev.conf
echo -e "$etc_nsswitch_conf" >${temp_dir}/initramfs/etc/nsswitch.conf
echo -e "$usr_share_udhcpc_default_script" \
>${temp_dir}/initramfs/usr/share/udhcpc/default.script
chmod 0755 ${temp_dir}/initramfs/usr/share/udhcpc/default.script
echo " Done."

echo -e -n ${i_msg}" Setting up sysinfo script in initramfs tree ..."
cd ${temp_dir}/initramfs/sbin
echo -e "$sbin_sysinfo" >sysinfo
chmod +x sysinfo
ln -s sysinfo dmidecode
echo " Done."

echo -e -n ${i_msg}" Copying terminfo files and gpg to initramfs tree ..."
cp -R /usr/lib/terminfo/* ${temp_dir}/initramfs/usr/lib/terminfo
cp /usr/bin/gpg ${temp_dir}/initramfs/usr/bin
echo " Done."

# -------------------------------- Downloads --------------------------------

kexectools_pkg_url=${kexectools_url_base}/${kexectools_tarball_rpo}
kexectools_pkg_loc=${temp_dir}/downloads/${kexectools_tarball_loc}
if [[ "$dload_kexectools_tarball" == true ]]; then
    do_download "kexectools" $kexectools_pkg_url $kexectools_pkg_loc
fi

busybox_pkg_url=${busybox_url_base}/${busybox_tarball_rpo}
busybox_pkg_loc=${temp_dir}/downloads/${busybox_tarball_loc}
if [[ "$dload_busybox_tarball" == true ]]; then
    do_download "Busybox" $busybox_pkg_url $busybox_pkg_loc
fi

iproute2_pkg_url=${iproute2_url_base}/${iproute2_tarball_rpo}
iproute2_pkg_loc=${temp_dir}/downloads/${iproute2_tarball_loc}
if [[ "$dload_iproute2_tarball" == true ]]; then
    do_download "iproute2" $iproute2_pkg_url $iproute2_pkg_loc
fi

if [[ $no_e2fsprogs != true ]]; then
    e2fsprogs_pkg_url=${e2fsprogs_url_base}/${e2fsprogs_tarball_rpo}
    e2fsprogs_pkg_loc=${temp_dir}/downloads/${e2fsprogs_tarball_loc}
    if [[ "$dload_e2fsprogs_tarball" == true ]]; then
        do_download "e2fsprogs" $e2fsprogs_pkg_url $e2fsprogs_pkg_loc
    fi
fi

petitboot_pkg_url=${petitboot_url_base}/${petitboot_tarball_rpo}
petitboot_pkg_loc=${temp_dir}/downloads/${petitboot_tarball_loc}
if [[ "$dload_petitboot_tarball" == true ]]; then
    do_download "Petitboot" $petitboot_pkg_url $petitboot_pkg_loc
fi

eudev_pkg_url=${eudev_url_base}/${eudev_tarball_rpo}
eudev_pkg_loc=${temp_dir}/downloads/${eudev_tarball_loc}
if [[ "$dload_eudev_tarball" == true ]]; then
    do_download "eudev" $eudev_pkg_url $eudev_pkg_loc
fi

# ---------------------------------- Build ---------------------------------

echo -e ${i_msg}" Building kexec-tools ..."
tar -xf ${temp_dir}/downloads/${kexectools_tarball_loc} -C ${temp_dir}/kexectools
cd ${temp_dir}/kexectools/kexec-tools-${kexectools_ver}
autoupdate
./bootstrap
./configure --prefix=/usr
make -j $no_comp_cores
tar -czf ${temp_dir}/initramfs/usr/share/kexectools/build.tgz config.log configure.ac Makefile
echo -e -n ${i_msg}" Installing kexec binary to initramfs tree..."
strip ./build/sbin/kexec -o ${temp_dir}/initramfs/sbin/kexec
echo " Done."
echo -e ${k_msg}" Finished building and installing kexec-tools."

echo -e ${i_msg}" Building Busybox ..."
tar -xjf ${temp_dir}/downloads/${busybox_tarball_loc} -C ${temp_dir}/busybox
cd ${temp_dir}/busybox/busybox-${busybox_ver}
make defconfig
# We will compile a separate iproute2.
sed -i 's/CONFIG_IPROUTE=y/\# CONFIG_IPROUTE is not set/g' .config
if [[ $no_e2fsprogs != true ]]; then
    sed -i 's/CONFIG_MKE2FS=y/\# CONFIG_MKE2FS is not set/g' .config
fi
# make menuconfig
LDFLAGS=--static make -j $no_comp_cores
cp .config dot_config
tar -czf ${temp_dir}/initramfs/usr/share/busybox/build.tgz dot_config Makefile
echo -e -n ${i_msg}" Installing Busybox binary to initramfs tree..."
cp ./busybox ${temp_dir}/initramfs/bin # This is the stripped version.
cp ./examples/udhcp/simple.script ${temp_dir}/initramfs/usr/share/udhcpc/
# chown 0755 ${temp_dir}/initramfs/usr/share/udhcpc/simple.script
cd ${temp_dir}/initramfs/bin
ln -s busybox sh
cd ${temp_dir}/initramfs/sbin
ln -s /bin/ip ip # Petitboot (in default config.h) expects this.
echo " Done."
echo -e ${k_msg}" Finished building and installing Busybox."

echo -e -n ${i_msg}" Writing Busybox notes/README to /usr/share/busybox ..."
echo -e "$README_PB_Busybox" \
    >${temp_dir}/initramfs/usr/share/busybox/README_PB_Busybox.txt
echo " Done."
echo -e -n ${i_msg}" Writing /etc/motd ..."
echo -e "$etc_motd" >${temp_dir}/initramfs/etc/motd
chmod 0644 ${temp_dir}/initramfs/etc/motd
echo " Done."

echo -e ${i_msg}" Building iproute2 (ip command)..."
tar -xf ${temp_dir}/downloads/${iproute2_tarball_loc} -C ${temp_dir}/iproute2
cd ${temp_dir}/iproute2/iproute2-${iproute2_ver}
./configure --prefix=/usr
make -j $no_comp_cores
tar -czf ${temp_dir}/initramfs/usr/share/iproute2/build.tgz config.mk Makefile
echo -e -n ${i_msg}" Installing iproute2 (ip) binary to initramfs tree ..."
strip ./ip/ip -o ${temp_dir}/initramfs/bin/ip
echo " Done."
echo -e ${k_msg}" Finished building and installing iproute2 (ip command)."

if [[ $no_e2fsprogs != true ]]; then
    echo -e ${i_msg}" Building e2fsprogs ..."
    tar -xf ${temp_dir}/downloads/${e2fsprogs_tarball_loc} -C ${temp_dir}/e2fsprogs
    cd ${temp_dir}/e2fsprogs/e2fsprogs-${e2fsprogs_ver}
    mkdir build
    cd ./build
    ../configure --prefix=/usr
    make -j $no_comp_cores
    tar -czf ${temp_dir}/initramfs/usr/share/e2fsprogs/build.tgz config.log Makefile
    echo -e -n ${i_msg}" Installing e2fsprogs binaries to initramfs tree ..."
    strip ./misc/badblocks -o ${temp_dir}/initramfs/sbin/badblocks
    strip ./misc/dumpe2fs -o ${temp_dir}/initramfs/sbin/dumpe2fs
    strip ./misc/tune2fs -o ${temp_dir}/initramfs/sbin/tune2fs
    strip ./misc/mke2fs -o ${temp_dir}/initramfs/sbin/mke2fs
    strip ./e2fsck/e2fsck -o ${temp_dir}/initramfs/sbin/e2fsck
    strip ./resize/resize2fs -o ${temp_dir}/initramfs/sbin/resize2fs
    echo " Done."
    echo -e ${k_msg}" Finished building and installing e2fsprogs."
fi

echo -e ${i_msg}" Building Petitboot ..."
tar -xf ${temp_dir}/downloads/${petitboot_tarball_loc} -C ${temp_dir}/petitboot
cd ${temp_dir}/petitboot/petitboot-v${petitboot_ver}
echo -e ${i_msg}" Applying Petitboot patches ..."
pb_patches_applied_ok=true
case "$petitboot_ver" in
    "1.13" | "1.14" | "1.15")
        patch -N -p1 --ignore-whitespace <\
          ${this_script_dir}/${pb_patch_dir}/${pb_1v13_add_grubcfg_path_patch_fname}
        if [[ "$?" != 0 ]]; then
            pb_patches_applied_ok=false
        fi
        patch -N -p1 --ignore-whitespace <\
          ${this_script_dir}/${pb_patch_dir}/${pb_1v13_ui_and_bootcfg_patch_fname}
        if [[ "$?" != 0 ]]; then
            pb_patches_applied_ok=false
        fi
    ;;
    *)
        echo " (No patches available for version $petitboot_ver of Petitboot.)"
    ;;
esac
if [[ $pb_patches_applied_ok == true ]]; then
   echo -e ${k_msg}" All Petitboot patches applied successfully."
else
   echo -e ${w_msg}" Not all Petitboot patches applied successfully, check messages."
fi

if [[ $use_build_ver_tag == true ]]; then
    ./configure PACKAGE_VERSION="${petitboot_ver} [${build_ver_tag}]" \
      --prefix=/usr --enable-busybox --with-ncurses --without-twin-x11 \
      --without-twin-fbdev --with-signed-boot
else
    ./configure --prefix=/usr --enable-busybox --with-ncurses --without-twin-x11 \
      --without-twin-fbdev --with-signed-boot
fi
make -j $no_comp_cores
tar -czf ${temp_dir}/initramfs/usr/share/petitboot/build.tgz config.log Makefile
echo -e -n ${i_msg}" Installing Petitboot executable files to initramfs tree..."
strip ./utils/pb-config -o ${temp_dir}/initramfs/usr/sbin/pb-config
cp ./utils/pb-console ${temp_dir}/initramfs/usr/sbin
chmod +x ${temp_dir}/initramfs/usr/sbin/pb-console
strip ./discover/pb-discover -o ${temp_dir}/initramfs/usr/sbin/pb-discover
strip ./utils/pb-event -o ${temp_dir}/initramfs/usr/sbin/pb-event
cp ./utils/pb-exec ${temp_dir}/initramfs/usr/sbin
cp ./utils/pb-plugin ${temp_dir}/initramfs/usr/sbin
cp ./utils/pb-sos ${temp_dir}/initramfs/usr/sbin
cp ./utils/pb-udhcpc ${temp_dir}/initramfs/usr/sbin
chmod +x ${temp_dir}/initramfs/usr/sbin/pb-udhcpc
strip ./ui/ncurses/petitboot-nc -o ${temp_dir}/initramfs/usr/sbin/petitboot-nc
cp ./utils/scsi-rescan ${temp_dir}/initramfs/usr/sbin
cp ./utils/bb-kexec-reboot ${temp_dir}/initramfs/usr/share/petitboot
cp ./utils/hooks/{01,20,90}-* ${temp_dir}/initramfs/usr/share/petitboot
echo " Done."
echo -e ${k_msg}" Finished building and installing Petitboot."

echo -e -n ${i_msg}" Writing buildinfo README to /usr/share/petitboot ..."
echo -e "$README_petitboot_initrd" \
  >${temp_dir}/initramfs/usr/share/petitboot/README_petitboot_initrd.txt
echo " Done."

echo -e ${i_msg}" Building eudev ..."
tar -xf ${temp_dir}/downloads/${eudev_tarball_loc} -C ${temp_dir}/eudev
cd ${temp_dir}/eudev/eudev-${eudev_ver}
mkdir build
cd ./build
../configure --prefix=/usr --enable-blkid --disable-kmod
make -j $no_comp_cores
tar -czf ${temp_dir}/initramfs/usr/share/eudev/build.tgz config.log Makefile
echo -e ${i_msg}" Installing eudev binaries and udev rules to initramfs tree ..."
strip ./src/udev/udevadm -o ${temp_dir}/initramfs/usr/bin/udevadm
strip ./src/udev/udevd -o ${temp_dir}/initramfs/usr/bin/udevd
strip ./src/collect/collect -o ${temp_dir}/initramfs/usr/bin/collect
for id_item in ata_id cdrom_id dmi_memory_id fido_id scsi_id; do
    strip ./src/${id_item}/${id_item} -o ${temp_dir}/initramfs/usr/lib/udev/${id_item}
done
for udev_rule_item in ${eudev_udev_rules_list[@]}; do
    cp -v ../rules/${udev_rule_item} \
        ${temp_dir}/initramfs/usr/lib/udev/rules.d
done
echo " Done."
echo -e ${k_msg}" Finished building and installing eudev."

# ----------------------------- Find and copy libs ---------------------------

echo -e ${i_msg}" Finding and listing all libraries required by the executables:"
lib_file_list=()
pre_path=${temp_dir}/initramfs
for exe_name in ${dyn_linked_exe_list[@]}; do
    exe_name_full=${pre_path}${exe_name}
    # libs_this_exe=$(objdump -p $exe_name_full | grep "NEEDED" | sed 's/NEEDED//g' | tr -d " ") # Note reliable
    # The next line is perhaps not reliable, but for now it will do.
    # The virtual (kernel) file linux-vdso.so.1 and the linker
    # ld-linux-aarch64.so.1 are omitted from the list.
    libs_this_exe=$(ldd $exe_name_full | grep -vE "linux-vdso.so.1|ld-linux-aarch64.so.1" | cut -d "(" -f1 | cut -d ">" -f2 | tr -d ' ')
    echo "Libs (except virtual) required by ${exe_name}:"
    echo $libs_this_exe
    lib_file_list+=($libs_this_exe)
done

lib_file_list_sorted=$(echo "${lib_file_list[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')
echo -e ${i_msg}" Libraries (generic form, i.e. symlink name) needed by the executables:"
for list_item in ${lib_file_list_sorted[@]}; do
    echo $list_item
done

echo -e ${i_msg}" Libraries (actual installed name/version) provided to the executables:"
lib_file_inst_list=()
for list_item in ${lib_file_list_sorted[@]}; do
    lib_file_inst_full=$(realpath $(whereis $list_item | cut -d " " -f2))
    lib_file_inst_list+=($lib_file_inst_full)
    echo $lib_file_inst_full
done

echo -e ${i_msg}" Copying libraries from host to initramfs tree ..."
cp /usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 ${temp_dir}/initramfs/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1
cd ${temp_dir}/initramfs/usr/lib
ln -s aarch64-linux-gnu/ld-linux-aarch64.so.1 ld-linux-aarch64.so.1
for list_item in ${lib_file_inst_list[@]}; do
    lib_file_inst_full=$(realpath $list_item)
    cp -v ${lib_file_inst_full} ${temp_dir}/initramfs${lib_file_inst_full}
done
echo " Done."

echo -e ${i_msg}" Running ldconfig for the libraries in the initramfs tree."
ldconfig -vr ${temp_dir}/initramfs
echo -e ${k_msg}" Finished with libraries."

# ------------------------------- Packing it up ------------------------------

echo -e ${i_msg}" Packing up the initramfs tree into a gzipped cpio archive..."
cd ${temp_dir}/initramfs
my_username=$(whoami)
echo "Enter your password to change ownership (root) of files in initramfs tree:"
sudo chown -R root:root ${temp_dir}/initramfs && \
  find . | cpio -H newc -o | gzip -c > ../${initrd_pb_name} && \
  chown $my_username:$my_username ../${initrd_pb_name}
echo " Done."
echo "Result: ${initrd_pb_name}"
mv ${temp_dir}/${initrd_pb_name} $result_dir

which_mkimage=$(which mkimage)${temp_dir}
test_which_mkimage=$?
if [[ $test_which_mkimage == 0 ]]; then
    echo -e -n "Making u-boot tagged version of the initramfs ..."
    mkimage -n "Petitboot-v${petitboot_ver}" -A arm64 -O linux -T ramdisk \
      -C gzip -d ${result_dir}/${initrd_pb_name} ${result_dir}/${uInitrd_pb_name}
    echo " Done."
    echo "Result: ${uInitrd_pb_name}"
fi

echo " Done."
cd $this_script_dir
echo -e ${k_msg}" Finished building and packing the Petitboot initramfs."

cd ${temp_dir}/
tree initramfs >${result_dir}/initramfs_file_tree.txt

# Typically the sudo cache timeout is 5m or so so this is not needed:
# echo "Enter your password to change back ownership (you) of initramfs tree:"
my_user=$(whoami)
sudo chown -R $my_user:$my_user ${temp_dir}/initramfs

# ---------------------------------- Cleanup ---------------------------------

echo -n "Do you want to delete the build directories?   [n/Y] >"
read do_del_pkgblddirs
if [[ "$do_del_pkgblddirs" != "n" ]]; then
    rm -rf ${temp_dir}/{kexec,busybox,iproute2,e2fsprogs,petitboot,}
fi

echo -n "Do you want to delete the download directory?  [n/Y] >"
read do_del_downloads
if [[ "$do_del_pkgblddirs" != "n" ]]; then
    rm -rf ${temp_dir}/downloads
fi

echo -n "Do you want to delete the initramfs file tree? [n/Y] >"
read do_del_initramfsdir
if [[ "$do_del_initramfsdir" != "n" ]]; then
    echo "Enter your password to delete the initramfs dir (owned by root):"
    sudo rm -rf ${temp_dir}/initramfs
fi

echo -e ${k_msg}" Finished ${this_script} (Output files in ./result)"
