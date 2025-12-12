#!/bin/bash

# debuntu_dbstrap_riscv64.bash
# 24-12-10: v0.13
# 25-12-12: v0.15
# Author: Tripole

# Usage: ./debuntu_dbstrap_riscv64.bash <distro>
#        where distro is one of: ubuntu, debian

# * This is a script to create a (small, CLI) Debian or Ubuntu Linux RISCV64
#   image using debootstrap. Compared to pristine Debian/Ubuntu it has only a
#   small number of additions; some scripts under /etc/kernel/post{inst,rm} to
#   update extlinuc.conf on the bootfs partition and some utility scripts in
#   /usr/local/bin to update grub.cfg. (Optionally, it also has a directory on
#   e.g. the bootfs partition to set up e.g. Petitboot.)
# * The script is designed to be run (as root) on an Ubuntu build host, either
#   natively on aarch64/ARM64 or virtualized (using qemu-aarch64-static) on
#   x86_64/amd64. The build host must have Debian keys installed (see below).
#   (It is quite possible it runs on a Debian host too, but this is not tested.)
# * Booting: The generated images can be booted with board resident (e.g. QSPI)
#   openSBI+u-boot using extlinux.conf on the image or by using Petitboot for
#   RISCV64 (using grub.cfg on the image). (Petitboot can be installed on the
#   image or on e.g. eMMC.) (The partition layout has two leading empty 2M+4M
#   partitions for manual addition SPL and openSPI+u-boot, if needed.)
# * Target SoC/board: The generated images are tailored to VisionFive 2 but can
#   easily be adapted to other RISCV64 SBCs (by updating the dtb and uEnv.txt).
# * Requirements: The script requires basic functionality incl. blkid, dd,
#   losetup, mkfs, xz, wget and the pkg. systemd-container (for systemd-nspawn).
#   (Most requirements are checked at runtime below.) For "cross-scripting"
#   (i.e. for use on another arch than RISCV64) you need to install the package
#   qemu-user-static (for qemu-riscv64-static).
# * Typical usage: Edit the parameters below and run the script from a temporary
#   directory (the image and all temporary files will be created in this dir.).
# * Image tested on: VisionFive 2, v1.3b (8GB).

# Notes:
# - The installed system is a bit bare-bones; e.g. no swap is set (only zram).
#   Info about (re)configuring zram (and optionally set up swap) can be found
#   e.g. in /etc/default/zramswap and https://wiki.debian.org/ZRam
# - During execution of the script (near the end) you will be asked to configure
#   (dpkg-reconfigure) some items: time zone, locale, keyboard and set root pw.
#   (The localizations can later be adjusted with dpkg-reconfigure.)
# - The image can always be booted via (board resident) u-boot (extlinux.conf)
#   but also using e.g. Petitboot (w/ e.g. grub.cfg, as set up on the image).
# - If you are booting via grub.cfg on rootfs (e.g. using Petitboot) you only
#   need to update grub.cfg and this can can be done by using grub-mkimage or
#   via scripts in /usr/local/bin, e.g. the script mkgrubcfg_simple.bash
# - The dtb files on the image are located at
#   /usr/lib/linux-image-<kernel version>-riscv64 (Debian)
#   /usr/lib/firmware/<kernel version>-generic/device-tree (Ubuntu)
#   A link to the default dtb must exist as /etc/default/dtb (as set up by this
#   script) in order for the kernel postinst extlinux.conf update hook to work.
# - The dtb file is not specified in the grub.cfg file upon installation but
#   the script mkgrubcfg_simple.bash can be run post-install to include a dtb
#   specification in grub.cfg. However, bootloaders based on kexec, such as
#   Petitboot, typically let the booted Linux image inherit the dtb used by
#   the bootloader, cf. the README files at Gitlab about Petitboot/u-root.
# - On VisionFive 2 the graphics support is not yet in mainline kernel so the
#   the remark below about desktop environments is not (yet) relevant (and you
#   have to use serial console or ssh, for now). (On VF2 there is also some
#   confusion about naming re. uEnv.txt/vf2_uEnv.txt, see comments below).
# - The automatic copying of vmlinuz,initrd.img to the bootfs partition after
#   kernel upgrade or initramfs rebuild always copies the newest kernel,initrd
#   (the one with the highest version number), as determined by the sort -V
#   command (cf. scripts in /etc/{kernel/postinst.d,initramfs/postupdate.d}).
# - The snap system on Ubuntu can cause trouble so it might be worth purging it.
# - The package linux-firmware is installed but firmware for e.g. a specific
#   WiFi or Bluethooth chip might not be included and thus have to be sought
#   elsewhere.
# - Networking is handled by NetworkManager on Ubuntu and systemd's networking
#   service on Debian. If you don't want NetworkManager installed on Ubuntu, and
#   thus fall back to netplan, you can remove the string "network-manager" from
#   the commands inside the here-doc below named ubuntu_custom_inst and comment
#   out the relevant sections of the function setup_distro_specifics below.
# - The numbering of the eth interfaces may vary, so try all RJ45 connectors.
# - Run time for this script is about 10m for Debian (excl. compression) on a
#   modern computer with good network connectivity. For Ubloatu, it can take
#   almost twice that time. (Check with: time ./debuntu_dbstrap.bash debian)
# - Tip: Generate the image cheaply, say 6G rootfs (so that burn to SD/USB
#   goes quickly). Then, enlarge the rootfs partition on the SD/USB. This can
#   be done on first boot by using growpart tool (see below). Alternatively,
#   it can be done before first boot by using either gparted or with the combo
#   of parted, e2fsck and resize2fs like so:
#   parted /dev/sdX resizepart 2 50% ; e2fsck -f /dev/sdX4 ; resize2fs /dev/sdX4
# - The image has a GPT partition table. This means that after copying to e.g.
#   SD, and possibly expanding partition 4 as above, the secondary GPT header
#   may not be at the end of the disk (as it should). The simplest way to fix
#   this is probably to run sfdisk --relocate gpt-bak-std /dev/sdX
# - Apart from booting considerations, this image is portable and can be
#   transferred by e.g. rsync to other media (the only thing that needs to be
#   updated then is the PARTUUID of the root partitionin listed in /etc/fstab).
# - Domain name resolution is now handled (also on Debian) by systemd, see
#   e.g. sec 2.1 in https://wiki.archlinux.org/title/Systemd-resolved

# ------------------------------- parameters ---------------------------------

# Top level directory in several of the file hierarchies used below and also
# the location of the disk image container during build (for size, see below).
# (Typically img_file_dir is the directory in which this script is located.)
imgfile_dir=$PWD

ubuntu_name=Ubuntu     # Used for the image name and in grub.cfg
ubuntu_edition=Noble   # Tested with Jammy and Noble.
debian_name=Debian     # Used for the image name and in grub.cfg
debian_edition=Trixie  # Works only w/ Trixie currently (caveat with RISCV64).

# The image tag will be added to img. name after distro name and kernel version.
img_tag=3pole-$(date +"%y%m%d")

# Host name for image.
host_name=debu

# The dtb file name is used in extlinux.conf and the dtb must be one of those
# existing in local /usr/lib/*${kernel-version}*/${dtb_mfg} on the image, i.e.
# as it comes in the kernel package. (The manufacturer name can be looked up
# in the kernel source tree at arch/riscv/boot/dts)
dtb_mfg=starfive
dtbfile_name=jh7110-starfive-visionfive-2-v1.3b.dtb
dtbfile_path=/boot/dtbs/${dtb_mfg}/${dtbfile_name} # Full path, starts w/ /boot

# If the file $root_sshkey_loc exists in $imgfile_dir then it will be installed
# on the image as /root/.ssh/authorized_keys (for passwordless ssh root login).
root_sshkey_loc="mysshkey.pub"

# If the directory $add_loc_dir exists in $imgfile_dir then this dir and its
# contents will be copied to $add_dir_img on the image (rel. to its root lvl.).
add_dir_loc=petitboot
add_dir_img=boot # No leading forward slash here.

# The generated Linux image has a GPT disk label and is partitioned as
# [ part1 (not used), part2 (not used), bootfs, rootfs ]. Details about
# the partitioning are given in comments about the sfdisk_script below.
p1_start=4096    # Recommended to not change
p1_size=4096     # Recommended to not change
p2_start=8192    # Recommended to not change
p2_size=8192     # Recommended to not change
p3_start=16384   # Recommended not to change
bootfs_MiB=500   # In general, use at least 300 MiB, 500 MiB recommended.
rootfs_MiB=6000  # In general, use at least 5000 MiB.
rootfs_type=ext4 # Must be ext4 currently.

# Compression (xz) of the finsiehd image takes some extra time.
compressed_img=no # {yes,no}

# Do we want to clean up all temporary files and directories afterwards?
docleanup_after=yes # {yes,no}

# Of course, it is often better to use a mirror for the repo downloads, see e.g.
# https://www.debian.org/mirror/list and http://mirrors.ubuntu.com
ubuntu_repourl="http://ports.ubuntu.com/ubuntu-ports"
debian_repourl="http://ftp.debian.org/debian"

# Link to growpart for resizing second partition (rootfs) to desired size.
growpart_url="https://raw.githubusercontent.com/canonical/cloud-utils/main/bin/growpart"

# The kernel command line actually used (to make extlinux.conf and grub.cfg)
# below will be prepended by the string "root=PARTUUID=${rootfs_PARTUUID}"
kernel_cmdline_opts="quiet splash"

# The selected zram compression method here must match what the kernel supports
# (if unsure, set to zstd). See /etc/default/zramswap
zram_compression=lzo-rle # {zstd,lzo,lzo-rle,...}
zram_percent=35 # Amount of RAM to be used for zram.

# Holds downloads etc.
tmpfile_dir=${imgfile_dir}/temp_files

# Temporary mount points (dirs) used during image creation.
# (The same structure is used on the image with the bootfs mounted under /boot).
rootfs_mnt=${imgfile_dir}/rootfs_tmp
bootfs_dir=/boot # Must have leading forward slash.
bootfs_mnt="${rootfs_mnt}""${bootfs_dir}"

# Mount options used in the fstab file on the image.
rootfs_mnt_opts="errors=remount-ro"
bootfs_mnt_opts="dmask=0027,errors=remount-ro"

# Nowadays this should be end0 for both Debian and Ubuntu.
iface_name=end0

# Some (but not all) commands used below to create the image.
reqd_cmdlist=("blkid" "dd" "debootstrap" "losetup" "mkfs.fat" "mkimage"
              "systemd-nspawn" "tar" "wget" "xz"
)

# List of packages to be added to (the ones minimally needed for) the install.
debian_extra_packages="aptitude man-db firmware-linux-free zram-tools sudo openssh-server"
ubuntu_extra_packages="nano aptitude man-db zram-tools sudo openssh-server"

# For running in QEMU the user mode emulation binary qemu-static-<arch> is reqd.
reqd_cmdlist_virt=("qemu-riscv64-static")

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

arch_str=$(uname -m)
if [[ "$arch_str" != "riscv64" && "$arch_str" != "x86_64" ]]; then
    echo ${e_msg}" The architecture is not one of x86_64 or riscv64, exiting."
    exit 1
fi

have_all_cmds=yes
if [[ "$arch_str" == "riscv64" ]]; then
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

# The debian-keyring package contains also the keys for the archives/repos.
if [[ "$1" == "debian" ]]; then
    deb_keyring_isinst=$(dpkg -l | awk '/debian-keyring/ {print }' | wc -l)
    if [[ $deb_keyring_isinst -eq 0 ]]; then
        echo ${e_msg}" The Debian keyring is not installed, exiting."
        exit 1
    fi
fi

if [[ "$rootfs_type" == "ext4" ]]; then
    reqd_cmdlist=("${reqd_cmdlist[@]}" "mkfs.ext4")
elif [[ "$rootfs_type" == "btrfs" ]]; then # Only a placeholder for now.
    reqd_cmdlist=("${reqd_cmdlist[@]}" "mkfs.btrfs")
else
    echo -e "The fstype for the rootfs must be one of ext4 or btrfs, exiting."
    exit 1
fi

# UUIDs can also be generated with the cmd uuidgen from the pkg uuid-runtime.
rootfs_UUID=$(cat /proc/sys/kernel/random/uuid)     # Used in rootfs, /etc/fstab
rootfs_PARTUUID=$(cat /proc/sys/kernel/random/uuid) # Used in extlinux.conf, grub.cfg
eth0nm_UUID=$(cat /proc/sys/kernel/random/uuid)     # Used in Ubuntu.
if [[ -z $rootfs_UUID || -z $rootfs_PARTUUID || -z $eth0nm_UUID ]]; then
    echo ${e_msg}" Cannot generate valid UUIDs from kernel random source, exiting."
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
        kernel_img_name_short=vmlinuz
        ;;
    "debian")
        distro_name=$debian_name
        distro_edition=$debian_edition
        distro_repourl=$debian_repourl
        keyring_file=/usr/share/keyrings/debian-archive-keyring.gpg
        bootfs_label=DEBN_BOOT
        rootfs_label=DEBN_ROOT
        kernel_img_name_short=vmlinux
        nonfree_list="non-free non-free-firmware"
    ;;
    *)
        calling_cmd=$0
        calling_cmd_tail=${calling_cmd##*/}
        echo "Usage: $calling_cmd_tail <distro>"
        echo "       where distro is one of: ubuntu,debian"
        echo "       For more customizable parameters, see inside the script."
        exit 0
    ;;
esac

# This is the name used on the container file during image creation.
# Before exit of this script, the kernel version is inserted into the name.
imgfile_name=${distro_name}_${distro_edition}_${img_tag}.img

# Remaining partition variables to be calculated.
p3_size=$(($bootfs_MiB *1024*1024/512))
p4_start=$(($p3_start +$p3_size +1))
p4_size=$(($rootfs_MiB *1024*1024/512))
gpt_bu_start=$(($p4_start +$p4_size +1))
gpt_bu_size=34 # Trailing GPT backup table.
imgfile_num_sectors=$(($p1_start +$p1_size +$p2_size +$p3_size +$p4_size +$gpt_bu_size))

# For the debootstrapping.
distro_release="$(tr [A-Z] [a-z] <<< "$distro_edition")" # To lowercase.

# For processing in the here-docs below.
ubuntu_release="$(tr [A-Z] [a-z] <<< "$ubuntu_edition")" # To lowercase.
debian_release="$(tr [A-Z] [a-z] <<< "$debian_edition")" # To lowercase.

# ------------------------------- here-docs ----------------------------------

# The partition layout here is the same as the layout used on StarFive's Debian
# images, which is documented in [1]. In this layout, the first partition is
# intended to hold the binary u-boot.spl.bin.normal.out and the second partition
# is intended to hold the binary fw_payload, see [2]. The first binary here is
# the SPL (based on u-boot) and the second binary is a FIT image containing
# fw_firmware.bin, which in turn is a combo of openSBI and u-boot.bin (see [2]).
# The software components just described correspond to distinct functions
# performed in the boot flow of VisionFive 2, see e.g. Fig. 2.7 in [2] or Fig.
# 2.1 in [3]. (This boot flow is a variation of the standard u-boot flow, see
# e.g. slides 12, 28 in [4] (for nomenclature see [5]). The variation is due to
# the need for openSBI on the riscv64 arch, see e.g. slide 13 in [6].) The third
# and fourth partitions are the boot and system partitions, respectively. We
# recreate here the StarFive partition layout structure but without installing
# SPL and openSPI+u-boot. (These items can later be manually added, if desired,
# see Sec. 3.8.3 ("Updating SPL and U-Boot of SD Card and eMMC") in [6]).
# The partition GUID type codes for the four partitions used are as follows:
#
# p1 : 2E54B353-1271-4842-806F-E436D6AF6985 : HiFive BBL (cf. fdisk)
# p2 : 5B193300-FC78-40CD-8002-E86C45580B47 : HiFive FSBL (cf. fdisk)
# p3 : C12A7328-F81F-11D2-BA4B-00A0C93EC93B : ESP (0xEF00)
# p4 : 0FC63DAF-8483-4772-8E79-3D69D8477DE4 : Linux filesystem data (0x8300)
#
# References (all the StarFive docs can be found at https://wiki.rvspace.org):
# [1] https://rvspace.org/en/project/Building_StarFive_Debian_Image
# [2] VisionFive 2 Single Board Computer Software Technical Manual, Version
#     1.31, Date 2024/07/01, Doc ID VisionFive2-TRMEN-001.
# [3] JH7110 Boot User Guide, Version 1.2, Date 2023/07/14, Doc ID
#     JH7110-BUGEN-001, VisionFive 2.
# [4] J. Teki, U-Boot from Scratch, FOSDEM - 2019.
# [5] https://stackoverflow.com/questions/31244862/what-is-the-use-of-spl-secondary-program-loader
# [6] J. Teki, An Introduction to RISC-V Boot flow, China RISC-V Forum - 2019,
#     ShenZhen, https://crvf2019.github.io/pdf/43.pdf
# [7] VisionFive 2 Single Board Computer Quick Start Guide, Version 1.72,
#     Date 2024/05/23, Doc ID VisionFive2-QSGEN-001.

sfdisk_script=$(cat <<EOF
label: gpt
first-lba: $p1_start
1 : start=${p1_start}, size=${p1_size}, type=2E54B353-1271-4842-806F-E436D6AF6985, name=spl
2 : start=${p2_start}, size=${p2_size}, type=5B193300-FC78-40CD-8002-E86C45580B47, name=uboot
3 : start=${p3_start}, size=${p3_size}, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=image
4 : start=${p4_start}, size=${p4_size}, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=root, uuid=$rootfs_PARTUUID
EOF
)

# Below we add also a line for the FAT32 (ESP) boot partition.
# (For swap we only add a stub, see https://help.ubuntu.com/community/SwapFaq)
fstab_file=$(cat <<EOF
UUID=$rootfs_UUID  /  $rootfs_type  $rootfs_mnt_opts  0  1
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

# Only used with manual configuration.
# debian_resolver_file=$(cat <<EOF
# nameserver $name_server_1
# nameserver $name_server_2
# EOF
# )

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
interface-name=$iface_name

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

ubuntu_repo_list_deb822=$(cat <<EOF
Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports
Suites: noble noble-updates noble-backports
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports
Suites: noble-security
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
)

flashk_block_file=$(cat <<"EOF"
Package: flash-kernel
Pin: release *
Pin-Priority: -1
EOF
)

# This is the basic (default) set of packages installed on top of the rootfs.
# (If you want to add packages, edit the variable ubuntu_extra_packages above.)
ubuntu_custom_inst=$(cat <<EOF
#!/bin/bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt -y install linux-image-generic # linux-headers-generic
echo "Setting FSTYPE to $rootfs_type in /etc/initramfs-tools/initramfs.conf"
sed -i "s/.*FSTYPE=.*/FSTYPE=${rootfs_type}/g" /etc/initramfs-tools/initramfs.conf
DEBIAN_FRONTEND=noninteractive apt -y install dialog network-manager usbutils
DEBIAN_FRONTEND=noninteractive apt -y install $ubuntu_extra_packages
dpkg-reconfigure tzdata
dpkg-reconfigure locales
dpkg-reconfigure keyboard-configuration

echo "Set password for \033[91mroot:\033[0m"
until passwd; do echo "Try again."; done
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

# This is the basic (default) set of packages installed on top of the rootfs.
# (If you want to add packages, edit the variable debian_extra_packages above.)
debian_custom_inst=$(cat <<EOF
#!/bin/bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt -y install linux-image-riscv64 # linux-headers-riscv64
echo "Setting FSTYPE to $rootfs_type in /etc/initramfs-tools/initramfs.conf"
sed -i "s/.*FSTYPE=.*/FSTYPE=${rootfs_type}/g" /etc/initramfs-tools/initramfs.conf
DEBIAN_FRONTEND=noninteractive apt -y install locales systemd-timesyncd usbutils
DEBIAN_FRONTEND=noninteractive apt -y install $debian_extra_packages
dpkg-reconfigure tzdata
dpkg-reconfigure locales
apt -y install console-setup
# dpkg-reconfigure keyboard-configuration

echo "Set password for \033[91mroot:\033[0m"
until passwd; do echo "Try again."; done
EOF
)

# We split this file in two; one part with parameter substitution and one w/o.
mkextlinux_conf_p1=$(cat <<EOF
#!/bin/bash

# Scans for vmlinu[x,z]-* in /boot and sets up an extlinux.conf file in
# /boot/extlinux
# Usage: /usr/local/bin/mkextlinux_conf.bash /boot/path/t/odtb/file where
# /boot/path/to/dtb/file is the full path under /boot to the dtb file.
# The path can alternatively be given in the env. variable dtb_path (command
# line has precedence). The dtb path can be a symlink; the full dtb path
# will be inserted into extlinux.conf Normally, the script is run from a
# mounted rootfs and then the PARTUUID of the rootfs is discovered using the
# blkid comand (see below). However, for use e.g. inside a chroot jail the
# rootfs PARTUUID can also be given as an environment variable prepended on
# the command line, e.g. like so (note the single quotes):
# chroot . /bin/bash -c 'rootfsPARTUUID=f3cab04c-...-faec36aace3f /usr/local/bin/mkextlinux_conf.bash /boot/path/to/dtb/file'

# The kernel command line parameters here may need tweaking.
kernel_cmdline_pars_="$kernel_cmdline_opts"

EOF
)

mkextlinux_conf_p2=$(cat <<"EOF1"

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: /usr/local/bin/mkextlinux_conf.bash /boot/path/to/dtb/file"
    echo "  where /boot/path/to/dtb/file is the full path (under /boot) to the dtb file."
    echo "  The path can alternatively be given in the environment variable dtb_path"
    echo "  (command line has precedence). More info inside the script."
    exit 1
fi

if [[ $# == 0 && -z $dtb_path ]]; then
    echo "A dtb file (or link) must be supplied, either as a command line argument"
    echo "or in the environment variable dtb_path."
    exit 1
fi

if [[ $# -eq 1 ]]; then
    dtb_path=$1
else
    echo "Using environment variable dtb_path: $dtb_path"
fi

dtbpath_full=$(realpath -e $dtb_path)
if [[ -f $dtbpath_full ]]; then
    dtbpath_rel_boot=${dtbpath_full#/boot/}
else
    echo "The dtb file (${dtbpath_full}) is missing, exiting."
    exit 1
fi

distro_name_lc=$(cat /etc/os-release | grep -E "^ID=" | cut -d "=" -f2)
distro_edition_lc=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d "=" -f2)

# First letter to uppercase.
distro_name="$(tr '[:lower:]' '[:upper:]' <<< ${distro_name_lc:0:1})""${distro_name_lc:1}"
distro_edition="$(tr '[:lower:]' '[:upper:]' <<< ${distro_edition_lc:0:1})""${distro_edition_lc:1}"

menu_title="--- $distro_name (${distro_edition}) ---"

if [[ -z "$rootfsPARTUUID" ]]; then
    rootfs_partuuid=$(blkid -s PARTUUID $(mount | grep -E "/ " | cut -d " " -f 1) | cut -d "\"" -f2)
else
    rootfs_partuuid=$rootfsPARTUUID
fi

# The next line is a default kernel command line and may have to be adjusted for each kernel.
kernel_cmdline_rootfspartuuid="root=PARTUUID="${rootfs_partuuid}
kernel_cmdline=${kernel_cmdline_rootfspartuuid}" "${kernel_cmdline_pars_}

echo "Parameters used to set up extlinux.conf :"
echo "Devicetree: $dtbpath_full"
echo "Rootfs PARTUUID: $rootfs_partuuid"
echo "Kernel cmd line: $kernel_cmdline"

cd /boot

if [[ -f extlinux/extlinux.conf ]]; then
    mv extlinux/extlinux.conf extlinux/extlinux.conf.bak
fi

# Note: The leading tabs in the here-document below are important.
	cat <<-EOF > extlinux/extlinux.conf
	# For more info about this file see the URLs (and the links therein):
	# https://docs.u-boot.org/en/latest/develop/distro.html
	# https://wiki.syslinux.org/wiki/index.php?title=SYSLINUX
	# For the tags (tokens) in extlinux.conf that u-boot actually parses, see
	# e.g. the code in the u-boot source file pxe_utils.c
	
	# The path to the dtb file can be defined by either the FDT or FDTDIR tag in
	# this file, or by using the variable fdtfile in uEnv.txt. The tag FDT has
	# has priority over FDTDIR but the role of fdtfile in uEnv.txt depends on
	# the boot methods defined in u-boot's environment. It should in general be
	# sufficient to have the correct dtb file specification here. The FDTDIR tag
	# is not well documented (even in the u-boot docs) but for VF2, v1.3b, the
	# following two alternatives work:
	# FDT /dtbs/starfive/jh7110-starfive-visionfive-2-v1.3b.dtb
	# FDTDIR /dtbs
	# provided the actual dtb path is /dtbs/starfive/starfive_visionfive2.dtb
	
	MENU TITLE $menu_title
	DEFAULT DEBNT_DEFAULT
	
	# When several entries are present; waiting time in units of 0.1s.
	# (When only one entry is present only that will show, without title.)
	TIMEOUT 20
	EOF

item_counter=0
default_label=""
for kernel_name in $(ls | grep -E "vmlinu[x,z]-" | sort -V) ; do
    item_counter=$((item_counter +1))

    kernel_vers=$(cut -d '-' -f 2- <<< $kernel_name)
    initrd_name=initrd.img-${kernel_vers}

    kernel_path=/boot/$kernel_name
    initrd_path=/boot/$initrd_name

    label=$kernel_name

    add_msg="Added extlinux.conf menu entry: $label"
    if [[ $item_counter -eq 1 ]]; then
        default_label=$label
        add_msg="$add_msg"" (default)"
    fi
    echo $add_msg

    # Note: The leading tabs in the here-document below are important.
	cat <<-EOF >> extlinux/extlinux.conf
	
	LABEL $label
	  LINUX  /${kernel_name}
	  INITRD /${initrd_name}
	  FDT    /${dtbpath_rel_boot}
	  APPEND $kernel_cmdline
	
	EOF
done

sed -i "s/DEBNT_DEFAULT/$default_label/g" /boot/extlinux/extlinux.conf

EOF1
)

mkextlinux_conf="${mkextlinux_conf_p1}""${mkextlinux_conf_p2}"

# This will go into a script in /etc/kernel/post{inst,rm}.d
extlinux_update_hook=$(cat <<"EOF"
#!/bin/bash
echo "Running kernel post{inst,rm} hook for extlinux.conf ..."

dtbfile_link=/etc/default/dtb
dtbpath_full=$(realpath -e $dtbfile_link)
if [[ ! -f $dtbpath_full ]]; then
    echo "The dtb file ($d{tbpath_full}) is missing, exiting."
    exit 1
fi

rootfsPARTUUID=$rootfs_PARTUUID_ dtb_path=$dtbpath_full bash -c '/usr/local/bin/mkextlinux_conf.bash'
EOF
)

# Template uEnv.txt but using values for VF2.
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

README_kernels=$(cat <<"EOF"
The scripts in /usr/local/bin can be used to assist in kernel handling.
For booting via grub the script mkgrubcfg_simple.bash can be used to generate
simple grub entries for kernels and accompanying initramfses in /boot (see
instrcutions inside the script generating this image). (See also the kernel
update hook scripts in /etc/kernel/{postinst,postrm}.d)
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

# Scans for kernel image files and makes a simple grub.cfg file in /boot/grub
#
# Usage: /usr/local/bin/mkgrubcfg_simple.bash /boot/path/to/dtb/file
#   where /boot/path/to/dtb/file is the full path under /boot to the dtb file.
#
# The full path is the path as it appears on a booted system. The full path
# can alternatively be given in the environment variable dtb_path (command
# line has precedence) and it can also be a symlink (e.g. /etc/default/dtb).
# The full dtb path will be inserted into grub.cfg in the form it appears on
# a non booted system (i.e. without the leading /boot part of the path if a
# separate boot partition is used; this is controlled by a parameter setting
# in the code). If no dtb path is given, a grub.cfg is created with only a
# placeholder for the path. Normally, this script is run from a mounted rootfs
# and then the PARTUUID of the rootfs is discovered using the blkid command
# (see below). However, for use e.g. inside a chroot jail the rootfs PARTUUID
# can also be given as an environment variable prepended on the command line,
# e.g. like so (note the single quotes):
# chroot . /bin/bash -c 'rootfsPARTUUID=f3cab04c-...-faec36aace3f /usr/local/bin/mkgrubcfg_simple.bash /boot/path/to/dtb/file'

# First defined at script generation time. Edit to taste.
kernel_cmdline_pars_="$kernel_cmdline_opts"

EOF
)

mkgrubcfg_simple_p2=$(cat <<"EOF1"

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: /usr/local/bin/mkgrubcfg_sumple.bash /boot/path/to/dtb/file"
    echo "  where /boot/path/to/dtb/file is the full path (under /boot) to the dtb file."
    echo "  The path can alternatively be given in the environment variable dtb_path"
    echo "  (command line has precedence). More info inside the script."
    exit 1
fi

# The file paths entered into in grub.cfg are relative to the top of the
# partition from where grub.cfg is read at boot time. The prefixes below for
# kernel and initramfs are added to their respective file names in grub.cfg.
# Thus, if you have a separate separate boot partition, these prefixes are
# generally the empty string "". If you do not have a separate boot partition
# then these prefixes are generally "/boot". The same priciple applies to the
# prefix for the dtb file (however the unprefixed file path is typically more
# than just the filename).
kernel_path_prefix=""
initrd_path_prefix=""
dtb_path_prefix=""

if [[ $# -eq 1 ]]; then
    dtb_path=$1
else
    echo "Using environment variable dtb_path: $dtb_path"
fi

# In grub.cfg it is not always necessary to specify the dtb file, for instance
# when grub.cfg is used during a kexec call where no new dtb is to be loaded
# (in which case the the already loaded dtb is reused).
devicetree_str="# devicetree /path/to/dtbfile # not used currently"
devicetree_msg="Devicetree:  No dtb file specified or dtb file missing."
dtbpath_full=$(realpath -e $dtb_path 2>/dev/null)
if [[ -f $dtbpath_full ]]; then
    dtbpath_rel_boot=${dtbpath_full#/boot} # Remove leading "/boot" by default.
    dtbpath_in_grubcfg=${dtb_path_prefix}${dtbpath_rel_boot}
    devicetree_str="devicetree $dtbpath_in_grubcfg"
    devicetree_msg="Devicetree:  $dtbpath_full"
fi

# To use this script on a machine where the kernel image or inird has some
# other naming convention, change the settings below.
kernel_name_template="vmlinu[x,z]-"
initrd_name_template="initrd.img"

distro_name_lc=$(cat /etc/os-release | grep -E "^ID=" | cut -d "=" -f2)
distro_edition_lc=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d "=" -f2)

# First letter to uppercase.
distro_name="$(tr '[:lower:]' '[:upper:]' <<< ${distro_name_lc:0:1})""${distro_name_lc:1}"
distro_edition="$(tr '[:lower:]' '[:upper:]' <<< ${distro_edition_lc:0:1})""${distro_edition_lc:1}"

if [[ -z "$rootfsPARTUUID" ]]; then
    rootfs_partuuid=$(blkid -s PARTUUID $(mount | grep -E "/ " | cut -d " " -f 1) | cut -d "\"" -f2)
else
    rootfs_partuuid=$rootfsPARTUUID
fi

# The next line is a default kernel command line and may have to be adjusted for each kernel.
kernel_cmdline_rootfspartuuid="root=PARTUUID="${rootfs_partuuid}
kernel_cmdline=${kernel_cmdline_rootfspartuuid}" "${kernel_cmdline_pars_}

echo "Parameters used to set up grub.cfg :"
echo $devicetree_msg
echo "Rootfs PARTUUID: $rootfs_partuuid"
echo "Kernel cmd line: $kernel_cmdline"

cd /boot

if [[ -f grub/grub.cfg ]]; then
    mv grub/grub.cfg grub/grub.cfg.bak
fi

for kernel_name in $(ls | grep -E "$kernel_name_template" | sort -V) ; do
    kernel_vers=$(cut -d '-' -f 2- <<< $kernel_name)
    initrd_name=${initrd_name_template}-${kernel_vers}

    kernel_path_in_grubcfg=${kernel_path_prefix}/${kernel_name}
    initrd_path_in_grubcfg=${initrd_path_prefix}/${initrd_name}
    echo "Added grub.cfg menu entry: $distro_name $distro_edition (kernel $kernel_vers)"

    # Note: The leading tabs in the here-document below are important.
	cat <<-EOF >> grub/grub.cfg
	menuentry "$distro_name $distro_edition (kernel $kernel_vers)" {
	
	linux  $kernel_path_in_grubcfg $kernel_cmdline
	initrd $initrd_path_in_grubcfg
	$devicetree_str
	
	}
	
	EOF
done
EOF1
)

mkgrubcfg_simple="${mkgrubcfg_simple_p1}""${mkgrubcfg_simple_p2}"

# This will go into a script in /etc/kernel/post{inst,rm}.d
grubcfg_update_hook=$(cat <<"EOF"
#!/bin/bash
echo "Running kernel post{inst,rm} hook (simple version) for grub.cfg ..."

dtbfile_link=/etc/default/dtb
# Here we insist on a dtb file path (even though mkgrubcfg_simple.bash
# works without it).
dtbpath_full=$(realpath -e $dtbfile_link)
if [[ -f $dtbpath_full ]]; then
    dtbfile_path=$dtbpath_full
else
    echo "The dtb file (${dtbpath_full}) is missing, exiting."
    exit 1
fi

rootfsPARTUUID=$rootfs_PARTUUID_ dtb_path=$dtbfile_path bash -c '/usr/local/bin/mkgrubcfg_simple.bash'
EOF
)

# This is for fw_printenv,fw_setenv from libubootenv-tool. To read the env you
# must first have executed a setenv at the u-boot prompt (otherwise u-boot uses
# the built-in env). The settings here are for VisionFive 2, cf. e.g.
# https://doc-en.rvspace.org/VisionFive2/Boot_UG/JH7110_SDK/boot_address_allocation.html
fw_env_config=$(cat <<"EOF"
# MTD device name	Device offset	Env. size	Flash sector size	Number of sectors
/dev/mtd1		0x0		0x10000
EOF
)

README_auxbootldr=$(cat <<"EOF"

Petitboot 
---------

It is easy to install the bootmanager/bootloader Petitboot onto this bootfs
and use Petitboot as a middle stage in the booting process. With such an
installation it is possible to have multiple kernels installed to choose from
at the bootmanager prompt and to boot kernels (and Linux OSes) installed on
other attached removable media. For more info on such "bootdisk" booting, see
https://gitlab.com/tripole-inc/bootdisk
EOF
)

# -------------------------------- functions ---------------------------------
# (There is really no reason why this particular code is made into functions.)

install_riscv64_qemu_binary () {
    if [[ $arch_str != "riscv64" ]]; then
        echo -n -e ${i_msg}" Installing local qemu-riscv64-static binary ..."
        qemu_binary_loc=$(which qemu-riscv64-static)
        cp $qemu_binary_loc ${rootfs_mnt}/usr/bin
        echo " Done."
    fi
}

remove_riscv64_qemu_binary () {
    if [[ $arch_str != "riscv64" ]]; then
        echo -n -e ${i_msg}" Removing local qemu-riscv64-static binary ..."
        rm ${rootfs_mnt}/usr/bin/qemu-riscv64-static
        echo " Done."
    fi
}

prepare_for_chroot_jail () {
    echo -n -e ${i_msg}" Preparing for chroot jail ..."
    case $1 in
        "ubuntu")
            echo -e "$ubuntu_custom_inst" >${rootfs_mnt}/root/"ubuntu_custom_inst.bash"
        ;;
        "debian")
            echo -e "$debian_custom_inst" >${rootfs_mnt}/root/"debian_custom_inst.bash"
        ;;
    esac
    chmod 0755 ${rootfs_mnt}/root/"${1}_custom_inst.bash"
    echo " Done."
}

setup_apt_sources () {
    case $1 in
        "ubuntu")
	    if [[ "$ubuntu_edition" == "Jammy" ]]; then
		echo -n -e ${i_msg}" Setting up /etc/apt/sources.list ..."
		rm -f ${rootfs_mnt}/etc/apt/sources.list
                echo -e "$ubuntu_repo_list" >${rootfs_mnt}/etc/apt/sources.list

	    else
		echo -n -e ${i_msg}" Setting up /etc/apt/sources.list.d/ubuntu.sources ..."
		rm -f ${rootfs_mnt}/etc/apt/sources.list
		rm -f ${rootfs_mnt}/etc/apt/sources.list.d/ubuntu.sources
		echo -e "$ubuntu_repo_list_deb822" > ${rootfs_mnt}/etc/apt/sources.list.d/ubuntu.sources
	    fi
        ;;
        "debian")
	    echo -n -e ${i_msg}" Setting up /etc/apt/sources.list.d/debian.sources ..."
	    rm -f ${rootfs_mnt}/etc/apt/sources.list
	    rm -f ${rootfs_mnt}/etc/apt/sources.list.d/debian.sources
            echo -e "$debian_repo_list_deb822" > ${rootfs_mnt}/etc/apt/sources.list.d/debian.sources
        ;;
    esac
    echo " Done."
}

do_chroot_jail_tasks () {
    echo -e ${i_msg}" Entering \033[94mchroot jail\033[0m. Installing some pkgs., running some scripts ..."
    systemd-nspawn -q --resolv-conf=copy-host --timezone=off -D ${rootfs_mnt} \
        /root/"${1}_custom_inst.bash"
   rm ${rootfs_mnt}/root/"${1}_custom_inst.bash"
    sleep 2 # Just to be able to read some of the messages.
    echo -e "Done. Exited \033[94mchroot jail\033[0m."
}

setup_dtb_file () {
    echo -n -e ${i_msg}" Copying the \033[94m${dtbfile_name}\033[0m file to bootfs..."
    kern_name=$(ls ${rootfs_mnt}/boot | grep "${kernel_img_name_short}-")
    kern_vers=$(cut -d '-' -f 2- <<< $kern_name)
    case $1 in
        "ubuntu")
            dtbfile_dir=${rootfs_mnt}/usr/lib/firmware/${kern_vers}/device-tree/${dtb_mfg}
        ;;
        "debian")
            dtbfile_dir=${rootfs_mnt}/usr/lib/linux-image-${kern_vers}/${dtb_mfg}
        ;;
    esac

    dtbfile_loc=${dtbfile_dir}/${dtbfile_name}
    if [[ -f $dtbfile_loc ]]; then
        mkdir -p ${bootfs_mnt}/dtbs/${dtb_mfg}
        cp $dtbfile_loc ${bootfs_mnt}/dtbs/${dtb_mfg}
        echo " Done."
    else
	echo -e " Fail!"
        echo -e ${w_msg}"\nCould not find $dtbfile_name"
        echo " in $dtbfile_dir"
        echo -e ${w_msg}" Device tree file must be set up manually on the image."
    fi
}

setup_distro_specifics () {
    case $1 in
        "ubuntu")
            echo -n -e ${i_msg}" Installing Network Manager configuration files for $iface_name ..."

            nm_conf_dir=${rootfs_mnt}/etc/NetworkManager
            nm_syscon_dir=${nm_conf_dir}/system-connections
            mkdir -p $nm_syscon_dir
            eth0_nmconf_loc=${nm_syscon_dir}/Wired_connection_1.nmconnection
            echo -e "$eth0_nmconf_file"> $eth0_nmconf_loc
            chmod 0600 $eth0_nmconf_loc

            # Perhaps not really needed, who knows...
            alloweth_nmconf_dir=${nm_conf_dir}/conf.d
            mkdir -p $alloweth_nmconf_dir
            alloweth_nmconf_loc=${alloweth_nmconf_dir}/allow-ethernet.conf
            echo -e "$alloweth_nmconf_file" >$alloweth_nmconf_loc
            chmod 0644 $alloweth_nmconf_loc

            echo " Done."

            echo -n -e ${i_msg}" Setting up local host mappings in /etc/hosts ..."
            echo -e "$ubuntu_hosts_file" >${rootfs_mnt}/etc/hosts
            echo " Done."

            # From debootstrap there will be an interfering resolv.conf file
            # which we remove. After leaving the chroot jail below there will
            # also be a leftover resolv.conf but it will be fixed automagically
            # by systemd-resolved.service
            if [[ -f ${rootfs_mnt}/etc/resolv.conf ]]; then
                echo -n -e ${i_msg}" Removing (interfering) pre installed /etc/resolv.conf ..."
                rm ${rootfs_mnt}/etc/resolv.conf
                echo " Done."
            fi

            # The flash-kernel package can cause problems on systems without
            # flash storage or non EFI systems. (At least this was the case on
            # ARM64.)
            echo -n -e ${i_msg}" Preventing apt from installing package flash-kernel ..."
            echo -e "$flashk_block_file" >\
                ${rootfs_mnt}/etc/apt/preferences.d/no-flash-kernel
            echo " Done."
        ;;
        "debian")
            echo -n -e ${i_msg}" Setting up /etc/network/interfaces ..."
            mkdir -p ${rootfs_mnt}/etc/network
            echo -e "$debian_interfaces_file" >\
                ${rootfs_mnt}/etc/network/interfaces
            echo " Done."
    ;;
esac

}

# ---------------------------------- main ------------------------------------

echo -e "\n\033[92m -- Making image for $distro_name ($distro_edition, riscv64) -- \033[0m\n"

imgfile_MiB=$(($imgfile_num_sectors *512/1024/1024)) # Not precise.
desired_MiB=$((14*${imgfile_MiB}/10)) # Approx. space for imgfile +imgfile.xz

cd $imgfile_dir
imgfile_loc=${imgfile_dir}/${imgfile_name}

echo -e "Image container file path (during build):"
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

umask 022

echo -n -e ${i_msg}" Making a directory for temporary files ..."
mkdir -p $tmpfile_dir
echo " Done."

echo -e ${i_msg}" Setting up container file (${imgfile_MiB} MB) ..."
dd if=/dev/zero of=$imgfile_loc bs=512 count=$imgfile_num_sectors conv=fsync status=progress
sync
echo "Done."

echo -n -e ${i_msg}" Setting up loop device for container file ..."
loop_dev=$(losetup -P -f --show ${imgfile_loc})
if [[ -z $loop_dev ]]; then
    echo -e "\n"${e_msg}" The command losetup $imgfile_loc failed, exiting."
    exit 1
fi
echo " Done."

echo -e ${i_msg}" Creating partitions in container file with sfdisk ..."
echo -e "$sfdisk_script" | sfdisk $loop_dev
sync
p4_PARTUUID=$(sfdisk --part-uuid $loop_dev 4 2>/dev/null)
echo "Rootfs PARTUUID: $p4_PARTUUID"
echo "Done."

echo -n -e ${i_msg}" Formatting the container file partitions ..."
mkfs.fat -F32 -n $bootfs_label ${loop_dev}p3 >/dev/null 2>&1
if [[ $rootfs_type == "ext4" ]]; then
    mkfs.ext4 -F -q -U $rootfs_UUID -L $rootfs_label -b 4k -m 0 ${loop_dev}p4 >/dev/null 2>&1
elif [[ $rootfs_type == "btrfs" ]]; then # Only a placeholder for now.
    mkfs.btrfs -f -U $rootfs_UUID -L $rootfs_label -m single ${loop_dev}p4 >/dev/null 2>&1
else
  echo "Oops. Not implemented formatting option for rootfs."
fi
echo " Done."

rootp_msg="\033[94mroot\033[0m"
echo -n -e ${i_msg}" Mounting the $rootp_msg partition inside the container file ..."
mkdir -p $rootfs_mnt
if ! mount ${loop_dev}p4 $rootfs_mnt ; then
    echo -e ${e_msg}" The command mount ${loop_dev}p4 failed, exiting."
    exit 1
fi
sync
echo " Done."

bootp_msg="\033[94mboot\033[0m"
echo -n -e ${i_msg}" Mounting the $bootp_msg partition inside the container file ..."
mkdir -p $bootfs_mnt
if ! mount ${loop_dev}p3 $bootfs_mnt ; then
    echo -e ${e_msg}" The command mount ${loop_dev}p3 failed, exiting."
    exit 1
fi
echo " Done."

echo -e ${i_msg}" Debootstrapping ${distro_name} system to ${rootfs_mnt}"
debootstrap --arch riscv64 --keyring $keyring_file $distro_release $rootfs_mnt $distro_repourl
if [[ $? -ne 0 ]]; then
    echo -e ${e_msg} " Could not complete debootstrapping, exiting."
    exit 1
else
    echo -e ${k_msg}" Done."
fi

echo -n -e ${i_msg}" Setting up the /etc/fstab file..."
echo -e "$fstab_file" >${rootfs_mnt}/etc/fstab
# There is no UUID on a fat partition but in fstab the serial number works.
bootfs_UUID=$(blkid -s UUID -o value ${loop_dev}p3)
fstab_lastline="UUID=${bootfs_UUID}  $bootfs_dir  vfat $bootfs_mnt_opts  0  2"
echo -e "$fstab_lastline" >>${rootfs_mnt}/etc/fstab
echo " Done."

echo -n -e ${i_msg}" Setting the hostname in /etc/hostname ..."
echo -e "$host_name" >${rootfs_mnt}/etc/hostname
echo " Done."

# This script (Canonical) provides an alternative method for resizing rootfs.
echo -e ${i_msg}" Installing script at /usr/local/bin/growpart.sh ..."
wget -P $tmpfile_dir -nv $growpart_url
if [[ $? -ne 0 ]]; then
    echo -e ${w_msg}" Unable to download the script growpart.sh"
else
    cp ${tmpfile_dir}/growpart ${rootfs_mnt}/usr/local/bin/growpart.sh
    chmod 0755 ${rootfs_mnt}/usr/local/bin/growpart.sh
    echo -e ${k_msg}" Done."
fi

echo -n -e ${i_msg}" Setting up directories /boot/extlinux and /boot/grub ..."
mkdir -p -m 0755 ${rootfs_mnt}/boot/extlinux
mkdir -p -m 0755 ${rootfs_mnt}/boot/grub
echo " Done."

echo -n -e ${i_msg}" Setting up symlink /etc/default/dtb to default dtb ..."
mkdir -p ${rootfs_mnt}/etc/default
ln -s ../..${dtbfile_path} ${rootfs_mnt}/etc/default/dtb
echo " Done."

echo -n -e ${i_msg}" Setting up uEnv.txt ..."
echo -e "$uEnv_txt" >${bootfs_mnt}/uEnv.txt
vf2_str=$(grep "visionfive-2" <<< "$dtbfile_name")
if [[ ! -z "$vf2_str" ]]; then
    # On some versions of u-boot on VF2 the file vf2_uEnv.txt is used to hold
    # variables copied to the u-boot environment variable bootenv_sdk during
    # boot and the bootenv_sdk variables are associated with a boot method
    # which is tried before ordinary sysboot (see the u-boot environment).
    # Therefore, either of uEnv.txt or vf2_uEnv.txt should exist if one wants
    # to specify boot variables (u-boot will always complain about the missing
    # one, whichever it is.) Here we choose to install v2f_uEnv.txt
    echo -n " (VF2 install; rename to vf2_uEnv.txt)"
    mv ${bootfs_mnt}/uEnv.txt ${bootfs_mnt}/vf2_uEnv.txt
fi
echo " Done."

echo -n -e ${i_msg}" Setting up /etc/fw_env.config ..."
echo -e "$fw_env_config" >${rootfs_mnt}/etc/fw_env.config
echo " Done."

echo -n -e ${i_msg}" Installing utility scripts in /usr/local/bin ..."
# This script uses grub-mkconfig but it doesn't work inside a loop device.
# (It is installed for later use, to produce fancier grub menus.)
echo -e "$mkgrubcfg" >${rootfs_mnt}/usr/local/bin/mkgrubcfg.bash
chmod 0755 ${rootfs_mnt}/usr/local/bin/mkgrubcfg.bash
# This script produces a basic grub.cfg file and works inside a loop device.
echo -e "$mkgrubcfg_simple" >${rootfs_mnt}/usr/local/bin/mkgrubcfg_simple.bash
chmod 0755 ${rootfs_mnt}/usr/local/bin/mkgrubcfg_simple.bash
echo -e "$mkextlinux_conf" >${rootfs_mnt}/usr/local/bin/mkextlinux_conf.bash
chmod 0755 ${rootfs_mnt}/usr/local/bin/mkextlinux_conf.bash
echo " Done."

# The configure script for Ubuntu's package linux-image-<version>-generic by
# default sets links in /boot but that won't work here since we use fat as
# bootfs file system (mounted under /boot). Debian also sets up links but
# under / (which supports them). In order to solve this dilemma we simply opt
# for disabling links with the following trick (see man 5 kernel-img.conf).
touch ${rootfs_mnt}/etc/kernel-img.conf
echo "do_symlinks = no" >>${rootfs_mnt}/etc/kernel-img.conf

setup_distro_specifics $1

setup_apt_sources $1

prepare_for_chroot_jail $1

install_riscv64_qemu_binary

do_chroot_jail_tasks $1

setup_dtb_file $1

remove_riscv64_qemu_binary

echo -n -e ${i_msg}" Creating extlinux.conf update hook after kernel install/removal ..."
mkdir -p ${rootfs_mnt}/etc/kernel/postinst.d
mkdir -p ${rootfs_mnt}/etc/kernel/postrm.d
echo -e "$extlinux_update_hook" > /${rootfs_mnt}/etc/kernel/postinst.d/update-extlinux-conf
echo -e "$extlinux_update_hook" > /${rootfs_mnt}/etc/kernel/postrm.d/update-extlinux-conf
chmod 0755 ${rootfs_mnt}/etc/kernel/postinst.d/update-extlinux-conf
chmod 0755 ${rootfs_mnt}/etc/kernel/postrm.d/update-extlinux-conf
echo " Done."

echo -e ${i_msg}" Creating /boot/extlinux/extlinux.conf ..."
chroot ${rootfs_mnt} bash -c "rootfs_PARTUUID_=$rootfs_PARTUUID /etc/kernel/postinst.d/update-extlinux-conf"
echo "Done."

echo -n -e ${i_msg}" Creating grub.cfg (simple version) update hook after kernel install/removal ..."
echo -e "$grubcfg_update_hook" > /${rootfs_mnt}/etc/kernel/postinst.d/update-grub-cfg-simple
echo -e "$grubcfg_update_hook" > /${rootfs_mnt}/etc/kernel/postrm.d/update-grub-cfg-simple
chmod 0755 ${rootfs_mnt}/etc/kernel/postinst.d/update-grub-cfg-simple
chmod 0755 ${rootfs_mnt}/etc/kernel/postrm.d/update-grub-cfg-simple
echo " Done."

echo -e ${i_msg}" Creating /boot/grub/grub.cfg (simple version) ..."
chroot ${rootfs_mnt} bash -c "rootfs_PARTUUID_=$rootfs_PARTUUID /etc/kernel/postinst.d/update-grub-cfg-simple"
echo "Done."

echo -n -e ${i_msg}" Setting up /etc/default/zramswap ..."
sed -i "s/.*ALGO=.*/ALGO=${zram_compression}/g" ${rootfs_mnt}/etc/default/zramswap
sed -i "s/.*PERCENT=.*/PERCENT=${zram_percent}/g" ${rootfs_mnt}/etc/default/zramswap
echo " Done."

# Pick up the kernel version before we leave /boot.
kernel_version=$(ls ${bootfs_mnt} | grep -E "vmlinu[x,z]-" | cut -d '-' -f 2-)

cd $imgfile_dir

if [[ -f $root_sshkey_loc ]]; then
    echo -e -n ${i_msg}" Installing key in file \033[94m${root_sshkey_loc}\033[0m as ssh key for root..."
    mkdir -p ${rootfs_mnt}/root/.ssh
    chmod 0700 ${rootfs_mnt}/root/.ssh
    cp $root_sshkey_loc ${rootfs_mnt}/root/.ssh/authorized_keys
    chmod 0600 ${rootfs_mnt}/root/.ssh/authorized_keys
    # Typically, the defaults in sshd_config are;
    # "PermitRootLogin prohibit-password"
    # "PubkeyAuthentication yes"
    # so the only thing we need to do change the line with
    # "PasswordAuthentication".
    sed -i '/.*PasswordAuthentication.*/c\PasswordAuthentication no' \
        ${rootfs_mnt}/etc/ssh/sshd_config
    echo " Done."
fi

if [[ -d $add_dir_loc ]]; then
    echo -e ${i_msg}" Installing the contents of the local directory \033[94m${add_dir_loc}\033[0m to"
    echo -e "         directory \033[94m${add_dir_img}\033[0m on the image..."
    mkdir -p ${rootfs_mnt}/${add_dir_img}
    cp -vR ${add_dir_loc##*/} ${rootfs_mnt}/${add_dir_img}
    echo " Done."
fi

echo -n -e ${i_msg}" Writing info about grub.cfg and alternate kernels ..."
echo -e "$README_kernels" >${rootfs_mnt}/boot/README_kernels.txt
echo " Done."

echo -n -e ${i_msg}" Writing instructions for installing Petitboot ..."
echo -e "$README_auxbootldr" >${bootfs_mnt}/README_auxbootldr.txt
echo " Done."

echo -e ${i_msg}" Unmounting the container file (and file system check)..."
sync
umount -f ${loop_dev}p3
sleep 2
fsck.fat -a ${loop_dev}p3
umount -f ${loop_dev}p4
sleep 2
if [[ $rootfs_type == "ext4" ]]; then
    e2fsck -p ${loop_dev}p4
fi
echo " Done."

echo -n -e ${i_msg}" Disconnecting and removing the loop devices ..."
losetup -d $loop_dev 2>/dev/null 
echo " Done."

imgfile_name_full=${distro_name}_${distro_edition}_${kernel_version}_${img_tag}.img
echo -n -e ${i_msg}" Adding kernel version to image name..."
imgfile_loc_full=${imgfile_dir}/${imgfile_name_full}
mv $imgfile_loc $imgfile_loc_full
echo " Done."

echo -e ${i_msg}" Output file: \033[94m${imgfile_name_full}\033[0m"

if [[ "$docleanup_after" == "yes" ]]; then
    echo -n -e ${i_msg}" Doing final cleanup of build area ..."
    rm -rf $tmpfile_dir
    rmdir $rootfs_mnt
    echo " Done."
fi

if [[ "$compressed_img" == "yes" ]]; then
    echo -e ${i_msg}" Compressing the image using xz compression ..."
    xz -v $imgfile_loc_full
    sleep 1
    echo "Done."
fi

echo -e "\n\033[92m -- $0 finished -- \033[0m\n"
