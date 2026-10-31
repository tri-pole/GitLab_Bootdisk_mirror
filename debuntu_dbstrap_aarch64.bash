#!/bin/bash
#
# debuntu_dbstrap_aarch64.bash
# 26-10-31: v0.18 (Tripole) Option to build also Devuan.
# 26-10-30: v0.17 reference rewrite of v0.15 (by Tripole), mostly by Qwen.
# 25-12-08: v0.15 (by Tripole)
# 23-06-12: v0.13 (by Tripole)
#
# Script to create a (small, CLI) Ubuntu, Debian or Devuan Linux AARCH64 image
# using debootstrap, adding only a few items: a vfat bootfs partition (mounted
# at /boot/bootfs on the image) with a copy of kernel, initramfs and dtb,
# (u-boot) boot scripts and chainloader binaries for u-boot.ext, scripts on
# rootfs under /etc/kernel/postinst.d and /etc/initramfs/post-update.d to
# update the kernel/initramfs copies on the bootfs partition after kernel
# update (and a hook to update grub.cfg), and some utility scripts in
# /usr/local/bin.
#
# Target SoC/board: The generated images are mainly intended for Amlogic based
# TV-boxes/SBCs, but the simple partition layout (a leading gap, a vfat bootfs
# partition and the rootfs partition) works on a large number of small ARM64
# computers.
#
# Booting: The generated images can be booted with the resident/vendor u-boot
# (on eMMC) using the boot scripts on the image, with chainloading via
# u-boot.ext as the default first method (see s905_autoscript on the bootfs),
# or also with e.g. Petitboot/u-root (placed on the same or separate medium)
# since the image has a valid grub.cfg.
#
# Build host: The script is designed to be run (as root) on an Ubuntu build
# host, either natively on aarch64/ARM64 or virtualized (using
# qemu-aarch64-static) on x86_64/amd64. (The script probably runs on Debian
# too, but this is not tested.) The build host must have the Debian keys
# installed (see below) and the debootstrap package. For Devuan, the
# debootstrap scripts are downloaded automagically by this script.
#
# Requirements: The script requires basic functionality incl. blkid, dd,
# debootstrap, losetup, mkfs, parted, mkimage, wget, xz and the pkg
# systemd-container (for systemd-nspawn). (Most requirements are checked at
# runtime below.) For "cross-scripting" (i.e. for use on another arch than
# aarch64/ARM64) you need to install the package qemu-user-static (for
# qemu-aarch64-static).
#
# Typical workflow: Edit the parameters below and run the script from a temp.
# dir. (the image and all temporary files will be created in this directory).
# If the file specified by uboot_ext_local exists in this directory, it will
# be installed on the image as the default u-boot.ext (there are also several
# u-boot.bin candidates from Ophub installed on the image that may serve as
# u-boot.ext when booting via chainloading). A root ssh key file specified by
# root_sshkey_loc can also be supplied in this directory.
#
# Image tested on: Ugoos AM6 plus (s922x) for booting and running the image,
# and on QEMU (qemu-system-x86_64 (host) and qemu-system-aarch64 (chroot
# jail)) for developing/building the image.
#
# Usage: (as root or w/ sudo) ./debuntu_dbstrap_aarch64.bash <distro>
#        where distro is one of: ubuntu, debian, devuan
#
# Notes:
# - The installed system is fairly "bare-bones"; e.g. no swap is set (only
#   zram). A swapfile is easy to set up and can coexist with zram (see
#   /etc/fstab). Info about (re)configuring zram (and optionally set up swap)
#   can be found e.g. in /etc/default/zramswap and https://wiki.debian.org/ZRam
# - During execution of the script (near the end) you will be asked to
#   configure (dpkg-reconfigure) some items: time zone, locale, keyboard and
#   set root pw. (The localizations can later be adjusted with
#   dpkg-reconfigure.)
# - Booting via u-boot boot scripts: This involves chainloading with
#   u-boot.ext (see below; several variants are supplied on the image).
#   Chainloading is the first boot method in the boot configuration file
#   s905_autoscript on the boot partition. If the u-boot env of the
#   resident/vendor u-boot (on eMMC) is not set up to parse s905_autoscript,
#   then the boot scripts in env on eMMC can be updated with the scripts in
#   aml_autoscript on the boot partition. Such an update is done by recovery
#   boot ("reset/toothpick" boot). (In this boot mode the reset pin is pushed
#   and held during the first part of the boot process which forces boot from
#   SD and thereby parsing of aml_autoscript and loading of new scripts into
#   u-boot env. This has been a standard procedure used to get Linux running
#   on TV-boxes.) The chainloader u-boot.ext is a binary file placed on the
#   boot partition. Many candidates (for different SoCs) that can be used as
#   u-boot.ext are included on the image in the /u-boot-ophub directory on the
#   bootfs. Note: chainloading is also useful when the resident u-boot is not
#   capable of handling newer compression methods of kernel and initramfs. In
#   order to boot without chainloading it is general (for TV-boxes) necessary
#   to set up legacy (u-boot) boot scripts (boot.scr, boot.ini, uEnv.ini
#   etc.) and generate u-boot tagged versions of the kernel and initramfs
#   (this is the fallback boot method in s905_autoscript). (For info about
#   this, see e.g. the Armbian folder in
#   https://github.com/FauthD/amlogic-u-boot-scripts/tree/main and check
#   boot.scr which is a text file with a u-boot tag (binary) header.) On the
#   other hand, if a newer version of u-boot is installed on eMMC, e.g. a
#   mainline version, it is likely that it can use extlinux.conf directly for
#   booting and chainloading as well as legacy boot scripts become
#   unnecessary.
# - When booting via grub.cfg on rootfs (e.g. using bootdisk) the file
#   grub.cfg needs updating after upgrading the kernel; this is now done
#   automatically by the hook in /etc/kernel/post{inst,rm}.d (simple version)
#   and can also be done manually with grub-mkconfig or via the scripts in
#   /usr/local/bin, e.g. mkgrubcfg_simple.bash.
# - The dtb file is copied to the top level of the bootfs partition upon image
#   creation and is referenced from extlinux.conf (FDT tag) and, if present,
#   from grub.cfg (devicetree tag). However, bootloaders based on kexec, such
#   as Petitboot/u-root, typically let the booted Linux image inherit the dtb
#   used by the bootloader, cf. the README files at Gitlab about
#   Petitboot/u-root.
# - The automatic copying of vmlinuz,initrd.img to the bootfs partition after
#   kernel upgrade or initramfs rebuild always copies the newest kernel,
#   initrd (the one with the highest version number), as determined by the
#   sort -V command (cf. scripts in
#   /etc/{kernel/postinst.d,initramfs/post-update.d}).
# - Networking is handled by NetworkManager on Ubuntu and by the ifupdown
#   mechanism (/etc/network/interfaces) on Debian.
# - The numbering of the eth interfaces may vary, so try all RJ45 connectors.
# - On some boxes it is necessary to run (as user) the script g12_sound.sh to
#   get sound working. (Afterwards, check for soundcards with e.g. aplay -L)
# - The package linux-firmware is installed but firmware for e.g. a specific
#   WiFi or Bluetooth chip might not be included and thus have to be sought
#   elsewhere.
# - The snap system on Ubuntu can cause trouble so it might be worth purging
#   it. A simple working desktop can be obtained by installing e.g.
#   xubuntu-core (with e.g. lightdm, chosen at install time) or
#   ubuntu-desktop-minimal (gdm). Another alternative is kubuntu-desktop.
# - Run time for this script is about 15m for Debian (excl. compression) on a
#   modern computer with good network connectivity. For Ubloatu, it can take
#   almost three times that (check it e.g. with the time command).
# - Pro tip: Generate the image cheaply, say 6G rootfs (so that burn to
#   SD/USB goes quickly). Then, enlarge the rootfs partition on the SD/USB.
#   This can be done on first boot by using the growpart tool (see below).
#   Alternatively, it can be done before first boot by using either gparted
#   (GUI) or (CLI) with the combo of parted, e2fsck and resize2fs like so:
#   parted /dev/sdX resizepart 2 50% ; e2fsck -f /dev/sdX2 ; resize2fs /dev/sdX2
# - The disk (resized or not) is valid as an MBR partitioned disk but it can
#   easily be converted to GPT: First, start gdisk; gdisk /dev/sdX, and gdisk
#   will tell you that it has found a valid MBR and a missing (or corrupt
#   GPT), and it will ask you which one to use. Choose the MBR. At the gdisk
#   prompt then enter the command "r" which will take you to the recovery and
#   transformation options. There, enter the command "f" to load the MBR and
#   build a fresh GPT from it. At last, exit gdisk with "w" (write).
# - Domain name resolution is now handled (also on Debian) by systemd, see
#   e.g. sec 2.1 in https://wiki.archlinux.org/title/Systemd-resolved
# - A recent version of debian-archive-keyring is required on the host.
#
# - ToDo: Perhaps pass rootPARTUUID via a file on the image (before jail) in
#   order to make in-jail kernel install not depend on hook ordering at all.
#
# For a summary of the changes relative to the previous version (v0.15), see
# CHANGELOG.md

set -Eeuo pipefail
shopt -s nullglob

# ------------------------------- parameters ---------------------------------

# Top level directory in several of the file hierarchies used below and also
# the location of the disk image container during build (for size, see below).
# (Typically imgfile_dir is the directory in which this script is located.)
imgfile_dir=${WORK_DIR:-$PWD}

ubuntu_name=Ubuntu       # Used for the image name and in grub.cfg
ubuntu_edition=Noble     # Tested with Focal, Jammy and Noble.
debian_name=Debian       # Used for the image name and in grub.cfg
debian_edition=Trixie    # Tested with Bullseye, Bookworm and Trixie.
devuan_name=Devuan       # Used for the image name and in grub.cfg
devuan_edition=Excalibur # Tested with Excalibur.

# The image tag will be added to img. name after distro name and kernel version.
img_tag=3pole-$(date +"%y%m%d")

# Host name for image.
host_name=debu

# The dtb file name used in extlinux.conf for booting. (The file must exist in
# the aarch64 tree under /usr/lib/.../amlogic on the image, i.e. as it comes
# in the kernel package; the exact location is set up in setup_dtb_file
# below.)
dtbfile_name=meson-g12b-gtking-pro.dtb

# If the file $uboot_ext_local exists in $imgfile_dir then it will be
# installed on the image as the default u-boot.ext on the bootfs (there are
# also several u-boot.bin candidates from Ophub installed on the image that
# may serve as u-boot.ext when booting via chainloading).
uboot_ext_local=u-boot.bin-gtkp-pb-1s-ctrlc # See $uboot_ext_local_url below.

# If the file $root_sshkey_loc exists in $imgfile_dir then it will be installed
# on the image as /root/.ssh/authorized_keys (for passwordless ssh root login).
root_sshkey_loc="mysshkey.pub"

# The generated Linux image has an MBR disk label and is partitioned as
# [ gap (not used), bootfs, rootfs ]. Details about the partitioning are
# given in the comments in the function create_partitions below.
gap_MiB=16        # Leading gap (space for a "hidden" u-boot, cf. below).
bootfs_MiB=500    # The bootfs holds (mostly) one new and one old copy of
                  # vmlinuz, initrd.img, plus the u-boot.ext candidates.
rootfs_MiB=6000
rootfs_type=ext4  # Must be ext4 currently (btrfs is a placeholder).

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

# Ophub repo (dir.) with u-boot.bin files for use as chainloader u-boot.ext.
ophub_repo_url="https://github.com/ophub"
ophub_raw_path="/u-boot/raw/refs/heads/main/u-boot/amlogic/overload"
ophub_uboot_url=${ophub_repo_url}${ophub_raw_path}

# Note: Some of these may not be able to boot newer Ubuntu kernels or initramfs
# since they do not have support for decompression of zstd compressed files.
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

# The kernel command line actually used (to make extlinux.conf and uEnv.txt)
# below will be prepended by the string "root=UUID=${rootfs_UUID}".
# (Kept as a string: it is embedded in the generated files as a single
# quoted string, and a kernel command line is naturally a single string.)
kernel_cmdline_opts="quiet splash"

# Holds downloads etc.
tmpfile_dir=${imgfile_dir}/temp_files

# Temporary mount points (dirs) used during image creation.
# (The same structure is used on the image with the bootfs mounted under
# /boot/bootfs.)
rootfs_mnt=${imgfile_dir}/rootfs_tmp
bootfs_dir=/boot/bootfs # Must have leading forward slash.
bootfs_mnt="${rootfs_mnt}${bootfs_dir}"

# Mount options used in the fstab file on the image.
rootfs_mnt_opts="errors=remount-ro"
bootfs_mnt_opts="defaults"

# Some (but not all) commands used below to create the image.
# (The mkfs command for rootfs_type is added in validate_params.)
reqd_cmdlist=("blkid" "dd" "debootstrap" "fsck.fat" "e2fsck" "losetup"
              "mkfs.fat" "mkimage" "parted" "systemd-nspawn" "tar" "wget" "xz"
)

# List of packages to be added to (the ones minimally needed for) the install.
# (These are arrays: the package list is embedded in the generated chroot
# script as a properly quoted bash array, so that a package name with spaces
# or shell metacharacters would not break the generated script.)
ubuntu_extra_packages=("nano" "aptitude" "usbutils" "zram-tools" "sudo"
                       "man-db" "ssh")
debian_extra_packages=("aptitude" "usbutils" "zram-tools" "sudo" "ssh")
devuan_extra_packages=("aptitude" "usbutils" "zram-tools" "sudo" "ssh")

# Debian specific parameters (defaults; overridden in select_distro).
nonfree_list="non-free non-free-firmware" # "non-free" for Bullseye.
time_pkg=systemd-timesyncd # ntp for Bullseye/Bookworm.

# For running in QEMU the user mode emulation binary qemu-<arch>-static is reqd.
reqd_cmdlist_virt=("qemu-aarch64-static")

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
        aarch64|x86_64) ;;
        *) die "The architecture '$arch_str' is not one of x86_64 or aarch64, exiting." ;;
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
            # The NetworkManager connection file below is set up for the
            # interface name eth0 (this is what worked on the tested boxes;
            # the numbering/naming of the eth interfaces may vary).
            iface_name=eth0
            ;;
        "debian")
            distro_name=$debian_name
            distro_edition=$debian_edition
            distro_repourl=$debian_repourl
            keyring_file=/usr/share/keyrings/debian-archive-keyring.gpg
            bootfs_label=DEBN_BOOT
            rootfs_label=DEBN_ROOT
            # On Amlogic boards with the mainline kernel, systemd's
            # predictable naming (used on Debian) typically names the eth
            # interface end0 (on-board index, cf. systemd.netnames(7)); on
            # Bullseye the name was commonly eth0.
            if [[ $debian_edition == "Bullseye" ]]; then
                nonfree_list="non-free"
                iface_name="eth0"
            else
                nonfree_list="non-free non-free-firmware"
                iface_name="end0"
            fi
            if [[ $debian_edition == "Trixie" ]]; then
                time_pkg=systemd-timesyncd
            else
                time_pkg=ntp
            fi
            ;;
        "devuan")
            distro_name=$devuan_name
            distro_edition=$devuan_edition
            distro_repourl=$devuan_repourl
            keyring_file=/usr/share/keyrings/devuan-archive-keyring.gpg
            bootfs_label=DEVU_BOOT
            rootfs_label=DEVU_ROOT
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
    [[ $gap_MiB =~ ^[0-9]+$ ]] || die "gap_MiB must be a non-negative integer."
    [[ $bootfs_MiB =~ ^[1-9][0-9]*$ ]] || die "bootfs_MiB must be a positive integer."
    [[ $rootfs_MiB =~ ^[1-9][0-9]*$ ]] || die "rootfs_MiB must be a positive integer."
    [[ -n $host_name ]] || die "host_name must not be empty."
    [[ $host_name =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] ||
        die "host_name '$host_name' is not a valid host name."
    [[ -n $dtbfile_name ]] || die "dtbfile_name must not be empty."
}

check_prereqs() {
    local chk_cmdlist=("${reqd_cmdlist[@]}")
    if [[ $arch_str != "aarch64" ]]; then
        chk_cmdlist+=("${reqd_cmdlist_virt[@]}")
    fi
    local missing=() chk_cmd
    for chk_cmd in "${chk_cmdlist[@]}"; do
        command -v "$chk_cmd" >/dev/null || missing+=("$chk_cmd")
    done
    [[ ${#missing[@]} -eq 0 ]] ||
        die "The required commands are missing: ${missing[*]}"
    if [[ $arch_str != "aarch64" && ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
        log_warn "No binfmt_misc entry for qemu-aarch64 found; systemd-nspawn will not be able to exec the aarch64 rootfs. Install/enable qemu-user-static."
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
    # This is a rough estimate: we do not take into account the space used by
    # temporary files etc.
    imgfile_MiB=$(( gap_MiB + bootfs_MiB + rootfs_MiB ))
}

generate_uuids() {
    # UUIDs can also be generated with the cmd uuidgen from the pkg uuid-runtime.
    local uuid_file=/proc/sys/kernel/random/uuid
    [[ -r $uuid_file ]] || die "Cannot read $uuid_file."
    rootfs_UUID=$(< "$uuid_file")  # Used in rootfs, /etc/fstab, extlinux.conf, grub.cfg.
    eth0nm_UUID=$(< "$uuid_file")  # Used in Ubuntu.
    [[ -n $rootfs_UUID && -n $eth0nm_UUID ]] ||
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
    dd if=/dev/zero of="$imgfile_loc" bs=1M count="$imgfile_MiB" \
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
    # The partition layout is a simple MBR layout: a leading gap (space for a
    # "hidden" u-boot, cf. README_auxbootldr.txt), the vfat bootfs partition
    # (p1) and the rootfs partition (p2, the rest of the disk).
    log_info "Creating partitions (MBR) in container file with parted ..."
    parted -s "$imgfile_loc" mklabel msdos
    parted -s "$imgfile_loc" mkpart primary fat32 \
        "${gap_MiB}MiB" "$(( gap_MiB + bootfs_MiB ))MiB"
    parted -s "$imgfile_loc" mkpart primary "$rootfs_type" \
        "$(( gap_MiB + bootfs_MiB ))MiB" 100%
    sync
    log_ok "Done."
}

format_partitions() {
    log_info "Formatting the container file partitions ..."
    mkfs.fat -n "$bootfs_label" "${loop_dev}p1" ||
        die "mkfs.fat of ${loop_dev}p1 failed."
    if [[ $rootfs_type == "ext4" ]]; then
        mkfs.ext4 -F -q -U "$rootfs_UUID" -L "$rootfs_label" -b 4k -m 0 "${loop_dev}p2" ||
            die "mkfs.ext4 of ${loop_dev}p2 failed."
    elif [[ $rootfs_type == "btrfs" ]]; then # Only a placeholder for now.
        mkfs.btrfs -f -U "$rootfs_UUID" -L "$rootfs_label" -m single "${loop_dev}p2" ||
            die "mkfs.btrfs of ${loop_dev}p2 failed."
    else
        die "Not implemented formatting option for rootfs (rootfs_type=$rootfs_type)."
    fi
    log_ok "Done."
}

mount_partitions() {
    log_info "Mounting the root partition inside the container file ..."
    mkdir -p "$rootfs_mnt"
    mount "${loop_dev}p2" "$rootfs_mnt" ||
        die "The command 'mount ${loop_dev}p2 $rootfs_mnt' failed."
    rootfs_mounted=true
    sync
    log_ok "Done."
    log_info "Mounting the boot partition inside the container file ..."
    mkdir -p "$bootfs_mnt"
    mount "${loop_dev}p1" "$bootfs_mnt" ||
        die "The command 'mount ${loop_dev}p1 $bootfs_mnt' failed."
    bootfs_mounted=true
    log_ok "Done."
}

debuntu_debootstrap() {
    # Used for both ubuntu and debian.
    log_info "Debootstrapping ${distro_name} system to ${rootfs_mnt}"
    debootstrap --arch arm64 --keyring "$keyring_file" \
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
    "${tmpfile_dir}/source/debootstrap" --arch arm64 --keyring "$keyring_file" \
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
    # Full kernel command line (used in the extlinux.conf and uEnv.txt
    # templates below).
    if [[ -n $kernel_cmdline_opts ]]; then
        kernel_cmdline="root=UUID=${rootfs_UUID} ${kernel_cmdline_opts}"
    else
        kernel_cmdline="root=UUID=${rootfs_UUID}"
    fi

    # Below we add also a line for the vfat boot partition.
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
DEBIAN_FRONTEND=noninteractive apt -y install dialog network-manager u-boot-tools
extra_packages=($(pkg_list_str "${ubuntu_extra_packages[@]}"))
DEBIAN_FRONTEND=noninteractive apt -y install "\${extra_packages[@]}"
dpkg-reconfigure tzdata
dpkg-reconfigure locales
dpkg-reconfigure keyboard-configuration

printf 'Set password for \033[91mroot:\033[0m\n'
until passwd; do echo "Try again."; done
EOF
    )

    # Used for Debian releases before Trixie (Trixie uses the deb822 format
    # below).
    debian_repo_list=$(cat <<EOF
deb http://deb.debian.org/debian $distro_release main contrib $nonfree_list
deb http://deb.debian.org/debian ${distro_release}-updates main contrib $nonfree_list
# deb http://deb.debian.org/debian ${distro_release}-backports main contrib $nonfree_list
deb http://security.debian.org/debian-security/ ${distro_release}-security main contrib $nonfree_list
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

    # This is the basic (default) set of packages installed on top of the rootfs.
    # (If you want to add packages, edit the array debian_extra_packages above.)
    debian_custom_inst=$(cat <<EOF
#!/bin/bash
set -Eeuo pipefail

apt-get update

# The linux-headers-arm64 package can be added if desired.
DEBIAN_FRONTEND=noninteractive apt -y install linux-image-arm64
echo "Setting FSTYPE to $rootfs_type in /etc/initramfs-tools/initramfs.conf"
sed -i "s/.*FSTYPE=.*/FSTYPE=${rootfs_type}/g" /etc/initramfs-tools/initramfs.conf
DEBIAN_FRONTEND=noninteractive apt -y install locales $time_pkg u-boot-tools
extra_packages=($(pkg_list_str "${debian_extra_packages[@]}"))
DEBIAN_FRONTEND=noninteractive apt -y install "\${extra_packages[@]}"
dpkg-reconfigure tzdata
dpkg-reconfigure locales
apt -y install console-setup

printf 'Set password for \033[91mroot:\033[0m\n'
until passwd; do echo "Try again."; done
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
    # (If you want to add packages, edit the array devuan_extra_packages above.)
    devuan_custom_inst=$(cat <<EOF
#!/bin/bash
set -Eeuo pipefail

apt-get update

# The linux-headers-arm64 package can be added if desired.
DEBIAN_FRONTEND=noninteractive apt -y install linux-image-arm64
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
    
    aml_autoscript=$(cat <<'EOF'
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

    s905_autoscript=$(cat <<'EOF'
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

    # Template uEnv.txt (for legacy boot scripts; cf. s905_autoscript).
    uEnv_txt=$(cat <<EOF
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
#!/bin/bash
set -Eeuo pipefail

bootpart_dir_=$bootfs_dir
EOF
    )

    # https://kernel-team.pages.debian.net/kernel-handbook/ch-update-hooks.html
    # $1 for any script under /etc/kernel or /etc/initramfs is version of "calling"
    # kernel in ABI format (as from uname -r).
    upd_bootfs_kernel_p2=$(cat <<'EOF'

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

    upd_bootfs_initrd_p2=$(cat <<'EOF'

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

# Scans for vmlinuz-* in /boot and makes a simple grub.cfg file in /boot/grub
#
# Usage: /usr/local/bin/mkgrubcfg_simple.bash [path-to-dtb-file]
#   where path-to-dtb-file is the path to the dtb file as it appears on a
#   running system (e.g. /boot/bootfs/meson-g12b-gtking-pro.dtb).
#
# The dtb path can be a symlink and it can alternatively be given in the
# environment variable dtb_path (command line has precedence). The full dtb
# path will be inserted into grub.cfg. If no dtb path is given, a grub.cfg is
# created with only a placeholder for the path (this is fine for bootloaders
# based on kexec, such as Petitboot/u-root, that let the booted Linux image
# inherit the dtb used by the bootloader). This script is normally run from a
# mounted rootfs and then the UUID of the rootfs is discovered using the blkid
# command (see below). However, for use inside a chroot jail the rootfs UUID
# can also be given as an environment variable rootfsUUID on the command line,
# like so (note the single quotes):
# chroot . /bin/bash -c 'rootfsUUID=f3cab04c-...-faec36aace3f /usr/local/bin/mkgrubcfg_simple.bash [path-to-dtb-file]'

# The kernel command line parameters here may need tweaking.
kernel_cmdline_pars_="$kernel_cmdline_opts"
EOF
    )

    mkgrubcfg_simple_p2=$(cat <<'EOF1'

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: /usr/local/bin/mkgrubcfg_simple.bash [path-to-dtb-file]"
    echo "  where path-to-dtb-file is the path to the dtb file as it appears on"
    echo "  a running system (optional)."
    echo "  The path can alternatively be given in the environment variable dtb_path"
    echo "  (command line has precedence). More info inside the script."
    exit 0
fi

if [[ $# -gt 1 ]]; then
    echo "Too many arguments (expected at most one), exiting."
    exit 1
fi

# The file paths entered into grub.cfg are relative to the top of the file
# system from where grub.cfg is read at boot time. The prefixes below for
# kernel and initramfs are added to their respective file names in grub.cfg.
# On this image the kernels and initramfses reside in /boot on the rootfs, so
# the default prefixes are "/boot". (If you change the setup, e.g. by using a
# separate boot partition mounted at /boot, set the prefixes to "" and adjust
# the dtb path handling below.)
kernel_path_prefix="/boot"
initrd_path_prefix="/boot"

if [[ $# -eq 1 ]]; then
    dtb_path=$1
else
    dtb_path=${dtb_path:-}
    if [[ -n $dtb_path ]]; then
        echo "Using environment variable dtb_path: $dtb_path"
    fi
fi

# In grub.cfg it is not always necessary to specify the dtb file, for
# instance when grub.cfg is used during a kexec call where no new dtb is to
# be loaded (in which case the already loaded dtb is reused).
devicetree_str="# devicetree /path/to/dtbfile # not used currently"
devicetree_msg="Devicetree:  No dtb file specified or dtb file missing."
dtbpath_full=""
if [[ -n $dtb_path ]]; then
    dtbpath_full=$(realpath -e -- "$dtb_path" 2>/dev/null) || true
fi
if [[ -f $dtbpath_full ]]; then
    devicetree_str="devicetree $dtbpath_full"
    devicetree_msg="Devicetree:  $dtbpath_full"
fi

# To use this script on a machine where the kernel image or initrd has some
# other naming convention, change the settings below.
kernel_name_template="vmlinuz"
initrd_name_template="initrd.img"

# shellcheck disable=SC1091
. /etc/os-release
distro_name_lc=$ID
distro_edition_lc=${VERSION_CODENAME:-}
distro_num=${VERSION_ID:-}

# First letter to uppercase.
distro_name="$(tr '[:lower:]' '[:upper:]' <<< "${distro_name_lc:0:1}")""${distro_name_lc:1}"
distro_edition="$(tr '[:lower:]' '[:upper:]' <<< "${distro_edition_lc:0:1}")""${distro_edition_lc:1}"

if [[ -z ${rootfsUUID:-} ]]; then
    # (The '|| var=' guards keep set -e from aborting on a failed findmnt or
    # blkid (e.g. in a chroot jail whose /dev lacks the device node) so that
    # the explicit check below can report a useful error instead of a bare
    # non-zero exit code.)
    rootfs_dev=$(findmnt -n -o SOURCE / 2>/dev/null) || rootfs_dev=""
    rootfs_uuid=$(blkid -s UUID -o value "$rootfs_dev" 2>/dev/null) || rootfs_uuid=""
    [[ -n $rootfs_uuid ]] || {
        echo "Could not determine the UUID of the root device ($rootfs_dev), exiting."
        exit 1
    }
else
    rootfs_uuid=$rootfsUUID
fi

# The next line is a default kernel command line and may have to be adjusted for each kernel.
kernel_cmdline_rootfsuuid="root=UUID=${rootfs_uuid}"
if [[ -n $kernel_cmdline_pars_ ]]; then
    kernel_cmdline="${kernel_cmdline_rootfsuuid} ${kernel_cmdline_pars_}"
else
    kernel_cmdline="$kernel_cmdline_rootfsuuid"
fi

echo "Parameters used to set up grub.cfg :"
echo "$devicetree_msg"
echo "Rootfs UUID: $rootfs_uuid"
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
    echo "No kernel image (vmlinuz-*) found in /boot, exiting."
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
    # (The here-document is unquoted so that the dtb file name is inserted;
    # the other expansions are escaped so that they happen at hook run time.)
    grubcfg_update_hook=$(cat <<EOF
#!/bin/bash
set -Eeuo pipefail

echo "Running kernel post{inst,rm} hook (simple version) for grub.cfg ..."

# The dtb file (on the bootfs partition, mounted at /boot/bootfs) is optional
# in grub.cfg (bootloaders based on kexec, such as Petitboot/u-root, typically
# let the booted Linux image inherit the dtb used by the bootloader), so it
# is passed to the mkgrubcfg_simple.bash script only if it exists.
if [[ -f /boot/bootfs/${dtbfile_name} ]]; then
    rootfsUUID="\${rootfs_UUID_:-}" dtb_path="/boot/bootfs/${dtbfile_name}" \
        bash -c '/usr/local/bin/mkgrubcfg_simple.bash'
else
    rootfsUUID="\${rootfs_UUID_:-}" \
        bash -c '/usr/local/bin/mkgrubcfg_simple.bash'
fi
EOF
    )

    README_auxbootldr=$(cat <<'EOF'
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

    README_altbootscr=$(cat <<'EOF'
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
On Amlogic TV-boxes it is sometimes necessary to have a zero lenght file called
aml_autoscript.zip present on the bootfs to trigger/enable the multiboot
functionality (via the Android Update&Backup app, cf. Armbian/CoreELEC forums).
EOF
    )

    README_uboot_ophub=$(cat <<'EOF'
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

    README_kernels=$(cat <<'EOF'
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
}

# ------------------------- rootfs file setup --------------------------------

setup_fstab() {
    log_info "Setting up the /etc/fstab file ..."
    write_template "${rootfs_mnt}/etc/fstab" "$fstab_file"
    # There is no UUID on a fat partition but in fstab the serial number works.
    local bootfs_UUID
    bootfs_UUID=$(blkid -s UUID -o value "${loop_dev}p1") ||
        die "Could not determine the UUID of the bootfs partition (${loop_dev}p1)."
    [[ -n $bootfs_UUID ]] || die "The bootfs partition has an empty UUID."
    printf 'UUID=%s  %s  vfat  %s  0  2\n' "$bootfs_UUID" "$bootfs_dir" "$bootfs_mnt_opts" \
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

install_g12_sound_script() {
    # On some boxes (e.g. g12a/g12b) this script (run as local user on the
    # booted image) is needed to get sound working.
    log_info "Installing script at /usr/local/bin/g12_sound.sh ..."
    if wget -P "$tmpfile_dir" -nv "$g12_sound_url"; then
        cp "${tmpfile_dir}/g12_sound.sh" "${rootfs_mnt}/usr/local/bin/g12_sound.sh"
        chmod 0755 "${rootfs_mnt}/usr/local/bin/g12_sound.sh"
        log_ok "Done."
    else
        log_warn "Unable to download the script g12_sound.sh from $g12_sound_url; skipping."
    fi
}

setup_boot_dirs() {
    log_info "Setting up directory /boot/grub ..."
    mkdir -p "${rootfs_mnt}/boot/grub"
    chmod 0755 "${rootfs_mnt}/boot/grub"
    log_ok "Done."
}

install_utility_scripts() {
    log_info "Installing utility scripts in /usr/local/bin ..."
    # This script uses grub-mkconfig but it doesn't work inside a loop device.
    # (It is installed for later use, to produce fancier grub menus.)
    write_template "${rootfs_mnt}/usr/local/bin/mkgrubcfg.bash" "$mkgrubcfg"
    # This script produces a basic grub.cfg file and works inside a loop device.
    write_template "${rootfs_mnt}/usr/local/bin/mkgrubcfg_simple.bash" "$mkgrubcfg_simple"
    chmod 0755 "${rootfs_mnt}/usr/local/bin/mkgrubcfg.bash" \
               "${rootfs_mnt}/usr/local/bin/mkgrubcfg_simple.bash"
    log_ok "Done."
}

install_bootfs_upd_hooks() {
    log_info "Installing bootfs update scripts in /etc/{kernel,initramfs} ..."
    local hook_file
    hook_file="${rootfs_mnt}/etc/kernel/postinst.d/upd_bootfs_kernel"
    mkdir -p "${rootfs_mnt}/etc/kernel/postinst.d"
    write_template "$hook_file" "$upd_bootfs_kernel"
    chmod 0755 "$hook_file"
    hook_file="${rootfs_mnt}/etc/initramfs/post-update.d/upd_bootfs_initrd"
    mkdir -p "${rootfs_mnt}/etc/initramfs/post-update.d"
    write_template "$hook_file" "$upd_bootfs_initrd"
    chmod 0755 "$hook_file"
    log_ok "Done."
}

# Note: this hook must be installed AFTER the chroot jail run (cf. the order
# in main()). If it is present inside the jail, dpkg runs it during the kernel
# install there, but then the rootfs UUID cannot be discovered (the jail's
# default /dev has no loop device nodes, so blkid fails) and the kernel
# package configuration is aborted. After the jail, the hook is run explicitly
# by create_grubcfg() with the UUID passed via the environment variable
# rootfs_UUID_.
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
            log_info "Setting up /etc/apt/sources.list ..."
            rm -f "${rootfs_mnt}/etc/apt/sources.list"
            write_template "${rootfs_mnt}/etc/apt/sources.list" "$ubuntu_repo_list"
            log_ok "Done."
            ;;
        "debian")
            if [[ $debian_edition == "Trixie" ]]; then
                log_info "Setting up /etc/apt/sources.list.d/debian.sources ..."
                rm -f "${rootfs_mnt}/etc/apt/sources.list"
                rm -f "${rootfs_mnt}/etc/apt/sources.list.d/debian.sources"
                write_template "${rootfs_mnt}/etc/apt/sources.list.d/debian.sources" "$debian_repo_list_deb822"
            else
                log_info "Setting up /etc/apt/sources.list ..."
                rm -f "${rootfs_mnt}/etc/apt/sources.list"
                write_template "${rootfs_mnt}/etc/apt/sources.list" "$debian_repo_list"
            fi
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

install_aarch64_qemu_binary() {
    if [[ $arch_str != "aarch64" ]]; then
        log_info "Installing local qemu-aarch64-static binary ..."
        local qemu_binary_loc
        qemu_binary_loc=$(command -v qemu-aarch64-static) ||
            die "qemu-aarch64-static not found (install the package qemu-user-static)."
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
    #     ./debuntu_dbstrap_aarch64.bash ubuntu 2>&1 | tee logfile
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
    local kernel_imgs=( "${rootfs_mnt}"/boot/vmlinuz-* )
    [[ ${#kernel_imgs[@]} -gt 0 ]] ||
        die "No kernel image (vmlinuz-*) found in ${rootfs_mnt}/boot."
    newest=$(printf '%s\n' "${kernel_imgs[@]}" | sort -V | tail -n 1)
    kern_name=${newest##*/}
    kern_vers=$(cut -d '-' -f 2- <<< "$kern_name")
    case $distro in
        "ubuntu")
            dtbfile_dir="${rootfs_mnt}/usr/lib/firmware/${kern_vers}/device-tree/amlogic"
            ;;
        "debian" | "devuan")
            dtbfile_dir="${rootfs_mnt}/usr/lib/linux-image-${kern_vers}/amlogic"
            ;;
    esac
    if [[ -f ${dtbfile_dir}/${dtbfile_name} ]]; then
        cp "${dtbfile_dir}/${dtbfile_name}" "${bootfs_mnt}"
    else
        die "Could not find $dtbfile_name in $dtbfile_dir (the device tree file must be set up manually on the image)."
    fi
    log_ok "Done."
}

remove_aarch64_qemu_binary() {
    if [[ $arch_str != "aarch64" ]]; then
        log_info "Removing local qemu-aarch64-static binary ..."
        rm -f "${rootfs_mnt}/usr/bin/qemu-aarch64-static"
        log_ok "Done."
    fi
}

create_grubcfg() {
    log_info "Creating /boot/grub/grub.cfg (simple version) ..."
    chroot "$rootfs_mnt" bash -c \
        "rootfs_UUID_='$rootfs_UUID' /etc/kernel/postinst.d/update-grub-cfg-simple" ||
        die "Could not create /boot/grub/grub.cfg (see the log above)."
    log_ok "Done."
}

setup_extlinux() {
    log_info "Setting up extlinux.conf on bootfs ..."
    mkdir -p "${bootfs_mnt}/extlinux"
    write_template "${bootfs_mnt}/extlinux/extlinux.conf" "$extlinux_conf"
    log_ok "Done."
}

setup_uenv() {
    log_info "Setting up uEnv.txt on bootfs ..."
    write_template "${bootfs_mnt}/uEnv.txt" "$uEnv_txt"
    log_ok "Done."
}

setup_boot_scripts() {
    log_info "Setting up boot script files on bootfs ..."
    write_template "${bootfs_mnt}/aml_autoscript.txt" "$aml_autoscript"
    write_template "${bootfs_mnt}/s905_autoscript.txt" "$s905_autoscript"
    mkimage -A arm -O linux -T script -C none \
        -d "${bootfs_mnt}/aml_autoscript.txt" "${bootfs_mnt}/aml_autoscript"
    mkimage -A arm -O linux -T script -C none \
        -d "${bootfs_mnt}/s905_autoscript.txt" "${bootfs_mnt}/s905_autoscript"
    log_ok "Done."
}

setup_u_boot_ext() {
    log_info "Setting up chainloader u-boot.ext ..."
    mkdir -p "${bootfs_mnt}/u-boot-ophub"
    write_template "${bootfs_mnt}/u-boot-ophub/README_u-boot-ophub.txt" "$README_uboot_ophub"
    local uboot_bin
    for uboot_bin in "${uboot_list[@]}"; do
        if ! wget -nv -P "${bootfs_mnt}/u-boot-ophub" "${ophub_uboot_url}/${uboot_bin}"; then
            log_warn "Unable to download $uboot_bin from ${ophub_uboot_url}/${uboot_bin}."
        fi
    done
    if [[ -f ${imgfile_dir}/${uboot_ext_local} ]]; then
        log_info "Found ${uboot_ext_local}, installing it as default u-boot.ext ..."
        mkdir -p "${bootfs_mnt}/u-boot-3pole"
        write_template "${bootfs_mnt}/u-boot-3pole/README_u-boot-aml.txt" "$README_uboot_aml"
        cp "${imgfile_dir}/${uboot_ext_local}" "${bootfs_mnt}/u-boot-3pole"
        cp "${imgfile_dir}/${uboot_ext_local}" "${bootfs_mnt}/u-boot.ext"
    else
        log_warn "The u-boot.ext file ${imgfile_dir}/${uboot_ext_local} does not exist; no default u-boot.ext installed."
    fi
    log_ok "Done."
}

detect_kernel_version() {
    # Pick up the kernel version (from the rootfs /boot, the bootfs copies are
    # named vmlinuz/initrd.img without version suffix).
    # (The glob is intentional; nullglob is set at the top of the script.)
    # shellcheck disable=SC2206
    local kernel_imgs=( "${rootfs_mnt}"/boot/vmlinuz-* )
    [[ ${#kernel_imgs[@]} -gt 0 ]] || die "Could not determine the kernel version from ${rootfs_mnt}/boot."
    local newest
    newest=$(printf '%s\n' "${kernel_imgs[@]}" | sort -V | tail -n 1)
    kernel_version=${newest##*/vmlinuz-}
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

write_readmes() {
    log_info "Writing instructions for alternate boot scripts ..."
    write_template "${bootfs_mnt}/README_altbootscr.txt" "$README_altbootscr"
    log_info "Writing info about grub.cfg and alternate kernels ..."
    write_template "${bootfs_mnt}/README_kernels.txt" "$README_kernels"
    log_info "Writing instructions for installing Petitboot/u-root ..."
    write_template "${bootfs_mnt}/README_auxbootldr.txt" "$README_auxbootldr"
    log_ok "Done."
}

unmount_container_file() {
    log_info "Unmounting the container file (and file system check) ..."
    sync
    umount -f "${loop_dev}p1"
    sleep 2
    # fsck.fat exit codes: 0 = no errors, 1 = errors corrected, 2 = errors not
    # corrected, 4/8/16 = operational errors.
    local rc=0
    fsck.fat -a "${loop_dev}p1" || rc=$?
    if [[ $rc -gt 1 ]]; then
        die "fsck.fat of ${loop_dev}p1 failed (exit code $rc)."
    fi
    umount -f "${loop_dev}p2"
    sleep 2
    if [[ $rootfs_type == "ext4" ]]; then
        # e2fsck exit codes: 0 = clean, 1 = errors corrected, 2 = errors not
        # corrected, 4/8/16 = operational errors.
        rc=0
        e2fsck -p "${loop_dev}p2" || rc=$?
        if [[ $rc -gt 1 ]]; then
            die "e2fsck of ${loop_dev}p2 failed (exit code $rc)."
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
        # because rmdir of rootfs_mnt would fail on the leftover (empty) boot
        # dir.)
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

    banner "Making image for $distro_name ($distro_edition, aarch64)"

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
    # Note: create_partitions() must run BEFORE setup_loop_device(): parted
    # writes the MBR directly into the container file, and the kernel's loop
    # driver only scans for partitions at attach time (or on an explicit
    # re-read request). If the loop device is attached first, the file is
    # still all zeros, no <loop_dev>p1/p2 nodes get created, and the later
    # mkfs of ${loop_dev}p1/p2 fails with "No such file or directory".
    create_partitions
    setup_loop_device
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
    install_g12_sound_script
    setup_boot_dirs
    install_utility_scripts
    install_bootfs_upd_hooks
    setup_distro_specifics
    setup_apt_lists
    prepare_for_chroot_jail
    install_aarch64_qemu_binary
    do_chroot_jail_tasks
    remove_aarch64_qemu_binary
    setup_dtb_file
    # (create_grub_upd_hook must come after the chroot jail run; cf. the
    # comment above the function. It must also come after setup_dtb_file so
    # that the dtb file is on the bootfs when create_grubcfg() runs the hook.)
    create_grub_upd_hook
    create_grubcfg
    setup_extlinux
    setup_uenv
    setup_boot_scripts
    setup_u_boot_ext
    detect_kernel_version
    write_readmes

    if [[ -f $root_sshkey_full ]]; then
        install_root_sshkey
    else
        log_warn "The ssh key file $root_sshkey_full does not exist; no ssh key installed."
    fi

    unmount_container_file
    detach_loop_device
    finalize_image
    cleanup_work_dirs

    build_ok=true
    banner "Finished"
}

main "$@"
