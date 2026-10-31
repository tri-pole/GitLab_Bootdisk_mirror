#!/bin/bash
#
# debuntu_dbstrap_riscv64.bash
# 26-10-29: v0.18 reference rewrite of v0.16 (by Tripole), mostly by Qwen.
# 26-02-10: v0.16 (by Tripole)
# 24-12-10: v0.13 (by Tripole)
#
# Script to create a (small, CLI) Ubuntu, Debian or Devuan Linux RISCV64 image
# using debootstrap, adding only a small number of items: a bootfs partition
# with a copy of kernel, initramfs, dtb and (u-boot) boot scripts, some scripts
# on rootfs under /etc/kernel/post{inst,rm} to update extlinux.conf on the
# bootfs partition after kernel update and some utility scripts in
# /usr/local/bin to also update grub.cfg. (Optionally, it also has a directory
# with supplementary files, such as a petitboot directory on the bootfs for
# setup of the Petitboot boot loader/manager.)
#
# Target SoC/board: The generated images are tailored to VisionFive 2 but can
# be adapted to other RISCV64 SBCs (by e.g. changing partition layout, dtb).
#
# Booting: The generated images can be booted with board resident (e.g. QSPI)
# openSBI+u-boot using extlinux.conf on the image or by using Petitboot for
# RISCV64 (using grub.cfg on the image). (Petitboot can be installed/set up
# on the image or on e.g. eMMC.) The default partition layout has two leading
# empty 2M+4M partitions for manual add of SPL and openSPI+u-boot, if needed.
#
# Build host: The script is designed to be run (as root) on an Ubuntu build
# host, either virtualized (using qemu-riscv64-static) on x86_64/amd64 or
# natively on RISCV64 (likely to be much slower). (The script probably runs on
# Debian too, at least after some small tweaks, but this is not tested.)
# The build host must have Debian keys installed (see below) and the
# debootstrap package in order to debootstrap Ubuntu and Debian. For Devuan,
# the debootstrap scripts are downloaded automagically by this script.
# Run time is about 17m for Ubuntu and 11m for Debian/Devuan on a modern 8
# thread x86_64 CPU.
#
# Requirements: The script requires basic functionality incl. blkid, dd,
# losetup, mkfs, wget, xz and the pkg. systemd-container (for systemd-nspawn).
# (Most requirements are checked at runtime below.) For "cross-scripting"
# (i.e. for use on another arch than RISCV64) you need to install the package
# qemu-user-static (for qemu-riscv64-static).
#
# Typical workflow: Edit the parameters below and run the script from a temp.
# dir. (the image and all temporary files will be created in this directory.).
#
# Image tested on: VisionFive 2, v1.3b (8GB).
#
# Usage: (as root or w/ sudo) ./debuntu_dbstrap_riscv64.bash <distro>
#        where distro is one of: ubuntu, debian, devuan
#
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
#   need to update grub.cfg and this can be done by using grub-mkimage or
#   via scripts in /usr/local/bin, e.g. the script mkgrubcfg_simple.bash
# - The dtb files on the image are located at
#   /usr/lib/firmware/<kernel version>-generic/device-tree (Ubuntu)
#   /usr/lib/linux-image-<kernel version>-riscv64 (Debian, Devuan)
#   A link to the default dtb must exist as /etc/default/dtb (as set up by this
#   script) in order for the kernel postinst extlinux.conf update hook to work.
# - The dtb file is specified in the devicetree entry in the grub.cfg file
#   (cf. mkgrubcfg_simple.bash). However, bootloaders based on kexec, such as
#   Petitboot, typically allow/let the booted Linux kernel inherit the dtb used
#   by kernel running the bootloader if the devicetree entry is not present
#   (or valid) in the grub.cfg for the kernel to be booted. (This holds at
#   least for the version of Petitboot for RISCV64 provided at Gitlab/Tripole.)
# - The automatic copying of vmlinuz,initrd.img to the bootfs partition after
#   kernel upgrade or initramfs rebuild always copies the newest kernel, initrd
#   (the one with the highest version number), as determined by the sort -V
#   command (cf. scripts in /etc/{kernel/postinst.d,initramfs/postupdate.d}).
# - Networking is handled by NetworkManager on Ubuntu and systemd's networking
#   service on Debian. If you don't want NetworkManager installed on Ubuntu, and
#   thus fall back to netplan, you can remove the string "network-manager" from
#   the commands inside the here-doc below named ubuntu_custom_inst and comment
#   out the relevant sections of the function setup_distro_specifics below.
# - The numbering of the eth interfaces may vary, so try all RJ45 connectors.
# - Domain name resolution is now handled on Ubuntu and Debian by systemd,
#   see e.g. sec 2.1 in https://wiki.archlinux.org/title/Systemd-resolved
# - The package linux-firmware is installed but firmware for e.g. a specific
#   WiFi or Bluetooth chip might not be included and thus have to be sought
#   elsewhere.
# - The snap system on Ubuntu can cause trouble so it might be worth purging it.
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
#   transferred by e.g. cp -a to other media (the only thing that needs to be
#   updated then is the PARTUUID of the root partition listed in /etc/fstab
#   on the rootfs and in /extlinux/extlinux.conf on the bootfs).
# - VisionFive 2 specifics:
#   * There is an issue with the dtb files in that the correct memory size will
#     not be identified when booting with kexec unless the dtb has the correct
#     memory size explicitly specified. (For the default VF2 dtb the mem size
#     is not hard coded, but determined via some "magic" during boot, so after
#     booting with kexec on an 8GB box the memory will often show up as 4GB.)
#     The issue is further explained in the README_petitboot-MEGA at
#     https://mega.nz/folder/WclhUTpJ#jobsjgxDvph2OfXZYwyxOw
#     where also workarounds are offered (not all Linux distros are affected).
#  *  The graphics support is not yet in mainline kernel so in general you
#     have to use serial console or ssh to run the image.
#  *  There is some confusion (stemming from Starfive) about naming regarding
#     uEnv.txt/vf2_uEnv.txt so you might see warnings about it during boot.
#
# - ToDo: Perhaps pass rootPARTUUID via a file on the image (before jail) in
#   order to make in-jail kernel install not depend on hook ordering at all.
#
# For a summary of the changes relative to the previous version (v0.16), see
# CHAMGELOG.md

set -Eeuo pipefail
shopt -s nullglob

# ------------------------------- parameters ---------------------------------

# Top level directory in several of the file hierarchies used below and also
# the location of the disk image container during build (for size, see below).
# (Typically imgfile_dir is the directory in which this script is located.)
imgfile_dir=${WORK_DIR:-$PWD}

ubuntu_name=Ubuntu       # Used for the image name and in grub.cfg
ubuntu_edition=Noble     # Tested with Jammy and Noble.
debian_name=Debian       # Used for the image name and in grub.cfg
debian_edition=Trixie    # Works only w/ Trixie currently (caveat with RISCV64).
devuan_name=Devuan       # Used for the image name and in grub.cfg
devuan_edition=Excalibur # Tested with Excalibur.

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

# If the directory $add_dir_loc exists in $imgfile_dir then $add_dir_loc and its
# contents will be copied to $add_dir_img on the image (rel. to its root lvl.).
add_dir_loc=petitboot
add_dir_img=boot # No leading forward slash here.

# The generated Linux image has a GPT disk label and is partitioned as
# [ part1 (not used), part2 (not used), bootfs, rootfs ]. Details about
# the partitioning are given in the comments in the function create_partitions
# below.
p1_start=4096    # Recommended to not change
p1_size=4096     # Recommended to not change
p2_start=8192    # Recommended to not change
p2_size=8192     # Recommended to not change
p3_start=16384   # Recommended not to change
bootfs_MiB=500   # In general, use at least 300 MiB, 500 MiB recommended.
rootfs_MiB=6000  # In general, use at least 5000 MiB.
rootfs_type=ext4 # Must be ext4 currently (btrfs is a placeholder).

# Compression (xz) of the finished image takes some extra time.
compressed_img=no # {yes,no}

# Do we want to clean up all temporary files and directories afterwards?
docleanup_after=yes # {yes,no}

# Of course, it is often better to use a mirror for the repo downloads, see e.g.
# https://www.debian.org/mirror/list and http://mirrors.ubuntu.com
ubuntu_repourl="http://ports.ubuntu.com/ubuntu-ports"
debian_repourl="http://ftp.debian.org/debian"
devuan_repourl="http://deb.devuan.org/merged"

# Location of Devuan specific debootstrap scripts.
devuan_dbscripts_url="https://pkgmaster.devuan.org/devuan/pool/main/d/debootstrap"
# Current Devuan tarball with debootstrap scripts (update when Devuan does).
devuan_dbscripts_tgz="debootstrap_1.0.145devuan1.tar.gz"

# Link to growpart for resizing second partition (rootfs) to desired size.
growpart_url="https://raw.githubusercontent.com/canonical/cloud-utils/main/bin/growpart"

# The kernel command line actually used (to make extlinux.conf and grub.cfg)
# below will be prepended by the string "root=PARTUUID=${rootfs_PARTUUID}".
# (Kept as a string: it is embedded in the generated scripts as a single
# quoted string, and a kernel command line is naturally a single string.)
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
bootfs_mnt="${rootfs_mnt}${bootfs_dir}"

# Mount options used in the fstab file on the image.
rootfs_mnt_opts="errors=remount-ro"
bootfs_mnt_opts="dmask=0027,errors=remount-ro"

# Some (but not all) commands used below to create the image.
# (The mkfs command for rootfs_type is added in validate_params.)
reqd_cmdlist=("blkid" "dd" "debootstrap" "fsck.fat" "e2fsck" "losetup"
              "mkfs.fat" "mkimage" "sfdisk" "systemd-nspawn" "tar" "wget" "xz"
)

# List of packages to be added to (the ones minimally needed for) the install.
# (These are arrays: the package list is embedded in the generated chroot
# script as a properly quoted bash array, so that a package name with spaces
# or shell metacharacters would not break the generated script.)
ubuntu_extra_packages=("nano" "aptitude" "man-db" "openssh-server")
debian_extra_packages=("aptitude" "man-db" "firmware-linux-free" "openssh-server")
devuan_extra_packages=("aptitude" "man-db" "firmware-linux-free" "openssh-server")

# For running in QEMU the user mode emulation binary qemu-<arch>-static is reqd.
reqd_cmdlist_virt=("qemu-riscv64-static")

# Bling (color in stdout)? Yes, we like. (Colors are only used when this
# parameter is yes and stdout is a terminal.)
enable_color_msg=yes # {yes,no}

# Name of the calling command (used in messages).
calling_cmd_name=${0##*/}

# --------------------------- helpers and traps ------------------------------

if [[ ${enable_color_msg} == "yes" && -t 1 ]]; then
    c_info=$'\033[94m'
    c_warn=$'\033[93m'
    c_err=$'\033[91m'
    c_ok=$'\033[92m'
    c_reset=$'\033[0m'
else
    c_info=""
    c_warn=""
    c_err=""
    c_ok=""
    c_reset=""
fi

log_info() { printf '[%s Info %s] %s\n' "$c_info" "$c_reset" "$*"; }
log_warn() { printf '[%s Warning %s] %s\n' "$c_warn" "$c_reset" "$*" >&2; }
log_err()  { printf '[%s Error %s] %s\n' "$c_err" "$c_reset" "$*" >&2; }
log_ok()   { printf '[%s OK %s] %s\n' "$c_ok" "$c_reset" "$*"; }
banner()   { printf '\n%s-- %s --%s\n' "$c_ok" "$*" "$c_reset"; }

die() {
    log_err "$*"
    exit 1
}

# confirm "Question? [N,y]" -> returns 0 only if the answer is y/Y.
confirm() {
    local ans
    printf '%s ' "$1"
    read -r ans || ans=""
    [[ ${ans,,} == "y" ]]
}

# State variables (the ${var:-} guards in cleanup() make the traps safe even
# if the script dies before they have been set).
build_ok=false
loop_dev=""
loop_attached=false
rootfs_mounted=false
bootfs_mounted=false
imgfile_loc=""
imgfile_loc_full=""
kernel_version=""
root_sshkey_full=""

on_error() {
    local rc=$?
    log_err "Command failed at line $1 (exit code $rc)."
    exit "$rc"
}

cleanup() {
    local rc=$?
    if $build_ok; then
        return 0
    fi
    # On a failed run the host must not be left with mounted partitions or an
    # attached loop device; the work dirs are kept for inspection.
    if $bootfs_mounted; then
        log_warn "Unmounting $bootfs_mnt ..."
        umount -f "$bootfs_mnt" 2>/dev/null ||
            log_err "Could not unmount $bootfs_mnt (do it manually!)"
    fi
    if $rootfs_mounted; then
        log_warn "Unmounting $rootfs_mnt ..."
        umount -f "$rootfs_mnt" 2>/dev/null ||
            log_err "Could not unmount $rootfs_mnt (do it manually!)"
    fi
    if $loop_attached; then
        log_warn "Detaching loop device $loop_dev ..."
        losetup -d "$loop_dev" 2>/dev/null ||
            log_err "Could not detach loop device $loop_dev (do it manually!)"
    fi
    log_warn "Image build did not complete (exit $rc). Work dirs kept for inspection: $imgfile_dir"
    return 0
}

trap 'on_error $LINENO' ERR
trap cleanup EXIT

# --------------------------- preparations/checks ----------------------------

check_host() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root (use sudo), exiting."
    local os_name
    # shellcheck disable=SC1091
    os_name=$(. /etc/os-release && printf '%s' "$NAME")
    [[ $os_name == "Ubuntu" ]] ||
        die "This script must be executed on Ubuntu Linux (host is '$os_name'), exiting."
    arch_str=$(uname -m)
    case $arch_str in
        riscv64|x86_64) ;;
        *) die "The architecture '$arch_str' is not one of x86_64 or riscv64, exiting." ;;
    esac
}

select_distro() {
    # $1: the distro argument (ubuntu, debian or devuan).
    case $1 in
        "ubuntu")
            distro_name=$ubuntu_name
            distro_edition=$ubuntu_edition
            distro_repourl=$ubuntu_repourl
            keyring_file=/usr/share/keyrings/ubuntu-archive-keyring.gpg
            bootfs_label=UBNT_BOOT
            rootfs_label=UBNT_ROOT
            kernel_img_name_short=vmlinuz
            # The VF2 device tree defines ethernet0/ethernet1 aliases, so
            # systemd's predictable naming (used on Ubuntu/Debian) names the
            # interfaces end0/end1, see systemd.netnames(7).
            iface_name=end0
            ;;
        "debian")
            distro_name=$debian_name
            distro_edition=$debian_edition
            distro_repourl=$debian_repourl
            keyring_file=/usr/share/keyrings/debian-archive-keyring.gpg
            bootfs_label=DEBN_BOOT
            rootfs_label=DEBN_ROOT
            kernel_img_name_short=vmlinux
            iface_name=end0 # See the comment in the ubuntu case above.
            # nonfree_list="non-free non-free-firmware"
            ;;
        "devuan")
            distro_name=$devuan_name
            distro_edition=$devuan_edition
            distro_repourl=$devuan_repourl
            keyring_file=/usr/share/keyrings/devuan-archive-keyring.gpg
            bootfs_label=DEVU_BOOT
            rootfs_label=DEVU_ROOT
            kernel_img_name_short=vmlinux
            # Devuan does not use systemd (and thus no systemd udev
            # predictable interface naming), so the legacy name is used.
            iface_name=eth0
            # nonfree_list="non-free non-free-firmware"
            ;;
        *)
            die "Usage: $calling_cmd_name <distro> (one of: ubuntu, debian, devuan)"
            ;;
    esac
    distro=$1
    # For the debootstrapping and the here-docs below we use lowercase.
    distro_release=$(tr '[:upper:]' '[:lower:]' <<< "$distro_edition")
    # This is the name used on the container file during image creation.
    # Before exit of this script, the kernel version is inserted into the name.
    imgfile_name=${distro_name}_${distro_edition}_${img_tag}.img
}

validate_params() {
    case $rootfs_type in
        "ext4")
            reqd_cmdlist+=("mkfs.ext4")
            ;;
        "btrfs")
            log_warn "rootfs_type=btrfs is a placeholder; only ext4 is really supported."
            reqd_cmdlist+=("mkfs.btrfs")
            ;;
        *)
            die "The fstype for the rootfs must be one of ext4 or btrfs, exiting."
            ;;
    esac
    case $compressed_img in yes|no) ;; *) die "compressed_img must be yes or no." ;; esac
    case $docleanup_after in yes|no) ;; *) die "docleanup_after must be yes or no." ;; esac
    case $enable_color_msg in yes|no) ;; *) die "enable_color_msg must be yes or no." ;; esac
    [[ $bootfs_MiB =~ ^[1-9][0-9]*$ ]] || die "bootfs_MiB must be a positive integer."
    [[ $rootfs_MiB =~ ^[1-9][0-9]*$ ]] || die "rootfs_MiB must be a positive integer."
    [[ $zram_percent =~ ^[1-9][0-9]*$ ]] || die "zram_percent must be a positive integer."
    (( zram_percent <= 100 )) || die "zram_percent must be between 1 and 100."
    [[ -n $host_name ]] || die "host_name must not be empty."
    [[ $host_name =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] ||
        die "host_name '$host_name' is not a valid host name."
    [[ -n $dtbfile_name ]] || die "dtbfile_name must not be empty."
    # Consistency of the (fixed) partition start positions.
    (( p2_start == p1_start + p1_size )) || die "p2_start must equal p1_start + p1_size."
    (( p3_start == p2_start + p2_size )) || die "p3_start must equal p2_start + p2_size."
}

check_prereqs() {
    local chk_cmdlist=("${reqd_cmdlist[@]}")
    if [[ $arch_str != "riscv64" ]]; then
        chk_cmdlist+=("${reqd_cmdlist_virt[@]}")
    fi
    local missing=() chk_cmd
    for chk_cmd in "${chk_cmdlist[@]}"; do
        command -v "$chk_cmd" >/dev/null || missing+=("$chk_cmd")
    done
    [[ ${#missing[@]} -eq 0 ]] ||
        die "The required commands are missing: ${missing[*]}"
    if [[ $arch_str != "riscv64" && ! -e /proc/sys/fs/binfmt_misc/qemu-riscv64 ]]; then
        log_warn "No binfmt_misc entry for qemu-riscv64 found; systemd-nspawn will not be able to exec the riscv64 rootfs. Install/enable qemu-user-static."
    fi
    # The keyring file is needed by debootstrap.
    [[ -f $keyring_file ]] ||
        die "The keyring file $keyring_file does not exist (install the corresponding keyring package), exiting."
    # The <distro>-keyring package contains also the keys for the archives/repos.
    case $distro in
        "debian")
            dpkg -s debian-keyring >/dev/null 2>&1 ||
                die "The Debian keyring is not installed (install the debian-keyring package), exiting."
            ;;
        "devuan")
            dpkg -s devuan-keyring >/dev/null 2>&1 ||
                die "The Devuan keyring is not installed (install the devuan-keyring package), exiting."
            ;;
    esac
}

derive_partition_vars() {
    # Remaining partition variables (sizes in sectors of 512 bytes).
    p3_size=$(( bootfs_MiB * 1024 * 1024 / 512 ))
    p4_start=$(( p3_start + p3_size + 1 ))
    p4_size=$(( rootfs_MiB * 1024 * 1024 / 512 ))
    # shellcheck disable=SC2034
    gpt_bu_start=$(( p4_start + p4_size + 1 )) # Trailing GPT backup table (info only).
    gpt_bu_size=34
    imgfile_num_sectors=$(( p1_start + p1_size + p2_size + p3_size + p4_size + gpt_bu_size ))
    imgfile_MiB=$(( imgfile_num_sectors * 512 / 1024 / 1024 )) # Not precise.
}

generate_uuids() {
    # UUIDs can also be generated with the cmd uuidgen from the pkg uuid-runtime.
    local uuid_file=/proc/sys/kernel/random/uuid
    [[ -r $uuid_file ]] || die "Cannot read $uuid_file."
    rootfs_UUID=$(< "$uuid_file")     # Used in rootfs, /etc/fstab
    # Lowercase, which is the canonical form (kernel, blkid and lsblk report
    # PARTUUIDs in lowercase; sfdisk/fdisk in uppercase). create_partitions()
    # verifies (case-insensitively) that this is the value sfdisk wrote.
    rootfs_PARTUUID=$(< "$uuid_file") # Used in extlinux.conf, grub.cfg
    eth0nm_UUID=$(< "$uuid_file")     # Used in Ubuntu.
    [[ -n $rootfs_UUID && -n $rootfs_PARTUUID && -n $eth0nm_UUID ]] ||
        die "Cannot generate valid UUIDs from kernel random source, exiting."
}

# --------------------------------- image build ------------------------------

space_prompt() {
    log_info "Make sure that you have enough free space: up to ~${required_MiB} MiB +some."
    echo "This is what you have:"
    df -h
    if confirm "Is this enough? [N,y] "; then
        log_ok "Continuing."
    else
        die "Not enough space (or so you say), exiting."
    fi
}

make_image_file() {
    log_info "Setting up container file (${imgfile_MiB} MiB) ..."
    dd if=/dev/zero of="$imgfile_loc" bs=512 count="$imgfile_num_sectors" \
        conv=fsync status=progress ||
        die "Could not create the image file $imgfile_loc."
    sync
    log_ok "Done."
}

setup_loop_device() {
    log_info "Setting up loop device for container file ..."
    loop_dev=$(losetup -P -f --show "$imgfile_loc") ||
        die "The command 'losetup -P -f --show $imgfile_loc' failed."
    [[ -n $loop_dev ]] || die "Could not determine the loop device for $imgfile_loc."
    loop_attached=true
    log_ok "Done: $loop_dev"
}

create_partitions() {
    # The partition layout here is the same as the layout used on StarFive's
    # Debian images, which is documented in [1]. In this layout, the first
    # partition is intended to hold the binary u-boot.spl.bin.normal.out and
    # the second partition is intended to hold the binary fw_payload, see [2].
    # The first binary here is the SPL (based on u-boot) and the second binary
    # is a FIT image containing fw_firmware.bin, which in turn is a combo of
    # openSBI and u-boot.bin (see [2]). The software components just described
    # correspond to distinct functions performed in the boot flow of VisionFive
    # 2, see e.g. Fig. 2.7 in [2] or Fig. 2.1 in [3]. (This boot flow is a
    # variation of the standard u-boot flow, see e.g. slides 12, 28 in [4] (for
    # nomenclature see [5]). The variation is due to the need for openSBI on the
    # riscv64 arch, see e.g. slide 13 in [6].) The third and fourth partitions
    # are the boot and system partitions, respectively. We recreate here the
    # StarFive partition layout structure but without installing SPL and
    # openSPI+u-boot. (These items can later be manually added, if desired, see
    # Sec. 3.8.3 ("Updating SPL and U-Boot of SD Card and eMMC") in [6]).
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
    log_info "Creating partitions in container file with sfdisk ..."
    sfdisk "$loop_dev" <<EOF
label: gpt
first-lba: $p1_start
1 : start=${p1_start}, size=${p1_size}, type=2E54B353-1271-4842-806F-E436D6AF6985, name=spl
2 : start=${p2_start}, size=${p2_size}, type=5B193300-FC78-40CD-8002-E86C45580B47, name=uboot
3 : start=${p3_start}, size=${p3_size}, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=image
4 : start=${p4_start}, size=${p4_size}, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=root, uuid=$rootfs_PARTUUID
EOF
    sync
    # Sanity check: the PARTUUID of partition 4 must be the one used in the
    # image (it is set in the sfdisk script above). sfdisk (libfdisk) reports
    # GPT PARTUUIDs in uppercase (it uses uuid_unparse_upper) while
    # rootfs_PARTUUID (from the kernel random source) is lowercase, so the
    # comparison must be case-insensitive. The lowercase form is the canonical
    # one here: the kernel stores and reports it lowercase (efi_guid_to_str()
    # uses %pUl) and the libblkid-based tools blkid and lsblk print it in
    # lowercase as well. The kernel's root=PARTUUID= matching is also
    # case-insensitive (strncasecmp in block/early-lookup.c), so the lowercase
    # PARTUUID embedded in extlinux.conf/grub.cfg is found at boot.
    local p4_PARTUUID
    p4_PARTUUID=$(sfdisk --part-uuid "$loop_dev" 4 2>/dev/null || true)
    if [[ ${p4_PARTUUID,,} != "${rootfs_PARTUUID,,}" ]]; then
        die "The PARTUUID of partition 4 ('$p4_PARTUUID') differs from the one used in the image ('$rootfs_PARTUUID'); the booted system will not be able to find the root partition."
    fi
    log_info "Rootfs PARTUUID: $rootfs_PARTUUID"
    log_ok "Done."
}

format_partitions() {
    log_info "Formatting the container file partitions ..."
    mkfs.fat -F32 -n "$bootfs_label" "${loop_dev}p3" ||
        die "mkfs.fat of ${loop_dev}p3 failed."
    if [[ $rootfs_type == "ext4" ]]; then
        mkfs.ext4 -F -q -U "$rootfs_UUID" -L "$rootfs_label" -b 4k -m 0 "${loop_dev}p4" ||
            die "mkfs.ext4 of ${loop_dev}p4 failed."
    elif [[ $rootfs_type == "btrfs" ]]; then # Only a placeholder for now.
        mkfs.btrfs -f -U "$rootfs_UUID" -L "$rootfs_label" -m single "${loop_dev}p4" ||
            die "mkfs.btrfs of ${loop_dev}p4 failed."
    else
        die "Not implemented formatting option for rootfs (rootfs_type=$rootfs_type)."
    fi
    log_ok "Done."
}

mount_partitions() {
    log_info "Mounting the root partition inside the container file ..."
    mkdir -p "$rootfs_mnt"
    mount "${loop_dev}p4" "$rootfs_mnt" ||
        die "The command 'mount ${loop_dev}p4 $rootfs_mnt' failed."
    rootfs_mounted=true
    sync
    log_ok "Done."
    log_info "Mounting the boot partition inside the container file ..."
    mkdir -p "$bootfs_mnt"
    mount "${loop_dev}p3" "$bootfs_mnt" ||
        die "The command 'mount ${loop_dev}p3 $bootfs_mnt' failed."
    bootfs_mounted=true
    log_ok "Done."
}

debuntu_debootstrap() {
    # Used for both ubuntu and debian.
    log_info "Debootstrapping ${distro_name} system to ${rootfs_mnt}"
    debootstrap --arch riscv64 --keyring "$keyring_file" \
        "$distro_release" "$rootfs_mnt" "$distro_repourl" ||
        die "Debootstrapping ${distro_name} failed."
    log_ok "Done."
}

devuan_debootstrap() {
    log_info "Downloading the Devuan debootstrap scripts ..."
    wget -P "$tmpfile_dir" -nv "${devuan_dbscripts_url}/${devuan_dbscripts_tgz}" ||
        die "Unable to download the Devuan debootstrap scripts from ${devuan_dbscripts_url}/${devuan_dbscripts_tgz}."
    tar -xzf "${tmpfile_dir}/${devuan_dbscripts_tgz}" -C "$tmpfile_dir" ||
        die "Failed to unpack the Devuan debootstrap scripts tarball."
    log_ok "Done."
    log_info "Debootstrapping ${distro_name} system to ${rootfs_mnt}"
    # The downloaded debootstrap script needs its companion functions file.
    # (The files come from the official Devuan debootstrap package tarball.)
    # shellcheck disable=SC1091
    source "${tmpfile_dir}/source/functions"
    "${tmpfile_dir}/source/debootstrap" --arch riscv64 --keyring "$keyring_file" \
        "$distro_release" "$rootfs_mnt" "$distro_repourl" \
        "${tmpfile_dir}/source/scripts/${distro_release}" ||
        die "Debootstrapping ${distro_name} failed."
    log_ok "Done."
}

# --------------------------- file templates ----------------------------------
#
# The templates below are expanded at run time, i.e. after the parameters
# (UUIDs, distro, etc.) have been set up in main(). The generated files are
# written with the write_template() function below, i.e. with printf, not
# with echo -e, so that backslash sequences in the file content (e.g. the
# \/ escapes in the devuan /etc/inittab sed command) are not mangled.

# Write a (template) string to a file, adding a trailing newline.
write_template() {
    local dest=$1 content=$2
    printf '%s\n' "$content" > "$dest" ||
        die "Could not write to $dest."
}

# Build a space-separated, shell-quoted list of the args (using printf %q),
# for embedding in the generated chroot install scripts below.
pkg_list_str() {
    local out=() p
    for p in "$@"; do
        out+=("$(printf '%q' "$p")")
    done
    printf '%s' "${out[*]}"
}

generate_templates() {
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

    # Only used with manual configuration (/etc/resolv.conf).
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
    alloweth_nmconf_file=$(cat <<'EOF'
[keyfile]
unmanaged-devices=*,except:type:wifi,except:type:gsm,except:type:cdma,except:type:ethernet
EOF
    )

    ubuntu_repo_list=$(cat <<EOF
deb http://ports.ubuntu.com/ubuntu-ports/ $distro_release main restricted
deb http://ports.ubuntu.com/ubuntu-ports/ ${distro_release}-updates main restricted

deb http://ports.ubuntu.com/ubuntu-ports/ $distro_release universe
deb http://ports.ubuntu.com/ubuntu-ports/ ${distro_release}-updates universe

deb http://ports.ubuntu.com/ubuntu-ports/ ${distro_release} multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ ${distro_release}-updates multiverse

# deb http://ports.ubuntu.com/ubuntu-ports/ ${distro_release}-backports main restricted universe multiverse

deb http://ports.ubuntu.com/ubuntu-ports/ ${distro_release}-security main restricted
deb http://ports.ubuntu.com/ubuntu-ports/ ${distro_release}-security universe
deb http://ports.ubuntu.com/ubuntu-ports/ ${distro_release}-security multiverse
EOF
    )

    ubuntu_repo_list_deb822=$(cat <<EOF
Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports
Suites: $distro_release ${distro_release}-updates ${distro_release}-backports
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports
Suites: ${distro_release}-security
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
    )

    flashk_block_file=$(cat <<'EOF'
Package: flash-kernel
Pin: release *
Pin-Priority: -1
EOF
    )

    # This is the basic (default) set of packages installed on top of the rootfs.
    # (If you want to add packages, edit the array ubuntu_extra_packages above.)
    ubuntu_custom_inst=$(cat <<EOF
#!/bin/bash
set -Eeuo pipefail

apt-get update
# The linux-headers-generic package can be added if desired.
DEBIAN_FRONTEND=noninteractive apt -y install linux-image-generic
echo "Setting FSTYPE to $rootfs_type in /etc/initramfs-tools/initramfs.conf"
sed -i "s/.*FSTYPE=.*/FSTYPE=${rootfs_type}/g" /etc/initramfs-tools/initramfs.conf
DEBIAN_FRONTEND=noninteractive apt -y install dialog network-manager usbutils zram-tools
extra_packages=($(pkg_list_str "${ubuntu_extra_packages[@]}"))
DEBIAN_FRONTEND=noninteractive apt -y install "\${extra_packages[@]}"
dpkg-reconfigure tzdata
dpkg-reconfigure locales
dpkg-reconfigure keyboard-configuration

printf 'Set password for \033[91mroot:\033[0m\n'
until passwd; do echo "Try again."; done
EOF
    )

    debian_repo_list_deb822=$(cat <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: $distro_release ${distro_release}-updates
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: ${distro_release}-security
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    )

    devuan_repo_list_deb822=$(cat <<EOF
Types: deb
URIs: http://deb.devuan.org/merged
Suites: $distro_release ${distro_release}-backports ${distro_release}-proposed-updates ${distro_release}-updates
Components: main non-free contrib non-free-firmware
Signed-By: /usr/share/keyrings/devuan-archive-keyring.gpg
Enabled: yes

Types: deb
URIs: http://deb.devuan.org/merged
Suites: ${distro_release}-security
Components: main non-free contrib non-free-firmware
Signed-By: /usr/share/keyrings/devuan-archive-keyring.gpg
Enabled: yes
EOF
    )

    # This is the basic (default) set of packages installed on top of the rootfs.
    # (If you want to add packages, edit the array debian_extra_packages above.)
    debian_custom_inst=$(cat <<EOF
#!/bin/bash
set -Eeuo pipefail

apt-get update

# The linux-headers-riscv64 package can be added if desired.
DEBIAN_FRONTEND=noninteractive apt -y install linux-image-riscv64
echo "Setting FSTYPE to $rootfs_type in /etc/initramfs-tools/initramfs.conf"
sed -i "s/.*FSTYPE=.*/FSTYPE=${rootfs_type}/g" /etc/initramfs-tools/initramfs.conf
DEBIAN_FRONTEND=noninteractive apt -y install locales systemd-timesyncd usbutils zram-tools
extra_packages=($(pkg_list_str "${debian_extra_packages[@]}"))
DEBIAN_FRONTEND=noninteractive apt -y install "\${extra_packages[@]}"
dpkg-reconfigure tzdata
dpkg-reconfigure locales
apt -y install console-setup
# dpkg-reconfigure keyboard-configuration

printf 'Set password for \033[91mroot:\033[0m\n'
until passwd; do echo "Try again."; done
EOF
    )

    # This is the basic (default) set of packages installed on top of the rootfs.
    # (If you want to add packages, edit the array devuan_extra_packages above.)
    devuan_custom_inst=$(cat <<EOF
#!/bin/bash
set -Eeuo pipefail

apt-get update

# The linux-headers-riscv64 package can be added if desired.
DEBIAN_FRONTEND=noninteractive apt -y install linux-image-riscv64
echo "Setting FSTYPE to $rootfs_type in /etc/initramfs-tools/initramfs.conf"
sed -i "s/.*FSTYPE=.*/FSTYPE=${rootfs_type}/g" /etc/initramfs-tools/initramfs.conf
echo "Enabling serial console login (T0) in /etc/inittab."
sed -i "s/.*T0.*/T0:23:respawn:\/sbin\/getty -L ttyS0 115200 screen/g" /etc/inittab
DEBIAN_FRONTEND=noninteractive apt -y install locales ntpsec u-boot-tools zram-tools
extra_packages=($(pkg_list_str "${devuan_extra_packages[@]}"))
DEBIAN_FRONTEND=noninteractive apt -y install "\${extra_packages[@]}"
dpkg-reconfigure tzdata
dpkg-reconfigure locales
apt -y install console-setup

printf 'Set password for \033[91mroot:\033[0m\n'
until passwd; do echo "Try again."; done
EOF
    )

    # We split this file in two; one part with parameter substitution and one w/o.
    mkextlinux_conf_p1=$(cat <<EOF
#!/bin/bash
set -Eeuo pipefail
shopt -s nullglob

# Scans for vmlinu[x,z]-* in /boot and sets up an extlinux.conf file in
# /boot/extlinux
#
# Usage: /usr/local/bin/mkextlinux_conf.bash /boot/path/to/dtb/file where
# /boot/path/to/dtb/file is the full path under /boot to the dtb file.
#
# The dtb path can be a symlink and it can also be given in the environment
# variable dtb_path (command line has precedence). The full dtb path will be
# inserted into extlinux.conf. The script is normally run from a mounted rootfs
# and then the PARTUUID of the rootfs is discovered using the blkid command
# (see below). However, for use inside a chroot jail the rootfs PARTUUID can
# also be given as an environment variable rootfsPARTUUID on the command line,
# like so (note the single quotes):
# chroot . /bin/bash -c 'rootfsPARTUUID=f3cab04c-...-faec36aace3f /usr/local/bin/mkextlinux_conf.bash /boot/path/to/dtb/file'

# The kernel command line parameters here may need tweaking.
kernel_cmdline_pars_="$kernel_cmdline_opts"
EOF
    )

    mkextlinux_conf_p2=$(cat <<'EOF1'

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: /usr/local/bin/mkextlinux_conf.bash /boot/path/to/dtb/file"
    echo "  where /boot/path/to/dtb/file is the full path (under /boot) to the dtb file."
    echo "  The path can alternatively be given in the environment variable dtb_path"
    echo "  (command line has precedence). More info inside the script."
    exit 0
fi

if [[ $# -eq 0 && -z ${dtb_path:-} ]]; then
    echo "A dtb file (or link) must be supplied, either as a command line argument"
    echo "or in the environment variable dtb_path."
    exit 1
fi

if [[ $# -eq 1 ]]; then
    dtb_path=$1
elif [[ $# -gt 1 ]]; then
    echo "Too many arguments (expected at most one), exiting."
    exit 1
else
    echo "Using environment variable dtb_path: $dtb_path"
fi

if ! dtbpath_full=$(realpath -e -- "$dtb_path"); then
    echo "The dtb file ($dtb_path) is missing, exiting."
    exit 1
fi
dtbpath_rel_boot=${dtbpath_full#/boot/}

# To use this script on a machine where the kernel image or initrd has some
# other naming convention, change the settings below.
kernel_name_template="vmlinu[xz]"
initrd_name_template="initrd.img"

# shellcheck disable=SC1091
. /etc/os-release
distro_name_lc=$ID
distro_edition_lc=${VERSION_CODENAME:-}
distro_num=${VERSION_ID:-}

# First letter to uppercase.
distro_name="$(tr '[:lower:]' '[:upper:]' <<< "${distro_name_lc:0:1}")""${distro_name_lc:1}"
distro_edition="$(tr '[:lower:]' '[:upper:]' <<< "${distro_edition_lc:0:1}")""${distro_edition_lc:1}"

if [[ -n $distro_edition ]]; then
    menu_title="--- $distro_name $distro_num ($distro_edition) ---"
else
    menu_title="--- $distro_name $distro_num ---"
fi

if [[ -z ${rootfsPARTUUID:-} ]]; then
    # (The '|| var=' guards keep set -e from aborting on a failed findmnt or
    # blkid (e.g. in a chroot jail whose /dev lacks the device node) so that
    # the explicit check below can report a useful error instead of a bare
    # non-zero exit code.)
    rootfs_dev=$(findmnt -n -o SOURCE / 2>/dev/null) || rootfs_dev=""
    rootfs_partuuid=$(blkid -s PARTUUID -o value "$rootfs_dev" 2>/dev/null) || rootfs_partuuid=""
    [[ -n $rootfs_partuuid ]] || {
        echo "Could not determine the PARTUUID of the root device ($rootfs_dev), exiting."
        exit 1
    }
else
    rootfs_partuuid=$rootfsPARTUUID
fi

# The next line is a default kernel command line and may have to be adjusted for each kernel.
kernel_cmdline_rootfspartuuid="root=PARTUUID=${rootfs_partuuid}"
if [[ -n $kernel_cmdline_pars_ ]]; then
    kernel_cmdline="${kernel_cmdline_rootfspartuuid} ${kernel_cmdline_pars_}"
else
    kernel_cmdline="$kernel_cmdline_rootfspartuuid"
fi

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
	# (When only one entry is present, only that one will show, without title.)
	TIMEOUT 20
	EOF

# (A here-string is used instead of a process substitution because /dev/fd
# does not exist in a debootstrapped rootfs (it is a symlink set up by
# systemd/udev at boot) and /proc is not mounted in the chroot.)
kernel_list=()
while IFS= read -r kernel_name; do
    [[ -n $kernel_name ]] || continue
    kernel_list+=("$kernel_name")
done <<< "$(ls | grep -E "${kernel_name_template}-" | sort -V || true)"

if [[ ${#kernel_list[@]} -eq 0 ]]; then
    echo "No kernel image (vmlinu[x,z]-*) found in /boot, exiting."
    exit 1
fi

item_counter=0
default_label=""
for kernel_name in "${kernel_list[@]}"; do
    item_counter=$((item_counter + 1))

    kernel_vers=$(cut -d '-' -f 2- <<< "$kernel_name")
    initrd_name="${initrd_name_template}-${kernel_vers}"

    label=$kernel_name

    add_msg="Added extlinux.conf menu entry: $label"
    if [[ $item_counter -eq 1 ]]; then
        default_label=$label
        add_msg="$add_msg (default)"
    fi

	# Note: The leading tabs in the here-document below are important.
	cat <<-EOF >> extlinux/extlinux.conf
	
	LABEL $label
	  LINUX  /${kernel_name}
	  INITRD /${initrd_name}
	  FDT    /${dtbpath_rel_boot}
	  APPEND $kernel_cmdline
	
	EOF

    echo "$add_msg"
done

sed -i "s/DEBNT_DEFAULT/$default_label/g" /boot/extlinux/extlinux.conf

EOF1
    )

    mkextlinux_conf="${mkextlinux_conf_p1}""${mkextlinux_conf_p2}"

    # This will go into a script in /etc/kernel/post{inst,rm}.d
    extlinux_update_hook=$(cat <<'EOF'
#!/bin/bash
set -Eeuo pipefail

echo "Running kernel post{inst,rm} hook for extlinux.conf ..."

dtbfile_link=/etc/default/dtb
if ! dtbpath_full=$(realpath -e -- "$dtbfile_link"); then
    echo "The dtb file ($dtbfile_link) is missing, exiting."
    exit 1
fi

rootfsPARTUUID="${rootfs_PARTUUID_:-}" dtb_path="$dtbpath_full" \
    bash -c '/usr/local/bin/mkextlinux_conf.bash'
EOF
    )

    # Template uEnv.txt but using values for VF2.
    uEnv_txt=$(cat <<'EOF'
# For StarFive's VisionFive 2, taken from VF2 SBC S/W Tech Ref. Man.
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

    README_kernels=$(cat <<'EOF'
The scripts in /usr/local/bin can be used to assist in kernel handling.
For booting via grub the script mkgrubcfg_simple.bash can be used to generate
simple grub entries for kernels and accompanying initramfses in /boot (see
instructions inside the script generating this image). (See also the kernel
update hook scripts in /etc/kernel/{postinst,postrm}.d)
EOF
    )

    mkgrubcfg=$(cat <<EOF
#!/bin/bash
set -Eeuo pipefail

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
set -Eeuo pipefail
shopt -s nullglob

# Scans for kernel image files and makes a simple grub.cfg file in /boot/grub
#
# Usage: /usr/local/bin/mkgrubcfg_simple.bash /boot/path/to/dtb/file
#   where /boot/path/to/dtb/file is the full path under /boot to the dtb file.
#
# The full dtb path is the path as it appears on a running system. The path can
# be a symlink (e.g. /etc/default/dtb) and it can alternatively be given in the
# environment variable dtb_path (command line has precedence). The full dtb path
# will be inserted into grub.cfg in the form it appears on a non running system
# (i.e. without the leading /boot part of the path if a separate boot partition
# is used; this is controlled by a parameter below). If no dtb path is given, a
# grub.cfg is created with only a placeholder for the path. This script is
# normally run from a mounted rootfs and then the PARTUUID of the rootfs is
# discovered using the blkid command (see below). However, for use inside a
# chroot jail the rootfs PARTUUID can also be given as an environment variable
# rootfsPARTUUID on the command line, like so:
# chroot . /bin/bash -c 'rootfsPARTUUID=f3cab04c-...-faec36aace3f /usr/local/bin/mkgrubcfg_simple.bash /boot/path/to/dtb/file'

# First defined at script generation time. Edit to taste.
kernel_cmdline_pars_="$kernel_cmdline_opts"
EOF
    )

    mkgrubcfg_simple_p2=$(cat <<'EOF1'

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: /usr/local/bin/mkgrubcfg_simple.bash /boot/path/to/dtb/file"
    echo "  where /boot/path/to/dtb/file is the full path (under /boot) to the dtb file."
    echo "  The path can alternatively be given in the environment variable dtb_path"
    echo "  (command line has precedence). More info inside the script."
    exit 0
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
elif [[ $# -gt 1 ]]; then
    echo "Too many arguments (expected at most one), exiting."
    exit 1
else
    dtb_path=${dtb_path:-}
    echo "Using environment variable dtb_path: $dtb_path"
fi

# In grub.cfg it is not always necessary to specify the dtb file, for instance
# when grub.cfg is used during a kexec call where no new dtb is to be loaded
# (in which case the the already loaded dtb is reused).
devicetree_str="# devicetree /path/to/dtbfile # not used currently"
devicetree_msg="Devicetree:  No dtb file specified or dtb file missing."
dtbpath_full=""
if [[ -n $dtb_path ]]; then
    dtbpath_full=$(realpath -e -- "$dtb_path" 2>/dev/null) || true
fi
if [[ -f $dtbpath_full ]]; then
    dtbpath_rel_boot=${dtbpath_full#/boot} # Remove leading "/boot" by default.
    dtbpath_in_grubcfg=${dtb_path_prefix}${dtbpath_rel_boot}
    devicetree_str="devicetree $dtbpath_in_grubcfg"
    devicetree_msg="Devicetree:  $dtbpath_full"
fi

# To use this script on a machine where the kernel image or initrd has some
# other naming convention, change the settings below.
kernel_name_template="vmlinu[xz]"
initrd_name_template="initrd.img"

# shellcheck disable=SC1091
. /etc/os-release
distro_name_lc=$ID
distro_edition_lc=${VERSION_CODENAME:-}
distro_num=${VERSION_ID:-}

# First letter to uppercase.
distro_name="$(tr '[:lower:]' '[:upper:]' <<< "${distro_name_lc:0:1}")""${distro_name_lc:1}"
distro_edition="$(tr '[:lower:]' '[:upper:]' <<< "${distro_edition_lc:0:1}")""${distro_edition_lc:1}"

if [[ -z ${rootfsPARTUUID:-} ]]; then
    # (The '|| var=' guards keep set -e from aborting on a failed findmnt or
    # blkid (e.g. in a chroot jail whose /dev lacks the device node) so that
    # the explicit check below can report a useful error instead of a bare
    # non-zero exit code.)
    rootfs_dev=$(findmnt -n -o SOURCE / 2>/dev/null) || rootfs_dev=""
    rootfs_partuuid=$(blkid -s PARTUUID -o value "$rootfs_dev" 2>/dev/null) || rootfs_partuuid=""
    [[ -n $rootfs_partuuid ]] || {
        echo "Could not determine the PARTUUID of the root device ($rootfs_dev), exiting."
        exit 1
    }
else
    rootfs_partuuid=$rootfsPARTUUID
fi

# The next line is a default kernel command line and may have to be adjusted for each kernel.
kernel_cmdline_rootfspartuuid="root=PARTUUID=${rootfs_partuuid}"
if [[ -n $kernel_cmdline_pars_ ]]; then
    kernel_cmdline="${kernel_cmdline_rootfspartuuid} ${kernel_cmdline_pars_}"
else
    kernel_cmdline="$kernel_cmdline_rootfspartuuid"
fi

echo "Parameters used to set up grub.cfg :"
echo "$devicetree_msg"
echo "Rootfs PARTUUID: $rootfs_partuuid"
echo "Kernel cmd line: $kernel_cmdline"

cd /boot

if [[ -f grub/grub.cfg ]]; then
    mv grub/grub.cfg grub/grub.cfg.bak
fi

# (A here-string is used instead of a process substitution because /dev/fd
# does not exist in a debootstrapped rootfs (it is a symlink set up by
# systemd/udev at boot) and /proc is not mounted in the chroot.)
kernel_list=()
while IFS= read -r kernel_name; do
    [[ -n $kernel_name ]] || continue
    kernel_list+=("$kernel_name")
done <<< "$(ls | grep -E "${kernel_name_template}-" | sort -V || true)"

if [[ ${#kernel_list[@]} -eq 0 ]]; then
    echo "No kernel image (vmlinu[x,z]-*) found in /boot, exiting."
    exit 1
fi

for kernel_name in "${kernel_list[@]}"; do
    kernel_vers=$(cut -d '-' -f 2- <<< "$kernel_name")
    initrd_name="${initrd_name_template}-${kernel_vers}"

    kernel_path_in_grubcfg=${kernel_path_prefix}/${kernel_name}
    initrd_path_in_grubcfg=${initrd_path_prefix}/${initrd_name}

    if [[ -n $distro_edition ]]; then
        menuentry_str="$distro_name $distro_num ($distro_edition) kernel $kernel_vers"
    else
        menuentry_str="$distro_name $distro_num kernel $kernel_vers"
    fi

	# Note: The leading tabs in the here-document below are important.
	cat <<-EOF >> grub/grub.cfg
	menuentry "$menuentry_str" {
	
	linux  $kernel_path_in_grubcfg $kernel_cmdline
	initrd $initrd_path_in_grubcfg
	$devicetree_str
	
	}
	
	EOF

    echo "Added grub.cfg menu entry: $menuentry_str"
done
EOF1
    )

    mkgrubcfg_simple="${mkgrubcfg_simple_p1}""${mkgrubcfg_simple_p2}"

    # This will go into a script in /etc/kernel/post{inst,rm}.d
    grubcfg_update_hook=$(cat <<'EOF'
#!/bin/bash
set -Eeuo pipefail

echo "Running kernel post{inst,rm} hook (simple version) for grub.cfg ..."

dtbfile_link=/etc/default/dtb
# Here we insist on a dtb file path (even though mkgrubcfg_simple.bash
# works without it).
if ! dtbpath_full=$(realpath -e -- "$dtbfile_link"); then
    echo "The dtb file ($dtbfile_link) is missing, exiting."
    exit 1
fi

rootfsPARTUUID="${rootfs_PARTUUID_:-}" dtb_path="$dtbpath_full" \
    bash -c '/usr/local/bin/mkgrubcfg_simple.bash'
EOF
    )

    # This is for fw_printenv,fw_setenv from libubootenv-tool. To read the env you
    # must first have executed a setenv at the u-boot prompt (otherwise u-boot uses
    # the built-in env). The settings here are for VisionFive 2, cf. e.g.
    # https://doc-en.rvspace.org/VisionFive2/Boot_UG/JH7110_SDK/boot_address_allocation.html
    fw_env_config=$(cat <<'EOF'
# MTD device name	Device offset	Env. size	Flash sector size	Number of sectors
/dev/mtd1		0x0		0x10000
EOF
    )

    README_auxbootldr=$(cat <<'EOF'

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
}

# ------------------------- rootfs file setup --------------------------------

setup_fstab() {
    log_info "Setting up the /etc/fstab file ..."
    write_template "${rootfs_mnt}/etc/fstab" "$fstab_file"
    # There is no UUID on a fat partition but in fstab the serial number works.
    local bootfs_UUID
    bootfs_UUID=$(blkid -s UUID -o value "${loop_dev}p3") ||
        die "Could not determine the UUID of the bootfs partition (${loop_dev}p3)."
    [[ -n $bootfs_UUID ]] || die "The bootfs partition has an empty UUID."
    printf 'UUID=%s  %s  vfat %s  0  2\n' "$bootfs_UUID" "$bootfs_dir" "$bootfs_mnt_opts" \
        >> "${rootfs_mnt}/etc/fstab"
    log_ok "Done."
}

setup_hostname() {
    log_info "Setting the hostname in /etc/hostname ..."
    printf '%s\n' "$host_name" > "${rootfs_mnt}/etc/hostname"
    log_ok "Done."
}

install_growpart_script() {
    # This script (Canonical) provides an alternative method for resizing rootfs.
    log_info "Installing script at /usr/local/bin/growpart.sh ..."
    if wget -P "$tmpfile_dir" -nv "$growpart_url"; then
        cp "${tmpfile_dir}/growpart" "${rootfs_mnt}/usr/local/bin/growpart.sh"
        chmod 0755 "${rootfs_mnt}/usr/local/bin/growpart.sh"
        log_ok "Done."
    else
        log_warn "Unable to download the script growpart.sh from $growpart_url; skipping."
    fi
}

setup_boot_dirs() {
    log_info "Setting up directories /boot/extlinux and /boot/grub ..."
    mkdir -p "${rootfs_mnt}/boot/extlinux" "${rootfs_mnt}/boot/grub"
    chmod 0755 "${rootfs_mnt}/boot/extlinux" "${rootfs_mnt}/boot/grub"
    log_ok "Done."
}

setup_dtb_link() {
    log_info "Setting up symlink /etc/default/dtb to default dtb ..."
    mkdir -p "${rootfs_mnt}/etc/default"
    ln -sf "../..${dtbfile_path}" "${rootfs_mnt}/etc/default/dtb"
    log_ok "Done."
}

setup_uenv_txt() {
    log_info "Setting up uEnv.txt ..."
    write_template "${bootfs_mnt}/uEnv.txt" "$uEnv_txt"
    # On some versions of u-boot on VF2 the file vf2_uEnv.txt is used to hold
    # variables copied to the u-boot environment variable bootenv_sdk during
    # boot and the bootenv_sdk variables are associated with a boot method
    # which is tried before ordinary sysboot (see the u-boot environment).
    # Therefore, either of uEnv.txt or vf2_uEnv.txt should exist if one wants
    # to specify boot variables (u-boot will always complain about the missing
    # one, whichever it is.) Here we choose to install vf2_uEnv.txt.
    if [[ $dtbfile_name == *visionfive-2* ]]; then
        log_info "(VF2 install; renaming uEnv.txt to vf2_uEnv.txt)"
        mv "${bootfs_mnt}/uEnv.txt" "${bootfs_mnt}/vf2_uEnv.txt"
    fi
    log_ok "Done."
}

setup_fw_env_config() {
    log_info "Setting up /etc/fw_env.config ..."
    write_template "${rootfs_mnt}/etc/fw_env.config" "$fw_env_config"
    log_ok "Done."
}

install_utility_scripts() {
    log_info "Installing utility scripts in /usr/local/bin ..."
    # This script uses grub-mkconfig but it doesn't work inside a loop device.
    # (It is installed for later use, to produce fancier grub menus.)
    write_template "${rootfs_mnt}/usr/local/bin/mkgrubcfg.bash" "$mkgrubcfg"
    # This script produces a basic grub.cfg file and works inside a loop device.
    write_template "${rootfs_mnt}/usr/local/bin/mkgrubcfg_simple.bash" "$mkgrubcfg_simple"
    # This script produces an extlinux.conf file (for u-boot) in /boot/extlinux.
    write_template "${rootfs_mnt}/usr/local/bin/mkextlinux_conf.bash" "$mkextlinux_conf"
    chmod 0755 "${rootfs_mnt}/usr/local/bin/mkgrubcfg.bash" \
               "${rootfs_mnt}/usr/local/bin/mkgrubcfg_simple.bash" \
               "${rootfs_mnt}/usr/local/bin/mkextlinux_conf.bash"
    log_ok "Done."
}

setup_kernel_img_conf() {
    # The configure script for Ubuntu's package linux-image-<version>-generic
    # by default sets links in /boot but that won't work here since we use fat
    # as bootfs file system (mounted under /boot). Debian also sets up links
    # but under / (which supports them). In order to solve this dilemma we
    # simply opt for disabling links with the following trick (see man 5
    # kernel-img.conf).
    touch "${rootfs_mnt}/etc/kernel-img.conf"
    echo "do_symlinks = no" >> "${rootfs_mnt}/etc/kernel-img.conf"
}

setup_distro_specifics() {
    case $distro in
        "ubuntu")
            log_info "Installing Network Manager configuration files for $iface_name ..."
            local nm_conf_dir="${rootfs_mnt}/etc/NetworkManager"
            local nm_syscon_dir="${nm_conf_dir}/system-connections"
            mkdir -p "$nm_syscon_dir"
            local eth0_nmconf_loc="${nm_syscon_dir}/Wired_connection_1.nmconnection"
            write_template "$eth0_nmconf_loc" "$eth0_nmconf_file"
            chmod 0600 "$eth0_nmconf_loc"
            # Perhaps not really needed, who knows...
            local alloweth_nmconf_dir="${nm_conf_dir}/conf.d"
            mkdir -p "$alloweth_nmconf_dir"
            local alloweth_nmconf_loc="${alloweth_nmconf_dir}/allow-ethernet.conf"
            write_template "$alloweth_nmconf_loc" "$alloweth_nmconf_file"
            chmod 0644 "$alloweth_nmconf_loc"
            log_ok "Done."

            log_info "Setting up local host mappings in /etc/hosts ..."
            write_template "${rootfs_mnt}/etc/hosts" "$ubuntu_hosts_file"
            log_ok "Done."

            # From debootstrap there will be an interfering resolv.conf file
            # which we remove. After leaving the chroot jail below there will
            # also be a leftover resolv.conf but it will be fixed automagically
            # by systemd-resolved.service.
            if [[ -f ${rootfs_mnt}/etc/resolv.conf ]]; then
                log_info "Removing (interfering) pre installed /etc/resolv.conf ..."
                rm -f "${rootfs_mnt}/etc/resolv.conf"
                log_ok "Done."
            fi

            # The flash-kernel package can cause problems on systems without
            # flash storage or non EFI systems. (At least this was the case on
            # ARM64.)
            log_info "Preventing apt from installing package flash-kernel ..."
            write_template "${rootfs_mnt}/etc/apt/preferences.d/no-flash-kernel" "$flashk_block_file"
            log_ok "Done."
            ;;
        "debian" | "devuan")
            log_info "Setting up /etc/network/interfaces ..."
            mkdir -p "${rootfs_mnt}/etc/network"
            write_template "${rootfs_mnt}/etc/network/interfaces" "$debian_interfaces_file"
            log_ok "Done."
            ;;
    esac
}

setup_apt_lists() {
    case $distro in
        "ubuntu")
            if [[ $ubuntu_edition == "Jammy" ]]; then
                log_info "Setting up /etc/apt/sources.list ..."
                rm -f "${rootfs_mnt}/etc/apt/sources.list"
                write_template "${rootfs_mnt}/etc/apt/sources.list" "$ubuntu_repo_list"
            else
                log_info "Setting up /etc/apt/sources.list.d/ubuntu.sources ..."
                rm -f "${rootfs_mnt}/etc/apt/sources.list"
                rm -f "${rootfs_mnt}/etc/apt/sources.list.d/ubuntu.sources"
                write_template "${rootfs_mnt}/etc/apt/sources.list.d/ubuntu.sources" "$ubuntu_repo_list_deb822"
            fi
            log_ok "Done."
            ;;
        "debian")
            log_info "Setting up /etc/apt/sources.list.d/debian.sources ..."
            rm -f "${rootfs_mnt}/etc/apt/sources.list"
            rm -f "${rootfs_mnt}/etc/apt/sources.list.d/debian.sources"
            write_template "${rootfs_mnt}/etc/apt/sources.list.d/debian.sources" "$debian_repo_list_deb822"
            log_ok "Done."
            ;;
        "devuan")
            log_info "Setting up /etc/apt/sources.list.d/devuan.sources ..."
            rm -f "${rootfs_mnt}/etc/apt/sources.list"
            rm -f "${rootfs_mnt}/etc/apt/sources.list.d/devuan.sources"
            write_template "${rootfs_mnt}/etc/apt/sources.list.d/devuan.sources" "$devuan_repo_list_deb822"
            log_ok "Done."
            ;;
    esac
}

prepare_for_chroot_jail() {
    log_info "Preparing for chroot jail ..."
    local inst_script
    case $distro in
        "ubuntu") inst_script="$ubuntu_custom_inst" ;;
        "debian") inst_script="$debian_custom_inst" ;;
        "devuan") inst_script="$devuan_custom_inst" ;;
    esac
    write_template "${rootfs_mnt}/root/${distro}_custom_inst.bash" "$inst_script"
    chmod 0755 "${rootfs_mnt}/root/${distro}_custom_inst.bash"
    log_ok "Done."
}

install_riscv64_qemu_binary() {
    if [[ $arch_str != "riscv64" ]]; then
        log_info "Installing local qemu-riscv64-static binary ..."
        local qemu_binary_loc
        qemu_binary_loc=$(command -v qemu-riscv64-static) ||
            die "qemu-riscv64-static not found (install the package qemu-user-static)."
        cp "$qemu_binary_loc" "${rootfs_mnt}/usr/bin" ||
            die "Could not copy $qemu_binary_loc to the image."
        log_ok "Done."
    fi
}

do_chroot_jail_tasks() {
    log_info "Entering chroot jail. Installing some pkgs., running some scripts ..."
    # The install script runs interactive programs (dpkg-reconfigure tzdata,
    # locales, keyboard-configuration and passwd), which need a console with
    # working input inside the container. nspawn's default console mode gives
    # the container an interactive pty-based console only when BOTH its stdin
    # and stdout are TTYs; when this script's stdout is piped, for instance
    # when it is run as
    #     ./debuntu_dbstrap_riscv64.bash ubuntu 2>&1 | tee logfile
    # nspawn falls back to a non-interactive console (read-only pty in
    # systemd <= 258, plain pipe in later versions): the ncurses menus are
    # still displayed, but keystrokes are not forwarded into the container,
    # so e.g. the arrow keys are just echoed by the terminal as "^[[A" /
    # "^[[B" instead of moving the cursor. (Mechanism: the console mode
    # resolution in src/nspawn/nspawn.c and the PTY_FORWARD_READ_ONLY flag in
    # src/shared/ptyfwd.c of the systemd source; verified against systemd
    # 259.) To keep the menus usable also with a teed (or otherwise piped)
    # stdout we force the interactive console mode, which allocates a pty in
    # the container and forwards keystrokes from our stdin (putting it in raw
    # mode) into the container. This only makes sense when our stdin is a
    # TTY, so the switch is added conditionally.
    local -a nspawn_args=(-q --resolv-conf=copy-host --timezone=off -D "$rootfs_mnt")
    if [[ -t 0 ]]; then
        nspawn_args+=("--console=interactive")
    fi
    systemd-nspawn "${nspawn_args[@]}" "/root/${distro}_custom_inst.bash" ||
        die "The systemd-nspawn chroot install run failed (see the log above)."
    rm -f "${rootfs_mnt}/root/${distro}_custom_inst.bash"
    sleep 2 # Just to be able to read some of the messages.
    log_ok "Done. Exited chroot jail."
}

# ----------------------------- image finalization ---------------------------

setup_dtb_file() {
    log_info "Copying the $dtbfile_name file to bootfs ..."
    local kern_name kern_vers dtbfile_dir newest
    # (The glob is intentional; nullglob is set at the top of the script.)
    # shellcheck disable=SC2206
    local kernel_imgs=( "${rootfs_mnt}"/boot/${kernel_img_name_short}-* )
    [[ ${#kernel_imgs[@]} -gt 0 ]] ||
        die "No kernel image ($kernel_img_name_short-*) found in ${rootfs_mnt}/boot."
    newest=$(printf '%s\n' "${kernel_imgs[@]}" | sort -V | tail -n 1)
    kern_name=${newest##*/}
    kern_vers=$(cut -d '-' -f 2- <<< "$kern_name")
    case $distro in
        "ubuntu")
            dtbfile_dir="${rootfs_mnt}/usr/lib/firmware/${kern_vers}/device-tree/${dtb_mfg}"
            ;;
        *)
            dtbfile_dir="${rootfs_mnt}/usr/lib/linux-image-${kern_vers}/${dtb_mfg}"
            ;;
    esac
    if [[ -f ${dtbfile_dir}/${dtbfile_name} ]]; then
        mkdir -p "${bootfs_mnt}/dtbs/${dtb_mfg}"
        cp "${dtbfile_dir}/${dtbfile_name}" "${bootfs_mnt}/dtbs/${dtb_mfg}"
    else
        die "Could not find $dtbfile_name in $dtbfile_dir (the device tree file must be set up manually on the image)."
    fi
    log_ok "Done."
}

remove_riscv64_qemu_binary() {
    if [[ $arch_str != "riscv64" ]]; then
        log_info "Removing local qemu-riscv64-static binary ..."
        rm -f "${rootfs_mnt}/usr/bin/qemu-riscv64-static"
        log_ok "Done."
    fi
}

# Note: this hook must be installed AFTER the chroot jail run (cf. the order
# in main()). If it is present inside the jail, dpkg runs it during the kernel
# install there, but then the rootfs PARTUUID cannot be discovered (the
# jail's default /dev has no block device nodes, so blkid fails) and the
# kernel package configuration is aborted. After the jail, the hook is run
# explicitly by create_extlinux_conf() with the PARTUUID passed via the
# environment variable rootfs_PARTUUID_.
create_extlinux_upd_hook() {
    log_info "Creating extlinux.conf update hook after kernel install/removal ..."
    local hook_dir hook_file
    for hook_dir in postinst.d postrm.d; do
        hook_file="${rootfs_mnt}/etc/kernel/${hook_dir}/update-extlinux-conf"
        mkdir -p "${rootfs_mnt}/etc/kernel/${hook_dir}"
        write_template "$hook_file" "$extlinux_update_hook"
        chmod 0755 "$hook_file"
    done
    log_ok "Done."
}

create_extlinux_conf() {
    log_info "Creating /boot/extlinux/extlinux.conf ..."
    chroot "$rootfs_mnt" bash -c \
        "rootfs_PARTUUID_='$rootfs_PARTUUID' /etc/kernel/postinst.d/update-extlinux-conf" ||
        die "Could not create /boot/extlinux/extlinux.conf (see the log above)."
    log_ok "Done."
}

# Note: this hook must be installed AFTER the chroot jail run (cf. the order
# in main()). If it is present inside the jail, dpkg runs it during the kernel
# install there, but then the rootfs PARTUUID cannot be discovered (the
# jail's default /dev has no block device nodes, so blkid fails) and the
# kernel package configuration is aborted. After the jail, the hook is run
# explicitly by create_grubcfg() with the PARTUUID passed via the environment
# variable rootfs_PARTUUID_.
create_grub_upd_hook() {
    log_info "Creating grub.cfg (simple version) update hook after kernel install/removal ..."
    local hook_dir hook_file
    for hook_dir in postinst.d postrm.d; do
        hook_file="${rootfs_mnt}/etc/kernel/${hook_dir}/update-grub-cfg-simple"
        mkdir -p "${rootfs_mnt}/etc/kernel/${hook_dir}"
        write_template "$hook_file" "$grubcfg_update_hook"
        chmod 0755 "$hook_file"
    done
    log_ok "Done."
}

create_grubcfg() {
    log_info "Creating /boot/grub/grub.cfg (simple version) ..."
    chroot "$rootfs_mnt" bash -c \
        "rootfs_PARTUUID_='$rootfs_PARTUUID' /etc/kernel/postinst.d/update-grub-cfg-simple" ||
        die "Could not create /boot/grub/grub.cfg (see the log above)."
    log_ok "Done."
}

setup_zramswap() {
    log_info "Setting up /etc/default/zramswap ..."
    local zramswap_file="${rootfs_mnt}/etc/default/zramswap"
    [[ -f $zramswap_file ]] || die "The file $zramswap_file does not exist on the image."
    sed -i "s/.*ALGO=.*/ALGO=${zram_compression}/g" "$zramswap_file"
    sed -i "s/.*PERCENT=.*/PERCENT=${zram_percent}/g" "$zramswap_file"
    log_ok "Done."
}

detect_kernel_version() {
    # Pick up the kernel version before we leave /boot.
    # (The glob is intentional; nullglob is set at the top of the script.)
    # shellcheck disable=SC2206
    local kernel_imgs=( "$bootfs_mnt"/vmlinu[xz]-* )
    [[ ${#kernel_imgs[@]} -gt 0 ]] || die "Could not determine the kernel version from $bootfs_mnt."
    local newest
    newest=$(printf '%s\n' "${kernel_imgs[@]}" | sort -V | tail -n 1)
    kernel_version=${newest##*/vmlinu[xz]-}
    log_info "Kernel version: $kernel_version"
}

install_root_sshkey() {
    log_info "Installing key in file $root_sshkey_full as ssh key for root ..."
    mkdir -p "${rootfs_mnt}/root/.ssh"
    chmod 0700 "${rootfs_mnt}/root/.ssh"
    cp "$root_sshkey_full" "${rootfs_mnt}/root/.ssh/authorized_keys"
    chmod 0600 "${rootfs_mnt}/root/.ssh/authorized_keys"
    # Typically, the defaults in sshd_config are;
    # "PermitRootLogin prohibit-password"
    # "PubkeyAuthentication yes"
    # so the only thing we need to do is change the line with
    # "PasswordAuthentication".
    sed -i '/.*PasswordAuthentication.*/c\PasswordAuthentication no' \
        "${rootfs_mnt}/etc/ssh/sshd_config"
    log_ok "Done."
}

install_add_dir() {
    local add_dir_name=${add_dir_loc##*/}
    local add_dir_full="${imgfile_dir}/${add_dir_name}"
    if [[ -d $add_dir_full ]]; then
        log_info "Installing the contents of the local directory $add_dir_full to directory $add_dir_img on the image ..."
        mkdir -p "${rootfs_mnt}/${add_dir_img}"
        cp -Rv "$add_dir_full" "${rootfs_mnt}/${add_dir_img}"
        log_ok "Done."
    else
        log_warn "The local directory $add_dir_full does not exist; nothing installed."
    fi
}

write_readmes() {
    log_info "Writing info about grub.cfg and alternate kernels ..."
    write_template "${rootfs_mnt}/boot/README_kernels.txt" "$README_kernels"
    log_info "Writing instructions for installing Petitboot ..."
    write_template "${bootfs_mnt}/README_auxbootldr.txt" "$README_auxbootldr"
    log_ok "Done."
}

unmount_container_file() {
    log_info "Unmounting the container file (and file system check) ..."
    sync
    umount -f "${loop_dev}p3"
    sleep 2
    # fsck.fat exit codes: 0 = no errors, 1 = errors corrected, 2 = errors not
    # corrected, 4/8/16 = operational errors.
    local rc=0
    fsck.fat -a "${loop_dev}p3" || rc=$?
    if [[ $rc -gt 1 ]]; then
        die "fsck.fat of ${loop_dev}p3 failed (exit code $rc)."
    fi
    umount -f "${loop_dev}p4"
    sleep 2
    if [[ $rootfs_type == "ext4" ]]; then
        # e2fsck exit codes: 0 = clean, 1 = errors corrected, 2 = errors not
        # corrected, 4/8/16 = operational errors.
        rc=0
        e2fsck -p "${loop_dev}p4" || rc=$?
        if [[ $rc -gt 1 ]]; then
            die "e2fsck of ${loop_dev}p4 failed (exit code $rc)."
        fi
    fi
    bootfs_mounted=false
    rootfs_mounted=false
    log_ok "Done."
}

detach_loop_device() {
    log_info "Disconnecting and removing the loop devices ..."
    losetup -d "$loop_dev" ||
        log_warn "Could not detach $loop_dev (do it manually!)."
    loop_attached=false
    log_ok "Done."
}

finalize_image() {
    imgfile_name_full="${distro_name}_${distro_edition}_${kernel_version}_${img_tag}.img"
    log_info "Adding kernel version to image name ..."
    imgfile_loc_full="${imgfile_dir}/${imgfile_name_full}"
    if [[ -f $imgfile_loc_full ]]; then
        log_warn "The file $imgfile_loc_full already exists; moving it to ${imgfile_loc_full}.bak"
        mv "$imgfile_loc_full" "${imgfile_loc_full}.bak"
    fi
    mv "$imgfile_loc" "$imgfile_loc_full"
    log_ok "Done."
    log_info "Output file: $imgfile_name_full"
    if [[ $compressed_img == "yes" ]]; then
        log_info "Compressing the image using xz compression ..."
        xz -v "$imgfile_loc_full" ||
            die "The xz compression of $imgfile_loc_full failed."
        log_ok "Done."
    fi
}

cleanup_work_dirs() {
    if [[ $docleanup_after == "yes" ]]; then
        log_info "Doing final cleanup of build area ..."
        # (The mounts have been removed, so the dirs are empty; rm -rf is used
        # because rmdir of rootfs_mnt would fail on the leftover (empty) boot dir.)
        rm -rf "$tmpfile_dir" "$rootfs_mnt"
        log_ok "Done."
    fi
}

# ---------------------------------- main ------------------------------------

main() {
    check_host
    select_distro "${1:-}"
    validate_params
    check_prereqs
    derive_partition_vars
    generate_uuids
    generate_templates

    cd "$imgfile_dir"
    imgfile_loc="${imgfile_dir}/${imgfile_name}"
    root_sshkey_full="${imgfile_dir}/${root_sshkey_loc}"

    banner "Making image for $distro_name ($distro_edition, riscv64)"

    log_info "Image container file path (during build): $imgfile_loc"
    local required_MiB
    if [[ $compressed_img == "no" ]]; then
        required_MiB=$imgfile_MiB
    else
        log_info "The finished (compressed) image file will be at (w/ kernel version inserted): ${imgfile_loc}.xz"
        required_MiB=$(( 14 * imgfile_MiB / 10 )) # Approx. space for imgfile + imgfile.xz
    fi
    space_prompt

    banner "Starting the installation"
    umask 022

    log_info "Making a directory for temporary files ..."
    mkdir -p "$tmpfile_dir"
    log_ok "Done."

    make_image_file
    # Note: create_partitions() runs sfdisk on the loop device (not on the
    # container file), which makes the kernel re-read the loop device's
    # partition table, so attaching the loop device first is fine here. If
    # this is ever changed to sfdisk/parted on the container file, the
    # partitioning must happen before setup_loop_device (or a partition
    # re-read must be forced afterwards, e.g. with blockdev --rereadpt),
    # otherwise the <loop_dev>pN device nodes are never created and the later
    # mkfs of the loop device partitions fails with "No such file or
    # directory".
    setup_loop_device
    create_partitions
    format_partitions
    mount_partitions

    if [[ $distro == "devuan" ]]; then
        devuan_debootstrap
    else
        debuntu_debootstrap
    fi

    setup_fstab
    setup_hostname
    install_growpart_script
    setup_boot_dirs
    setup_dtb_link
    setup_uenv_txt
    setup_fw_env_config
    install_utility_scripts
    setup_kernel_img_conf
    setup_distro_specifics
    setup_apt_lists
    prepare_for_chroot_jail
    install_riscv64_qemu_binary
    do_chroot_jail_tasks
    setup_dtb_file
    remove_riscv64_qemu_binary
    # (The two update hooks below must be installed after the chroot jail
    # run; cf. the comments above create_extlinux_upd_hook() and
    # create_grub_upd_hook(). They must also come after setup_dtb_file so
    # that the dtb file exists (and the /etc/default/dtb symlink resolves)
    # when the hooks are run by create_extlinux_conf() and create_grubcfg().)
    create_extlinux_upd_hook
    create_extlinux_conf
    create_grub_upd_hook
    create_grubcfg
    setup_zramswap
    detect_kernel_version

    if [[ -f $root_sshkey_full ]]; then
        install_root_sshkey
    else
        log_warn "The ssh key file $root_sshkey_full does not exist; no ssh key installed."
    fi
    install_add_dir
    write_readmes

    unmount_container_file
    detach_loop_device
    finalize_image
    cleanup_work_dirs

    build_ok=true
    banner "Finished"
}

main "$@"
