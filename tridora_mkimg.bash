#!/bin/bash

# tridora_mkimg.bash
# 23-06-25: v0.1
# Author: Tripole

# Script to add a locally provided kernel to a recent Fedora ARM64 image.
# This can be useful since recent Fedora kernels (e.g. on 38 and onwards)
# cannot be booted using kexec(), and therefore not by Petitboot, but requires
# proper EFI support (and an updated grub bootloader). For instance, the
# koop-3pole kernels are bootable on recent Fedora images using Petitboot.

# Acknowledgement: The idea for this script came from a post by JFL on the
# Beelink forum describing how to manually install a Petitboot bootable kernel
# on recent Fedora ARM64 images (one example shown was a koop-3pole kernel).

# Notes:
# - The kernel files in the local kernel direectory (see below) should be the
#   same as the sub-tarballs found in Ophub's and Tripole's main tarball, like
#   boot-<krnver_str>-tar.gz ,
#   modules-<krnver_str>-tar.gz ,
#   header-<krnver_str>-tar.gz or headers-<krnver_str>-tar.gz ,
#   dtb-amlogic-<krnver_str>-tar.gz ,
#   dtb-allwinner-<krnver_str>-tar.gz ,
#   dtb-rockchip-<krnver_str>-tar.gz .
# - Fedora ARM64 images can be found here https://alt.fedoraproject.org/alt/
# - If you install manually another kernel you need to make also a new entry
#   for it in grub, in the Fedora way: You need to create a new text file in
#   /boot/loader/entries on the bootfs (partition 2) with a name like
#   <32randchardecnumber>-<kernelname>.aarch64.conf
#   with contents of the form (cf. existing entries in /boot/loader/entries)
#
#   title Fedora Linux (6.1.35-koop-3pole) 38 (Thirty Eight)
#   version 6.1.35-koop-3pole
#   linux /vmlinuz-6.1.35-koop-3pole
#   initrd /initramfs-6.1.35-koop-3pole.img
#   # devicetree /meson-g12b-gtking-pro.dtb # <- for now, this is commented out
#   options root=UUID=4d6b4931-164a-4c35-9a78-1ac5a17f4cfa rootdelay=5 rootflags=data=writeback rw console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 loglevel=1
#   grub_users $grub_users
#   grub_arg --unrestricted
#   grub_class fedora
#
#   Depending on the kernel you use, the kernel command line (options above)
#   may need to be changed. The UUID can be read from of the other grub entries.
#   To generate a random 32 character number for the file name you can e.g. do
#   $ tr -cd '[:digit:]' < /dev/urandom | fold -w 32 | head -n 1
# - The grub update method just described works with Petitboot but if you want
#   to use u-root (e.g. via u-root bootdisk) you must write a grub.cfg that
#   u-root understands with "simple" menu entries (listing kernel image,
#   initramfs and kernel command line; examples are easy to find by search).

# -------------------------------- Parameters ---------------------------------

# Name of the original Fedora ARM64 OS image without trailing .raw.xz
fedora_image="Fedora-Minimal-38-1.6.aarch64"
# fedora_image="Fedora-Workstation-38-1.6.aarch64"

# Fedora major release string (number as on Fedora ARM64 image, and w/ letters).
fedora_release="38 (Thirty Eight)" # Only used to tag grub loader entries.

# Kernel tag used in resulting disk image name (uncomment and edit to taste).
# Example for koop-3pole kernel.
krnver_str="6.1.35-koop-3pole" # Kernel name/release str., plain text.

# Keep the compressed (xz) original Fedora ARM64 image file?
keep_orig_img=yes # {yes,no}

# Recompression (xz) of the image file after adding kernel? (Takes extra time.)
compressed_img=yes # {yes,no}

# Do we want to remove temporary directories afterwards?
docleanup_after=yes # {yes,no}

# Typically we run this script from the same dir as the Fedora image file.
imgfile_dir=$PWD

rootfs_mnt=${imgfile_dir}/temp_mnt
bootfs_mnt=${rootfs_mnt}/boot # Do not edit this.

# Location of local kernel package files (sub-tarballs, see notes above).
krnfile_dir=${imgfile_dir}/my_kernel

# The string root=UUID=${rootfs_UUID} will be prepended once UUID is known.
kernel_cmdline_opts="rootdelay=5 rootflags=data=writeback rw console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 loglevel=1"

# List of names for the SoC vendors for which you wish to install the dtb
# package (the selected dtb below must be in one of these packages).
# Ophub packages dtbs for amlogic, allwinner and rockchip w/ his kernels.
# (The paths to the dtb packages (defined below) are of the form
# ${ophub_krepo_url}/dtb-${socdtbs_name}-${krnver_str_url}.tar.gz)
socdtbs_list=("amlogic" "allwinner" "rockchip")

# This is not really used now, only as a placeholder (see below).
dtbfile_name=meson-g12b-gtking-pro.dtb

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

arch_str=$(uname -m)
if [[ "$arch_str" != "aarch64" && "$arch_str" != "x86_64" ]]; then
    echo ${e_msg}" The architecture is not one of x86_64 or aarch64, exiting."
    exit 1
fi

# ---------------------------------- code ------------------------------------

cd $imgfile_dir

echo -e "\n\033[92m -- Installing kernel $krnver_str on image $fedora_image -- \033[0m\n"

echo -n -e ${i_msg}" Uncompressing the image file containing Fedora..."
if [[ "$keep_orig_img" == "yes" ]]; then
   unxz_sw="-kv"
   else
   unxz_sw="-v"
fi
unxz $unxz_sw ${imgfile_dir}/${fedora_image}.raw.xz
echo " Done."

echo -n -e ${i_msg}" Setting up a mount point for the image file rootfs..."
mkdir -p $rootfs_mnt
echo " Done."

echo -n -e ${i_msg}" Setting up loop device for (raw) image file..."
loop_dev=$(losetup -P -f --show ${imgfile_dir}/${fedora_image}.raw)
if [[ -z $loop_dev ]]; then
    echo -e "\n"${e_msg}" The command losetup ${fedora_image}.raw failed, exiting."
    exit 1
fi
echo " Done."

rootp_msg="\033[94mroot\033[0m"
echo -n -e ${i_msg}" Mounting the $rootp_msg partition inside the container file..."
mkdir -p $rootfs_mnt
if ! mount ${loop_dev}p3 $rootfs_mnt ; then
    echo -e ${e_msg}" The command mount ${loop_dev}p3 failed, exiting."
    exit 1
fi
sync
echo " Done."

bootp_msg="\033[94mboot\033[0m"
echo -n -e ${i_msg}" Mounting the $bootp_msg partition inside the container file..."
if ! mount ${loop_dev}p2 $bootfs_mnt ; then
    echo -e ${e_msg}" The command mount ${loop_dev}p2 failed, exiting."
    exit 1
fi
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
rm ${rootfs_mnt}/boot/uImage-${krnver_str}
rm ${rootfs_mnt}/boot/uInitrd-${krnver_str}
# We rename the initramfs to Fedora naming style (e.g. what dracut outputs).
# Rebuild the initramfs in Fedora with e.g. dracut --kver 6.1.35-koop-3pole
mv ${rootfs_mnt}/boot/initrd.img-${krnver_str} ${rootfs_mnt}/boot/initramfs-${krnver_str}.img 
mkdir -p -m 0744 ${rootfs_mnt}/lib/modules
tar -xzf ${krnfile_dir}/modules-${krnver_str}.tar.gz -C ${rootfs_mnt}/lib/modules
for socdtbs_name in ${socdtbs_list[*]}; do
    mkdir -p -m 0755 ${rootfs_mnt}/boot/dtb-${krnver_str}/${socdtbs_name}
    tar -xzf ${krnfile_dir}/dtb-${socdtbs_name}-${krnver_str}.tar.gz -C ${rootfs_mnt}/boot/dtb-${krnver_str}/${socdtbs_name}
done
echo " Done."

echo -n -e ${i_msg}" Adding grub entry (in /boot/loader/entries) for kernel..."
rootfs_UUID_tag=$(grep -E "/ " ${rootfs_mnt}/etc/fstab | cut -b -41)
# Yes, we like Stackexchange...
rnd_digits=$(tr -cd '[:digit:]' < /dev/urandom | fold -w 32 | head -n 1)
loader_entry_name=${rnd_digits}-${krnver_str}.aarch64.conf
loader_entry_p1=$(cat <<EOF
title Fedora Linux ($krnver_str) $fedora_release
version $krnver_str
linux /vmlinuz-${krnver_str}
initrd /initramfs-${krnver_str}.img
# devicetree /$dtbfile_name
options root=$rootfs_UUID_tag $kernel_cmdline_opts
EOF
)

loader_entry_p2=$(cat <<"EOF"

grub_users $grub_users
grub_arg --unrestricted
grub_class fedora
EOF
)

loader_entry="${loader_entry_p1}""${loader_entry_p2}"

echo -e "$loader_entry" >${rootfs_mnt}/boot/loader/entries/${loader_entry_name}
echo " Done."

echo -n -e ${i_msg}" Unmounting the container file..."
umount -f ${loop_dev}p2
sync && sleep 2
umount -f ${loop_dev}p3
sync && sleep 2
echo " Done."

echo -n -e ${i_msg}" Disconnecting and removing the loop devices..."
losetup -d $loop_dev 2>/dev/null
echo " Done."

echo -n -e ${i_msg}" Renaming the image to include added kernel name..."
mv ${imgfile_dir}/${fedora_image}.raw \
   ${imgfile_dir}/${fedora_image}_${krnver_str}_raw
echo " Done."

if [[ "$compressed_img" == "yes" ]]; then
    echo -e ${i_msg}" Compressing the image using xz compression..."
    xz -v ${imgfile_dir}/${fedora_image}_${krnver_str}_raw
    sleep 1
    echo "Done."
fi

if [[ "$docleanup_after" == "yes" ]]; then
    echo -n -e ${i_msg}" Removing temporary mount directory..."
    rmdir $rootfs_mnt
    echo " Done."
fi

echo -e "\n\033[92m -- Finished -- \033[0m\n"
