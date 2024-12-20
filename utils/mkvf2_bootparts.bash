#!/bin/bash

# mkvf2_bootparts.bash

# 24-12-20, Tripole

# Script to create a few partitions on storage media (e.g. SD, eMMC, nvme) to
# be used as "bootdisk" (to hold Petitboot+kernel) for VisionFive 2. As an
# option you can also install openSPI+SPL and u-boot. For this, the files
# u-boot-spl.bin.normal.out and visionfive2_fw_payload.img must exist in the
# same dir as this script (you will be asked about this option near the end).

# Snippets sourced from petitboot_mkimage_riscv64.bash

# Requirements: sfdisk, dosfstools (and perhaps more).

# -------------------------------- Parameters --------------------------------

# For explanations of the parameter and values here, see the official StarFive
# documentation (and e.g. the comments in debuntu_dbstrap_riscv64.bash).

# The generated Linux image has a GPT disk label and is partitioned as
# [ part1 (not used), part2 (not used), bootfs, rootfs ]. Details about
# the partitioning are given in comments about the sfdisk_script below.
p1_start=4096    # Recommended to not change
p1_size=4096     # Recommended to not change
p2_start=8192    # Recommended to not change
p2_size=8192     # Recommended to not change
p3_start=16384   # Recommended not to change
bootfs_MiB=300   # In general, use at least 100 MiB.
bootfs_label=BOOT # FAT label.

tmp_mnt=/tmp/mkvf2_bootparts # Temporary mount point (created then deleted).

spl_fname="u-boot-spl.bin.normal.out"
uboot_fname="visionfive2_fw_payload.img"

# ------------------------------- Preliminaries ------------------------------

# Remaining partition variables to be calculated.
p3_size=$(($bootfs_MiB *1024*1024/512))
gpt_bu_start=$(($p3_start +$p3_size +1))
gpt_bu_size=34 # Trailing GPT backup table.
imgfile_num_sectors=$(($p1_start +$p1_size +$p2_size +$p3_size +$gpt_bu_size))

# -------------------------------- Here-docs ---------------------------------

sfdisk_script=$(cat <<EOF
label: gpt
first-lba: $p1_start
1 : start=${p1_start}, size=${p1_size}, type=2E54B353-1271-4842-806F-E436D6AF6985, name=spl
2 : start=${p2_start}, size=${p2_size}, type=5B193300-FC78-40CD-8002-E86C45580B47, name=uboot
3 : start=${p3_start}, size=${p3_size}, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=image
EOF
)

uEnv_txt=$(cat <<EOF
# For StartFive's VisionFive 2, taken from VF2 SBC S/W Tech Ref. Man.
dt_high=0xffffffffffffffff
initrd_high=0xffffffffffffffff
kernel_addr_r=0x40200000
kernel_comp_addr_r=0x5a000000
kernel_comp_size=0x4000000
fdt_addr_r=0x46000000
ramdisk_addr_r=0x46100000
# Move distro to first boot to speed up booting
boot_targets=distro mmc0 dhcp
# Fix wrong fdtfile name
fdtfile=starfive/jh7110-starfive-visionfive-2-v1.3b.dtb
# Fix missing bootcmd
bootcmd=run load_distro_uenv;run bootcmd_distro
EOF
)

extlinux_conf=$(cat <<EOF

MENU TITLE <BOOTPART>
DEFAULT Petitboot

LABEL Petitboot
  LINUX  /vmlinux
  INITRD /initrd-pb
  FDT    /jh7110-starfive-visionfive-2-v1.3b.dtb
  APPEND quiet pb_no_autoboot=true pb_nonet=true pb_delay=2 pb_displ=db pb_mem_max=0x13fffffff

EOF
)

# ----------------------------------- Main -----------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root, exiting."
    exit 1
fi

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /dev/target_dev"
    echo "    where target_dev is e.g. /dev/mmcblk0"
    exit 1
else
    target_dev=$1
    target_dev_end=${target_dev#/dev/}
    test_exist_target_dev=$(lsblk | grep "${target_dev_end} ")
    if [[ $? != 0 ]]; then
        echo "The proposed target device $target_dev does not exist, exiting."
        exit 1
    fi
fi

echo "-- Executing $0 to create new partitions on a device. --"
echo "You have selected the following target device: $target_dev"
echo -n "Is this correct? [N,y] >"
read target_sel
if [[ "$target_sel" != "y" ]]; then
    echo "OK, your answer was not (exactly) y , exiting."
    exit 1
else
    echo "OK, you answered y so here we go."
fi

# First, wipe the tagret area.
echo "Filling the target area on ${target_dev} with zeros ..."
dd if=/dev/zero of=$target_dev bs=512 count=$imgfile_num_sectors conv=fsync status=progress
sync

echo -e "\nCreating new partitions on $target_dev ..."
echo -e "$sfdisk_script" | sfdisk $target_dev
sync

echo -e "\nResulting partitions created on ${target_dev}:"
sfdisk -l -o Device,Start,End,Sectors,Size,Type,Type-UUID,Name $target_dev

echo -e "\nFormatting the boot partition as FAT32 ..."
mkfs.fat -v -F32 -n $bootfs_label ${target_dev}p3

echo -e -n "\nInstalling also uEnv.txt (for VF2) and template extlinux.conf ..."
mkdir -p $tmp_mnt
mount ${target_dev}p3 $tmp_mnt
echo -e "$uEnv_txt" >${tmp_mnt}/uEnv.txt
mkdir ${tmp_mnt}/extlinux
echo -e "$extlinux_conf" >${tmp_mnt}/extlinux/extlinux.conf
umount ${target_dev}p3
echo " Done."

echo -e "\nDo you want to install the boot loader binaries"
echo "$spl_fname and $uboot_fname"
echo -n "to ${target_dev}p1 and ${target_dev}p2, respectively? [N,y] >"
read bootld_inst
if [[ "$bootld_inst" != "y" ]]; then
    echo "OK, your answer was not (exactly) y , skipping."
else
    if [[ -f $spl_fname ]] && [[ -f $uboot_fname ]]; then
        echo "OK, you answered y so we install also the bootloader binaries ..."
        dd if=./u-boot-spl.bin.normal.out of=${target_dev}p1 status=progress conv=fsync
        dd if=./visionfive2_fw_payload.img of=${target_dev}p2 status=progress conv=fsync
    else
        echo "At least one of $spl_fname and $uboot_fname is missing, skipping."
    fi
fi

echo -e "\n -- Done executing $0 --"
