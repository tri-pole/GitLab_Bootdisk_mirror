#!/bin/bash

# petitboot_mkinitrd_riscv64.bash
#
# 26-11-12: v0.17, Qwen3.8
# 26-10-12: v0.15, Tripole and Qwen3.8
# 26-02-10: v0.13, Tripole
# ...
# 24-12-18: v0.1, Tripole
# for complete log, see CHANGELOG.md

# Script to build and pack Petitboot for RISCV64 in an initramfs (cpio+gzip).

# Requirements: RISCV64 build host with normal build environment (see below)
# where the user running the script must be in the sudo group. (At the end
# of the build proper ownership of files in the initramfs needs to be set.)

# Tested on: Ubuntu 22.04.5 host running in QEMU (qemu-system-riscv64) and in
# docker container on x86_64, and on Ubuntu 24.04.5 running on VisionFive 2.
# (Cross compilation is not possible since some libs/utils are copied from the
# build host, see below.) The initramfs has been tested on VisionFive 2, v1.3b.

# Dependencies: GNU build tools w/ compiler suite, installed dependencies for
# the packages kexec, busybox, iproute2, e2fsprogs, petitboot and eudev.
# For example, on a default installation of Debian 12.8 or Ubuntu Server
# 22.04.5 all the dependencies should be satisfied by installing the following
# packages (along with their dependencies):
# autoconf automake bison build-essential cpio flex gawk gettext git gperf gpg
# libasprintf-dev libblkid-dev libdevmapper-dev libdw-dev libelf-dev
# libgd-tools libgettextpo-dev libgpgme-dev liblzma-dev libncurses-dev
# libssl-dev libtool libudev-dev pkg-config tree wget zstd
# The build host must have installed some commands that are copied (along with
# some conf files), namely file, grep, unzstd (see copy_*_list below).

# Patches: Some patches are applied to Petitboot to adjust functionality, to
# fix some compatibility issues with recent ncurses and to get RISCV64 support
# in the version (fork) of kexec-tools that we use (see below). These patches
# are downloaded and applied as part of the build. The script extract-vmlinux
# from Linux src is downloaded and patched at build time as well.

# Usage: The script can be run as an ordinary user but near the end it will ask
# for the user password to execute a sudo command to change ownership of the
# files in the initramfs. During execution of this script, two directories will
# be created in the same dir as this script; one result dir and one temp file
# directory hierarchy. (Near the end of this script you will be asked which of
# the temp dirs you want to delete.) Run time for the script is ~30m in QEMU
# (4 cores, on a reasonably modern box) and less than 13m on bare metal (VF2).

# Inspiration taken from: https://www.raptorengineering.com/content/kb/1.html

# About the build: By default, the build config files etc. for each component
# are stored also in the resulting initramfs; search for build.tgz in the code
# below (these files are small, but you can omit them to save space). (Since
# some libs are copies from the host, for source (debugging) see host source.)

# Things to note about Petitboot:
# - Petitboot has a configuration menu but settings cannot be saved to disk.
# - The dmidecode command is fake and is just a link to /sbin/sysinfo which is
#   a hacky shell script to extract info from /proc/device-tree. This script
#   may need tweaking for different platforms in order to correctly show the
#   Manufacturer, Model and Board data in the top margin of the Petitboot menu.
#   (Does not currently work on RISCV64 so no mfg./board info in main menu.)
# - gpg (which is only needed for verifying signed or encrypted boot) is not
#   properly setup (missing certificates and libraries); for instructions, see
#   e.g. the notes at raptorengineering.com in the link above.
# - Some files (libraries and executables, cf. below) are simply copied from
#   the host.
# - Sometimes there is a delay before any bootable configurations show up in
#   the main UI (and only a "bare-bones" menu is shown). This is because some
#   bus is slow to respond. (On the VF2 the PCI/nvme can take up to 30s to
#   respond, but USB devices can also generally be slow.) There is also a
#   default delay of a few secs (configurable) before starting the main UI to
#   allow for all devices to be detected before the UI is drawn but sometimes,
#   e.g. when many devices are connected, the scan may take even longer.
# - There are ten kernel command line options that can be sent to the kernel
#   running Petitboot and which will direct the behavior of Petitboot:
#   * pb_no_autoboot={true,false} (default false). No autoboot if true.
#       (Petitboot has a default autoboot of 10s (here patched to 60s), but the
#       feature is of limited use since the chosen boot entry cannot be saved.)
#   * pb_nonet={true,false} (default false). Will create a netns jail for
#       Petitboot if true so that only the loopback interface will be enabled.
#   * pb_delay={0,1,2,3,...} (default 1). Delay in seconds to start main UI.
#   * pb_displ={{M,m},d,{b,s}} (default ds). Determines what is displayed in
#       the header of Petitboot's main screen. The format descriptors are:
#       M,m = manufacturer (long, short), d = product name,
#       b = board info string, s = SoC info string. (See sysinfo code below.)
#   * pb_mem_max=<0xXYZ> (default not set). This hex number will be used as max
#       RAM during kexec reboot. (The option pb_mem_max does not limit the
#       available RAM for the kernel being booted.) The limit pb_mem_max is
#       needed when booting some kernels that (for some reason) cannot see all
#       RAM and hence would otherwise not find the initramfs (which is placed
#       near the top of RAM for kexec reboot). More info below.
#   * pb_no_decompr={true,false} (default false). Decompression of a kernel to
#       be loaded is never attempted if this option is set to true. (In the
#       default mode, the code will detect uncompressed items and leave them
#       as-is.) The compression formats recognized for kernels are gzip, xz,
#       bzip2, lzma, lzo and zstd.
#   Remote mode: If the option pb_rootpw is given along with one of the options
#       pb_ipstr or pb_hostname then Petitboot starts in remote mode and waits
#       for telnet login (tcp/23) where the UI appears. If pb_hostname is given
#       then the IP address is obtained via DHCP, otherwise the IP address used
#       is the one supplied in pb_ipstr (pb_hostname/DHCP has precedence).
#   * pb_rootpw={string,undef} (default undefined). Root password for telnet.
#   * pb_ipstr={xxx.yyy.zzz.uuu/vv,undef} (default is undef) IPv4 addr/prefix.
#       The option pb_ipstr sets the IP address and subnet size (prefix) in rm.
#   * pb_hostname={string,undef} (default undef). Hostname (for DHCP in rm).
#   * pb_netdev={string,undef} (default eth0). Only applies to remote mode.

# Things to note about Busybox and other utils:
# - When entering the Busybox command line you will see an error message like
#   "can't access tty; job control turned off". This is due to the choice of
#   /dev/console which is serial; thus cannot be a controlled tty, see e.g.
#   https://raw.githubusercontent.com/brgl/busybox/master/shell/cttyhack.c
# - The commands reboot, halt, poweroff are available in Busybox but must be
#   used with the -f flag (force; do not go through init).
# - The pb-discover process may interfere with some e2fsprogs such as e2fsck
#   (giving error messages about busy devices etc.) so it is advisable to first
#   kill pb-discover before e.g. attempting to repair file systems from the
#   Busybox shell.

# ToDo:
# - Perhaps add the option of having a user supplied file tree baked into the
#   initramfs, e.g. with firmware files for the kernel running Petitboot.
#   (The plugin mechanism of Petitboot requires manual invocation.)
# - There seems to be an option for Petitboot named petitboot.debug that can
#   be passed via the kernel command line, but it is unclear what it is.

# Final note: I'm aware (now, D'oh!) that the name of the program is a bit of a
# misnomer since the program creates an initramfs (file system), not an initrd
# (ramdisk). However, in bootloader contexts (e.g. u-boot) the two (initramfs
# and initrd) are often collectively referred to as "initrd" (lame excuse).

# set -Eeuo pipefail is enabled below (right after the logging helpers),
# together with an ERR trap (reports the failing line and exit code) and an
# EXIT trap (on failure: keep the work dirs for inspection; it never deletes
# anything). The build steps are also checked explicitly with check_rc
# (Functions section). Benign non-zero exits (e.g. the cleanup 'read' prompts
# on a non-tty stdin) are handled explicitly where they occur, so that
# 'set -e' does not abort on them.
# NOTE: 'shopt -s nullglob' is deliberately NOT used: the only glob in the
# script (the Petitboot hooks copy, ./utils/hooks/{01,20,90}-*) should fail
# loudly if it matches nothing, which the default glob behavior gives us.

# --------------------------------- Parameters -------------------------------

# If used, this tag is inserted inside the header in the Petitboot main menu
# where it normally says e.g. Petitboot (v1.15) so that instead it will say
# something like Petitboot (v1.15 (mytaglinehere))
build_date=$(date -u +"%y%m%d")
build_ver_tag=3p-${build_date}
# If the next line is set to true, the build_ver_tag is shown in the top
# margin in the Petitboot main menu (after the Petitboot version number)
# and the tag is also applied to the resulting initramfs(s) (see below).
use_build_ver_tag=true # {true,false}

# The initramfs can be built also in a smaller version where the e2fsprogs
# tools are omitted (file system tools are still available in Busybox).
# (Note: The name tag format of the generated initrd is still the same.)
no_e2fsprogs=false # {true,false}

# The source packages listed/defined below are downloaded unless a copy of the
# package in question already exists in ${temp_dir}/downloads (see below).

# The releases of the standard kexec-tools maintained by Simon Horman (horms)
# at https://github.com/horms/kexec-tools do not yet have the required support
# for RISCV and therefore we use a fork that has the required support. This
# fork is by Song Shuai (sugarfillet) and is based on work by Nick Kossifidis.
# The fork adds support for booting kernels of type Image (in uncompressed
# form, or with gzip or lzo compression). More info about this fork can be
# found here at https://lkml.iu.edu/hypermail/linux/kernel/2309.1/07133.html
# We use commit 56552e1a2f1f445f40dcbadf27129fcd7215df5c from branch rv-Image
# from the fork available at https://github.com/sugarfillet/kexec-tools.git
# In the initramfs we do not call the kexec executable directly, but via
# a wrapper script, and for this reason we use the name kexec_bin for the
# kexec (compiled) binary, both here in the code and in the initramfs.

# Patches (e.g. Petitboot) are taken from here.
bootdisk_url=https://gitlab.com/tripole-inc/bootdisk.git
bootdisk_dir=bootdisk # Clone into dir, relative to $temp_dir

# Script to decompress the Linux kernel.
extract_vmlinux_url="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/scripts/extract-vmlinux?h=v6.18.2"
misc_patch_dir=misc_patches # Relative to $bootdisk_dir

# Definitions for categories 'linux', 'archive' and 'compress' for 'file' cmd.
file_magic_ver=FILE5_46
file_magic_url_base=https://raw.githubusercontent.com/file/file/refs/tags/${file_magic_ver}/magic/Magdir
file_magic_arr=(linux archive compress)
file_magic_cut=("524,530p" "327,419p" "1,458p") # Arguments to sed -n below.

# Alternative location for Sugarfillet's patched kexec-tools:
# https://github.com/tri-pole/kexec-tools-riscv64-sugarfillet
kexectools_ver=sf-rv-Image-56552e1
kexectools_branch=rv-Image
kexectools_url=https://github.com/sugarfillet/kexec-tools.git
kexectools_commit_sha=56552e1a2f1f445f40dcbadf27129fcd7215df5c
kexectools_loc_build_dir=kexectools/kexec-tools-${kexectools_ver}
kt_patch_dir=kexectools_patches # Relative to $bootdisk_dir
kt_fix_initrd_in_mem_pos_patch_name=kexec_fix_initrd_in_mem_pos.patch
clone_kexectools_repo=true

busybox_ver=1.36.1
busybox_url_base=https://busybox.net/downloads
bb_tarball_repo_name=busybox-${busybox_ver}.tar.bz2
bb_tarball_local_name=busybox-v${busybox_ver}.tar.bz2
# busybox_bch=$(sed -e 's/\./_/g' <<< $busybox_ver)
# busybox_git_url="https://git.busybox.net/busybox"

iproute2_ver=6.12.0
iproute2_url_base=https://github.com/iproute2/iproute2/archive/refs/tags
# iproute2_url_base=https://git.kernel.org/pub/scm/network/iproute2/iproute2.git/snapshot
ipr2_tarball_repo_name=v${iproute2_ver}.tar.gz
ipr2_tarball_local_name=iproute2-${ipr2_tarball_repo_name}

e2fsprogs_ver=1.47.2
e2fsprogs_url_base=https://github.com/tytso/e2fsprogs/archive/refs/tags
e2fs_tarball_repo_name=v${e2fsprogs_ver}.tar.gz
e2fs_tarball_local_name=e2fsprogs-${e2fs_tarball_repo_name}

petitboot_ver=1.15 # Don't change this; PB patches may no longer work.
petitboot_url_base=https://github.com/open-power/petitboot/releases/download/v${petitboot_ver}
pb_tarball_repo_name=petitboot-v${petitboot_ver}.tar.gz
pb_tarball_local_name=${pb_tarball_repo_name}
pb_patch_dir=petitboot_patches # Relative to $bootdisk_dir
pb_1v13_add_grubcfg_path_patch_fname=pb_1v13_add_grubcfg_path.patch
pb_1v13_ui_and_bootcfg_patch_fname=pb_1v13_ui_and_bootcfg.patch
pb_add_riscv64_functionality_patch_fname=pb_add_riscv64_functionality.patch
pb_scsi_rescan_patch_fname=pb_scsi_rescan.patch
pb_menu_ncurses_struct_patch_fname=pb_menu_ncurses_struct.patch
pb_fix_ncurses_leak_patch_fname=pb_fix_ncurses_leak.patch
pb_fix_ncurses_items_patch_fname=pb_fix_ncurses_items.patch
pb_fix_ncurses_comment_patch_fname=pb_fix_ncurses_comment.patch
pb_patch_list=("${pb_1v13_add_grubcfg_path_patch_fname}"
               "${pb_1v13_ui_and_bootcfg_patch_fname}"
               "${pb_add_riscv64_functionality_patch_fname}"
               "${pb_scsi_rescan_patch_fname}"
               "${pb_menu_ncurses_struct_patch_fname}"
               "${pb_fix_ncurses_leak_patch_fname}"
               "${pb_fix_ncurses_items_patch_fname}"
               "${pb_fix_ncurses_comment_patch_fname}")

eudev_ver=3.2.14
eudev_url_base=https://github.com/eudev-project/eudev/releases/download/v${eudev_ver}
eudev_tarball_repo_name=eudev-${eudev_ver}.tar.gz
eudev_tarball_local_name=eudev-v${eudev_ver}.tar.gz
eudev_udev_rules_list=("50-udev-default.rules" "60-autosuspend.rules"
                       "60-block.rules" "60-cdrom_id.rules" "60-drm.rules"
                       "60-evdev.rules" "60-fido-id.rules" "60-input-id.rules"
                       "60-persistent-input.rules" "60-persistent-storage.rules"
                       "60-serial.rules" "64-btrfs.rules" "64-btrfs.rules.in"
                       "70-memory.rules" "70-mouse.rules" "75-probe_mtd.rules")

# The terminal definition files listed here will be copied into the initramfs.
# Petitboot uses the linux terminal per default. (This is defined as TERM=linux
# in the script ${pb_build}/utils/pb-console which is copied to the initramfs
# at the location /usr/sbin/pb-console). The standard location for the terminfo
# files is typically /usr/share/terminfo but it can also be /lib/terminfo.
terminfo_dir=/usr/share/terminfo # /usr/{share,lib}/terminfo for {Noble,Jammy}
pb_term_list=("ansi" "dumb" "linux" "vt220")

# Libraries used by these executables will be copied from the host.
dyn_linked_exe_list_noe2fs=("/sbin/kexec_bin" "/usr/bin/file" "/usr/bin/grep"
                            "/usr/bin/unzstd"
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
    dyn_linked_exe_list=("${dyn_linked_exe_list_noe2fs[@]}")
    # Suffix for the embedded build README (heredoc below); empty in the
    # default build, where e2fsprogs IS included.
    e2fsprogs_build_info=" (not included in this build; use Busybox applets)"
else
    dyn_linked_exe_list=("${dyn_linked_exe_list_noe2fs[@]}"
                         "${dyn_linked_exe_list_e2fs[@]}")
    e2fsprogs_build_info=""
fi

# These files are not necessary for Petitboot to start but decompression of
# kernel/initramfs will not work if file or grep (the complete one) is missing.
# (The binary for gpg can probably be omitted.)
copy_file_list=("/usr/bin/file" "/usr/bin/grep" "/usr/bin/unzstd" "/usr/bin/gpg")

# Bling? Yes, we like. (Only on a tty; logs stay clean when piped/redirected,
# e.g. in CI or via the build wrapper.)
if [[ -t 1 ]]; then
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

# Logging helpers (kbuild style; see arm64_kbuild.bash). log_err goes to
# stderr, the rest to stdout. The _n variants print no newline (the " Done."
# line completes the message).
log_info() { printf '[%s Info %s] %s\n' "$c_info" "$c_reset" "$*"; }
log_warn() { printf '[%s Warning %s] %s\n' "$c_warn" "$c_reset" "$*"; }
log_err()  { printf '[%s Error %s] %s\n' "$c_err" "$c_reset" "$*" >&2; }
log_ok()   { printf '[%s OK %s] %s\n' "$c_ok" "$c_reset" "$*"; }
log_info_n() { printf '[%s Info %s] %s' "$c_info" "$c_reset" "$*"; }
log_ok_n()   { printf '[%s OK %s] %s' "$c_ok" "$c_reset" "$*"; }

# --- Global error handling (kbuild style) -----------------------------------
# set -e: abort on any unhandled command failure; -E: the ERR trap is
# inherited by functions and subshells; -u: abort on unset variables;
# pipefail: a failing command anywhere in a pipeline fails the pipeline.
# The ERR trap reports the failing line; the EXIT trap reports on failure
# and keeps the work dirs for inspection (it never deletes anything).
set -Eeuo pipefail
build_ok=false
on_error() {
    local rc=$?
    log_err " Command failed at line $1 (exit code $rc)."
    exit "$rc"
}
cleanup() {
    local rc=$?
    if [[ $build_ok == true ]]; then return 0; fi
    log_warn " Build did not complete (exit $rc). Work dirs"
    echo "            kept for inspection: ${result_dir:-?} /"
    echo "            ${temp_dir:-?} (if created)."
    return 0
}
trap 'on_error $LINENO' ERR
trap cleanup EXIT

# ---------------------------------- Host info -------------------------------

host_info=$(uname -rsm)
os_info=$(cat /etc/os-release)
this_script_dir=$(dirname "$(readlink -f "$0")")
this_script=$(basename "$0")

no_comp_cores=$(nproc)
if [[ $no_comp_cores -gt 2 ]]; then
    # We leave one core for other work (typically no_comp_cores = 4 or more).
    no_comp_cores=$((no_comp_cores -1))
    # (On a 1- or 2-core machine, e.g. a small CI runner VM, all cores are
    # used; leaving one idle would waste half the machine.)
fi

# ---------------------------------- Here docs -------------------------------

README_petitboot_initrd=$(cat <<EOF

This Petitboot initramfs is built with $this_script from

https://gitlab.com/tripole-inc/bootdisk

The following source versions have been used

kexec-tools: $kexectools_ver
Busybox:     $busybox_ver
iproute2:    $iproute2_ver
e2fsprogs:   $e2fsprogs_ver$e2fsprogs_build_info
Petitboot:   $petitboot_ver
eudev:       $eudev_ver

to build the initramfs on a $host_info host running

$os_info

EOF
)

README_PB_Busybox=$(cat <<EOF
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

etc_motd=$(cat <<"EOF"
This is the Busybox shell (ash).
For some usage notes, see /usr/share/busybox/README_PB_Busybox.txt
EOF
)

etc_group=$(cat <<"EOF"
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

etc_nsswitch_conf=$(cat <<"EOF"
passwd:    files
group:     files
shadow:    files
hosts:     files
networks:  files
protocols: files
services:  files
ethers:    files
rpc:       files
netgroup:  files
EOF
)

usr_share_udhcpc_default_script=$(cat <<"EOF"
#!/bin/sh

/usr/share/udhcpc/simple.script "$@"
/usr/sbin/pb-udhcpc "$@"
EOF
)

init_script=$(cat <<"EOF"
#!/bin/sh

# 22-07-29, 23-10-07, 26-01-05, Tripole
# 26-10-12, Tripole and Qwen3.8
# Adapted from Raptor Engineering's How-To note on Petitboot.
# https://www.raptorengineering.com/content/kb/1.html

# This script can collect and use seven arguments from the kernel command line
# (typically the trailing part). Another three arguments from the kernel
# command line are used in scripts in the initramfs. The arguments used in
# this script are pb_no_autoboot, pb_nonet, pb_delay, pb_ipstr, pb_rootpw and
# pb_netdev. If (and only if) the two parameters pb_ipstr and pb_rootpw are
# both defined, then Petitboot starts in remote mode, where the UI can be
# accessed via telnet (and the console will only give a shell).

# Kernel command line arguments used in this script:
# * pb_no_autoboot={true,false,undef}, default is false (i.e. do autoboot).
#   If pb_no_autoboot=true the autoboot function is disabled. When the autoboot
#   function is enabled the first boot entry (after Petitboot's sorting) in the
#   boot entry list is started after the timeout period. The timeout period in
#   Petitboot is typically 10s (but this may have been altered by patches).
# * pb_nonet={true,false,undef}, default is false (i.e. bring up network).
#   If pb_nonet=true then pb-discover is started in a netns network jail so
#   that only the loopback interface works (thus also disabling PXE/netboot).
# * pb_delay={nonnegative integer,undef}, units of seconds, default is 1.
#   The variable pb_delay can be used to give a delay time before the main UI
#   comes up. This can be useful to let certain hardware "settle" (see below).
#   Remote (UI) mode options. This mode is triggered if pb_rootpw is set and
#   one of pb_hostname or pb_ipstr is set (the option pb_netdev is optional).
# * pb_rootpw={string,undef}, default is undefined. Root password for telnet.
# * pb_hostname={string,undef}, default is undefined. Hostname for telnet DHCP.
# * pb_ipstr={xxx.yyy.zzz.uuu/vv,undef}, default is undef, IPv4 addr/prefix.
#   The option pb_ipstr sets IP address and subnet size for telnet static addr.
# * pb_netdev={string}, default is eth0. Network device name for remote mode.

# Kernel command line arguments used in other scripts:
# * pb_no_decompr={true,false}, default false. Decompression of a kernel to be
#   loaded is never attempted if this option is set to true. (In the default
#   mode, the code will detect uncompressed items and leave them as-is.) The
#   compression formats recognized for kernels are gzip, xz, bzip2, lzma, lzo
#   and zstd.
# * pb_displ={{M,m},d,{b,s}}, default ds. Used in the dmidecode/sysinfo cmd.
#   Determines what is displayed in the header of Petitboot's main screen.
#   The format descriptors are: M,m = manufacturer (long, short), d = product
#   name, b = board info string, s = SoC info string.
# * pb_mem_max={hex number,undef}, default undef. Passed to kexec_wrapper.sh
#   via the shell that kexec_wrapper is executed in (Petitboot main UI or the
#   telnet login shell in remote mode).

if [ "$pb_no_autoboot" != "false" ] && [ "$pb_no_autoboot" != "true" ] ; then
    pb_no_autoboot=false
fi
if [ "$pb_nonet" != "false"] && [ "$pb_nonet" != "true" ] ; then
    pb_nonet=false
fi
if [ ! -z "${pb_delay##*[!0-9]*}" ] ; then
    delay=$pb_delay
else
    delay=1
fi

# This hack with a delay + some writing to the tty seems to be needed for the
# ncurses menu/UI to come up correctly (on some monitors/ttys). Also, some time
# may be needed for udev/pb-discover to detect/parse all devices/partitions.
start_wait () {
    wait_secs=$1
    if [ "$wait_secs" -gt "1" ]; then
        echo -n "Starting Petitboot in ..."
        while [ "$wait_secs" -gt "0" ] ; do
            echo -n "${wait_secs}..."
            sleep 1s
            wait_secs=$((wait_secs -1))
        done
    else
        echo "Starting Petitboot ..."
        sleep 1s
    fi
}

remote_mode=""
netdev=eth0
if [ "$pb_nonet" = "false" ] && [ ! -z "$pb_rootpw" ] && \
     ( [ ! -z "$pb_ipstr" ] || [ ! -z "$pb_hostname" ] ) ; then
    if [ ! -z "$pb_hostname" ]; then
        remote_mode=dhcp
    else
        remote_mode=static
    fi
    if [ ! -z "$pb_netdev" ]; then
        netdev=$pb_netdev
    fi
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

pb_discover_cmd="/usr/sbin/pb-discover"
# Keep option separate from the cmd to mitigate quoted expansion problems.
pb_discover_opt=""
if [ "$pb_no_autoboot" = "true" ] ; then
   pb_discover_opt="-a"
fi

# The verbose setting here only gives a little more info in the PB log.
pb_nc_cmd="/usr/sbin/petitboot-nc"
pb_nc_opt="-v"

if [ "$pb_nonet" = "true" ] ; then
    # Set up a network namespace to deny Petiboot access to external networks.
    /bin/ip netns add mininet
    /bin/ip netns exec mininet /bin/ip link set dev lo up
    /bin/ip netns exec mininet "$pb_discover_cmd" $pb_discover_opt 2>/dev/null &
    start_wait $delay
    /bin/ip netns exec mininet "$pb_nc_cmd" $pb_nc_opt
elif [ ! -z "$remote_mode" ] ; then
    mkdir /dev/pts
    mount -t devpts none /dev/pts
    # Run pb-discover in a network namespace jail so that its network handling
    # cannot touch the interface carrying this telnet session. In particular,
    # the "Rescan devices" UI entry makes pb-discover call network_shutdown(),
    # which brings all tracked interfaces down and flushes their addresses.
    # Without the jail that would kill this session (and the UI wedges on the
    # dead pty). Only loopback exists in the jail, so no PXE/netboot.
    /bin/ip netns add mininet
    /bin/ip netns exec mininet /bin/ip link set dev lo up
    echo -e "export pb_mem_max=$pb_mem_max" > /root/.profile
    echo -e "/bin/ip netns exec mininet $pb_discover_cmd $pb_discover_opt 2>/dev/null &" >> /root/.profile
    echo -e "sleep $delay && $pb_nc_cmd $pb_nc_opt" >> /root/.profile
    echo "root:x:0:0:root:/root:/bin/sh" > /etc/passwd
    echo -e "${pb_rootpw}\\n${pb_rootpw}" | passwd >/dev/null 2>&1
    echo "[ -- Petitboot in remote mode -- ]"
    ip_addr=$(echo $pb_ipstr | cut -d '/' -f1)
    if [ "$remote_mode" = "dhcp" ]; then
        hostname "$pb_hostname"
        udhcpc -s /usr/share/udhcpc/simple.script -i "$netdev" -x hostname:"$pb_hostname"
        echo "[ -- Waiting for telnet login (root, tcp/23) on host: '$pb_hostname' -- ]"
    else
        hostname "pb-${ip_addr}"
        ip addr add "$pb_ipstr" dev "$netdev"
        sleep 1
        ip link set dev "$netdev" up
        echo "[ -- Waiting for telnet login (root, tcp/23) on IP: $ip_addr -- ]"
    fi
    /usr/sbin/telnetd
    echo "[ To resume Petitboot UI here: killall telnetd && source /root/.profile ]"
else
    "$pb_discover_cmd" $pb_discover_opt 2>/dev/null &
    start_wait $delay
    "$pb_nc_cmd" $pb_nc_opt
fi

# Lockdown is related to (failed) secure boot (search for LOCKDOWN in PB src).
if [ -e /etc/pb-lockdown ] ; then
    echo "Failed to launch Petitboot, rebooting!"
    echo 1 > /proc/sys/kernel/sysrq
    echo b > /proc/sysrq-trigger
else
    echo "[ Dropping to a shell. (No job control on /dev/console.) ]"
    exec sh
fi
EOF
)

# sh does not support null characters '\0' (they will be mangled when a here
# doc is written to file).
sbin_sysinfo=$(cat <<"EOF"
#!/bin/sh

# 22-07-29, 23-10-05, 24-12-19, Tripole
# Hack to provide the most basic sysinfo from the device tree in order to
# mimic dmidecode's output which is used e.g. in the PB main menu header.
# (This script may well need to be adapted to any particular SBC and this
# can easily be done by cut-and-try from within the PB/Busybox shell.)

# pb-discover queries /sbin/dmidecode with the following request specifiers:
# --string=system-manufacturer
# --string=system-product-name
# --string=system-uuid
# For Ugoos AM6, cat gives the following results (w/ null bytes in strings):
# /proc/device-tree/compatible :  "ugoos,am6\0amlogic,s922x\0amlogic,g12b"
# /proc/device-tree/name       :  <empty>
# /proc/device-tree/model      :  "Ugoos AM6" # With a null char \0 somewhere.
# In the pipe filters below using tr we cannot use the null character \0
# explicity since sh does not allow nulls inside strings (only at the end).

# Busybox's version of stty is stripped down and there is no reliable way to
# determine the column width of the screen. To determine what is displayed
# we therefore use an environment variable from the kernel command line with
# the name/format pb_displ={{M,m},d,{b,s}} where M,m = manufacturer (long,
# short), d = product name, b = board info string, s = SoC info string, see
# below. (Note: The board/SoC info string is also used in Petitboot's System
# information screen.)

if [ -z "$pb_displ" ]; then
    pb_displ=ds
fi

query_str=${1#--string=}
response_str=""

case "$query_str" in
    "system-manufacturer" )
        val_str=$(tr [:cntrl:] ' ' </proc/device-tree/model | cut -d ' ' -f 1)
        case "$pb_displ" in
            M* )
                lead_str="Manufacturer: "
                response_str="${lead_str}${val_str}  "
                break
            ;;
            m* )
                lead_str="Mfg.: "
                response_str="${lead_str}${val_str}  "
                break
            ;;
            * )
                response_str=""
            ;;
        esac
    ;;
    "system-product-name" )
        val_str=$(tr [:cntrl:] ' ' </proc/device-tree/model | cut -d ' ' -f 2-)
        case "$pb_displ" in
            *d* )
                lead_str="Model: "
                response_str="${lead_str}${val_str}"
                break
            ;;
            * )
                response_str=""
            ;;
        esac
    ;;
    "system-uuid" )
        val_str=$(tr [:cntrl:] ' ' </proc/device-tree/compatible | awk -F ' ' '{print $NF}')
        case "$pb_displ" in
            *b )
                lead_str="Board: "
                response_str="${lead_str}${val_str}  "
                break
            ;;
            *s )
                lead_str="SoC: "
                val_str_cut=$(echo -n $val_str | cut -d ',' -f 2)
                response_str="${lead_str}${val_str_cut}  "
                break
            ;;
            * )
                response_str=""
            ;;
        esac
    ;;
esac

echo $response_str
EOF
)

README_memmax=$(cat <<"EOF"
# Remark on the mem-max argument (pb_mem_max):
# The following is valid at the time of this writing and applies, probably
# mostly, to VisionFive 2.
# Some kernels are only aware of half the memory (e.g. ~4G for VF2 8G) after
# kexec reboot. The reasons for this can be traced to how kernels determine
# the physical memory size based on the info in dtb and hardware probing, see
# e.g. https://github.com/starfive-tech/VisionFive2/issues/20
#      https://www.reddit.com/r/RISCV/comments/10jg152/comment/j9f2bri
# Some kernels (e.g. openSUSE's) are always aware of all memory, but others
# (e.g. Debian's) are not. Since kexec loads the new initrd at the top of the
# memory, as seen by the first (loading) kernel, this can be outside what the
# second (loaded) kernel is aware of.
# For this reason we may want to force the initrd mem load address in kexec to
# be lower, at a point in memory which the new kernel considers admissible.
# We do this by using the --mem-max arg of kexec (working values can be
# inferred from dmesg from failed reboots).
# The mem-max value can be passed to this script by using the environment
# variable pb_mem_max and the variable should give the max memory address in
# hex, e.g. pb_mem_max=0x13fffffff.
# The variable pb_mem_max can be passed in two ways:
# (1) Globally, for all kernels to be booted by Petitboot, by adding an
# argument pb_mem_max=<val> to the kernel command line for the kernel running
# Petitboot (this is typically done by editing extlinux.conf).
# (2) On a per-kernel basis, by adding a command line arg pb_mem_max=<val> to
# the kernel command line in grub.cfg (or by editing the command line for
# in Petitboot's main menu before boot).
# A workaround to the problem described above is to edit the dtb to reflect
# the correct memory size, as described in the reddit post above.
EOF
)

kexec_wrapper=$(cat <<"EOF"
#!/bin/sh

# 26-01-01, 26-02-10, Tripole

# This script performs filtering of the kexec call from Petitboot and can do
# (optional) decompression of kernels before calling kexec (the binary).
# The script can use two arguments from the kernel command line; pb_no_decompr
# and pb_mem_max. If pb_no_decompr=true then the code for kernel decompression
# below is disabled and the kernel is loaded as-is (always). The argument
# pb_mem_max can be used to restrict the loading region of the initrd during
# kexec which can sometimes be needed (for more info, see the file
# /usr/share/kexectools/README_memmax.txt).
# For RISCV64 we use a kexec binary which is based on a patched version of the
# code, due to Nick Kossifidis and Song Shuai (sugarfillet) described here:
# https://lkml.iu.edu/hypermail/linux/kernel/2309.1/07133.html.

kexec_binary="/sbin/kexec_bin" # The real McCoy.

# We use a modded version of extract-vmlinux where all informative output is
# directed to stderr and the order of try_decompress calls is changed.
extract_vmlinux_cmd="extract-vmlinux-pb"

kernel_path_extracted="/tmp/vmlinux-pb"

if [ -z "$pb_no_decompr" ]; then
    pb_no_decompr=false
fi
call_memmax_str=""
if [ ! -z "$pb_mem_max" ]; then
    call_memmax_str=" --mem-max="$pb_mem_max
fi

# The kexec call (issued by Petitboot) invoking this script can be only one of
# the following two forms (for details, see e.g. boot.c in the Petitboot src
# or run /usr/sbin/petitboot-nc -v in ./init, or uncomment two lines below):
# (1) kexec -{e,f}
# (2) kexec -{l,s} --initrd=/path/to/initrd \
#                  --dtb=/path/to/dtb \
#                  --append=<can_be_several_whitespace_separated_substrings> \
#                  /path/to/kernel
# where the all options except the last /path/to/kernel are optional. The call
# kexec -s (file based kexec syscall) is here translated to kexec -l (ordinary
# kexec operation). The call kexec -f is only tried by Petitboot if -e fails.

# Below we unpack the kexec call, filter the arguments, and send a repackaged
# version to kexec_binary (after optional kernel decompression).

opt_args_str=""
append_mode=false
append_args=""
kernel_str=""
call_str=""
arg_num=1
if [ "$#" = 1 ]; then
    # If telnetd is running (Petitboot remote mode), kill it before kexec -e.
    kill -s SIGTERM $(pidof telnetd) >/dev/null 2>&1
    call_str=$1
else
    # This is one of the cases -s or -l (we map both to -l).
    # We pick out the kernel_str, append_args and opt_args_str ("the rest").
    for arg_item in "$@" ; do
        if [ "$arg_num" = "$#" ]; then
            # Pick up the trailing /path/to/kernel
            kernel_str=$arg_item
        else
            if [ "$append_mode" = "false" ]; then
                # Pick up the initrd, dtb and append string(s).
                case "$arg_item" in
                    "-s" | "-l" )
                    # Do nothing.
                    ;;
                    "--append="* )
                        append_args="${arg_item#--append=}"
                        append_mode=true
                    ;;
                    * )
                        opt_args_str="$opt_args_str $arg_item"
                    ;;
                esac
            else
                # Gobble up all the substrings of the append string.
                append_args="$append_args $arg_item"
            fi
        fi
        arg_num=$((arg_num +1))
    done

    # If compression is enabled, check first if the kernel is uncompressed.
    # If it is not, then decompress the kernel.
    kernel_path=$kernel_str
    if [ "$pb_no_decompr" != "true" ]; then
        kernel_path_real=$(realpath $kernel_str)
        file $kernel_path_real | grep -q 'Linux kernel.*boot executable' >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            kernel_path=$kernel_path_extracted
            eval "$extract_vmlinux_cmd $kernel_path_real >$kernel_path" 2>/dev/null
        fi
    fi

    if [ ! -z "$pb_mem_max" ]; then
        call_mem_append_str="--mem-max="${pb_mem_max}
    else
        call_mem_append_str=""
    fi

    # The kexec binary accepts both --command-line and --append (to cmdline).
    # If --command-line is absent the --append contents is used as cmdline.
    # If the argument to --command-line or --append is a string that contains
    # whitespace (and it often does) it must be enclosed in double quotes.
    call_str_head="--load $kernel_path $opt_args_str $call_mem_append_str"
    call_str_tail=" --command-line="\"${append_args}\"
    call_str_raw=${call_str_head}${call_str_tail}
    call_str=$(echo $call_str_raw | tr -s ' ') # Squeeze any multiple spaces.
fi

# echo "Call string received from petitboot: [""$@""]" >/dev/console
# echo "Call string sent to kexec executable: [$call_str]" >/dev/console

eval "$kexec_binary $call_str"
EOF
)

# --------------------------------- Functions -------------------------------

check_rc () {
    # Usage: check_rc <rc> <description>
    # Exits the script if <rc> is non-zero. (With 'set -e' active, a failing
    # command usually trips the ERR trap - a line-numbered report - before
    # reaching this check; the check is kept so that every build step is
    # checked explicitly and labelled, as per the original design.)
    if [[ $1 -ne 0 ]]; then
        log_err " $2 failed (exit code $1), exiting."
        exit 1
    fi
}

run_time () {
local epoch_secs_now
epoch_secs_now=$(date +"%s")
case "$#" in
    "1" ) # $1 is a dummy argument.
        local result=$epoch_secs_now
    ;;
    "2" )
        local run_time_secs
        run_time_secs=$((epoch_secs_now - $2))
        local result
        result=$(date -d@$run_time_secs -u +"%H:%M:%S")
    ;;
    * )
        echo "Error in function run_time(), exiting."
        exit 1
    ;;
esac
echo "$result"
}

do_download() {
    # Usage: do_download <name> <url> <local_path>
    # Returns 0 on success, 1 on failure (does not exit; the caller decides
    # the message context). Verifies that the resulting file is a readable
    # tarball (guards against truncated files left by an interrupted earlier
    # run); on a bad file it re-downloads once before giving up.
    local bundle_name=$1
    local bundle_pkg_url=$2
    local bundle_pkg_loc=$3
    if [[ ! -f "$bundle_pkg_loc" ]]; then
        log_info " Downloading $bundle_name tarball from"
        echo "         $bundle_pkg_url"
        echo "         to local directory/name"
        echo "         $bundle_pkg_loc"
        if wget "$bundle_pkg_url" -O "$bundle_pkg_loc"; then
            log_ok " Done. $bundle_name source tarball successfully downloaded."
        else
            log_err " Failed to download $bundle_name source, exiting."
            return 1
        fi
    else
        log_ok " Skipping download of ${bundle_name}; file already exists."
    fi
    if ! tar -tf "$bundle_pkg_loc" >/dev/null 2>&1; then
        log_warn " $bundle_name tarball at $bundle_pkg_loc is not a"
        echo "         readable tarball; deleting and re-downloading once."
        rm -f "$bundle_pkg_loc"
        if ! wget "$bundle_pkg_url" -O "$bundle_pkg_loc"; then
            log_err " Failed to re-download $bundle_name source, exiting."
            return 1
        fi
        if ! tar -tf "$bundle_pkg_loc" >/dev/null 2>&1; then
            log_err " Re-downloaded $bundle_name tarball is still"
            echo "         not readable, exiting."
            return 1
        fi
    fi
    return 0
}

check_prereqs() {
    # Abort early (with a clear message) if any required command is missing,
    # rather than dying mid-build at the first use of it.
    local missing=() cmd
    for cmd in git wget tar patch strip ldd ldconfig cpio gzip tree file \
               sudo realpath autoupdate; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_err " Missing required commands: ${missing[*]}, exiting."
        exit 1
    fi
}

# ------------------------------- Preliminaries -----------------------------

run_time_start=$(run_time "start")

PATH=${PATH}:/usr/sbin

this_arch=$(arch)

if [[ $this_arch != riscv64 ]]; then
    log_err " -- Unsupported arch: ${this_arch}, exiting. --"
    exit 1
fi

check_prereqs

# Tag to be applied to the name of the resulting initrd (and the uInitrd).
if [[ $use_build_ver_tag == true ]]; then
    initrd_pb_tag=v${petitboot_ver}-${this_arch}-${build_ver_tag}
else
    initrd_pb_tag=v${petitboot_ver}-${this_arch}
fi
initrd_pb_name=initrd-pb-${initrd_pb_tag}

if [[ $no_e2fsprogs != true ]]; then
    log_info " -- Building the Petitboot initramfs for $this_arch (with e2fsprogs) --"
else
    log_info " -- Building the Petitboot initramfs for $this_arch (without e2fsprogs) --"
fi

log_info_n " Setting up initramfs directory structure ..."
result_dir=${PWD}/result_riscv64
if [[ -d "$result_dir" ]]; then
    log_err " The result dir $result_dir already exists, exiting."
    exit 1
fi
mkdir -p "${result_dir}"
temp_dir=${PWD}/temp_files
if [[ -e "$temp_dir" ]]; then
    log_err " The temp dir $temp_dir already exists (stale state from"
    echo "         a previous run?), exiting. Delete it and re-run."
    exit 1
fi
mkdir -p "${temp_dir}"
mkdir "${temp_dir}/downloads"
mkdir "${temp_dir}/kexectools"
mkdir "${temp_dir}/busybox"
mkdir "${temp_dir}/iproute2"
mkdir "${temp_dir}/e2fsprogs"
mkdir "${temp_dir}/petitboot"
mkdir "${temp_dir}/eudev"
mkdir "${temp_dir}/initramfs"
mkdir "${temp_dir}/initramfs/bin"
mkdir "${temp_dir}/initramfs/etc"
mkdir "${temp_dir}/initramfs/etc/netns"
mkdir "${temp_dir}/initramfs/etc/netns/mininet"
mkdir "${temp_dir}/initramfs/newroot"
mkdir "${temp_dir}/initramfs/proc"
mkdir "${temp_dir}/initramfs/run"
mkdir "${temp_dir}/initramfs/run/udev"
mkdir "${temp_dir}/initramfs/sbin"
mkdir "${temp_dir}/initramfs/sys"
mkdir "${temp_dir}/initramfs/tmp"
mkdir "${temp_dir}/initramfs/usr"
mkdir "${temp_dir}/initramfs/usr/bin"
mkdir "${temp_dir}/initramfs/usr/lib"
mkdir "${temp_dir}/initramfs/usr/lib/${this_arch}-linux-gnu"
mkdir "${temp_dir}/initramfs/usr/lib/udev"
mkdir "${temp_dir}/initramfs/usr/lib/udev/rules.d"
mkdir "${temp_dir}/initramfs/usr/lib/terminfo"
mkdir "${temp_dir}/initramfs/usr/sbin"
mkdir "${temp_dir}/initramfs/usr/share"
mkdir "${temp_dir}/initramfs/usr/share/kexectools"
mkdir "${temp_dir}/initramfs/usr/share/busybox"
mkdir "${temp_dir}/initramfs/usr/share/iproute2"
mkdir "${temp_dir}/initramfs/usr/share/e2fsprogs"
mkdir "${temp_dir}/initramfs/usr/share/petitboot"
mkdir "${temp_dir}/initramfs/usr/share/eudev"
mkdir "${temp_dir}/initramfs/usr/share/udhcpc"
mkdir "${temp_dir}/initramfs/usr/share/misc"
mkdir "${temp_dir}/initramfs/var"
mkdir "${temp_dir}/initramfs/var/log"
mkdir "${temp_dir}/initramfs/var/log/petitboot"
mkdir "${temp_dir}/initramfs/var/run"
mkdir "${temp_dir}/initramfs/var/run/netns"
cd "${temp_dir}/initramfs"
ln -s usr/lib lib
echo " Done."

log_info_n " Setting up 'init' script in initramfs ..."
echo -e "$init_script" > "${temp_dir}/initramfs/init"
chmod +x "${temp_dir}/initramfs/init"
echo " Done."

log_info " Setting up basic configuration files in initramfs tree ..."
echo    "         /etc/{group,mdev.conf,nsswitch.conf}"
echo -e "$etc_group" > "${temp_dir}/initramfs/etc/group"
touch "${temp_dir}/initramfs/etc/mdev.conf"
echo -e "$etc_nsswitch_conf" > "${temp_dir}/initramfs/etc/nsswitch.conf"
echo    "         /usr/share/udhcpc/default.script"
echo -e "$usr_share_udhcpc_default_script" \
> "${temp_dir}/initramfs/usr/share/udhcpc/default.script"
chmod 0755 "${temp_dir}/initramfs/usr/share/udhcpc/default.script"
echo " Done."

log_info_n " Setting up 'sysinfo' script in initramfs tree ..."
cd "${temp_dir}/initramfs/sbin"
echo -e "$sbin_sysinfo" >sysinfo
chmod +x sysinfo
ln -s sysinfo dmidecode
echo " Done."

# The terminal used by Petitboot is defined in ${pb_build}/utils/pb-console
# as TERM=linux which is often defined in /lib/terminfo/l/linux (but note
# that we have symlinked /lib to /usr/lib above).
log_info_n " Copying terminfo files from host to initramfs ..."
for terminfo_file in "${pb_term_list[@]}"; do
    terminfo_dir_lett=${terminfo_file:0:1}
    terminfo_file_path=${terminfo_dir}/${terminfo_dir_lett}/${terminfo_file}
    if [[ -f "$terminfo_file_path" ]]; then # We do not resolve symlinks here.
        # echo "Found terminfo file ${terminfo_file}, copying."
        mkdir -p "${temp_dir}/initramfs/usr/lib/terminfo/${terminfo_dir_lett}"
        cp "$terminfo_file_path" \
          "${temp_dir}/initramfs/usr/lib/terminfo/${terminfo_dir_lett}"
    else
        log_err " Cannot find the terminfo file ${terminfo_file}, exiting."
        exit 1
    fi
done
echo " Done."

# Petitboot will start without these files, but it may not function properly.
for loc_file in "${copy_file_list[@]}"; do
    mkdir -p "$(dirname "$loc_file")"
    log_info_n " Copying the file $loc_file to initramfs tree ..."
    if [[ -f "$loc_file" ]]; then
        cp "$loc_file" "${temp_dir}/initramfs${loc_file}"
        chmod 0755 "${temp_dir}/initramfs${loc_file}"
        echo " Done."
    else
        log_warn " Could not find the file ${loc_file}."
    fi
done

# -------------------------------- Downloads --------------------------------

# This is small so we always clone it.
log_info " Cloning the bootdisk repo $bootdisk_url"
echo            "         to the local dir ${temp_dir}/${bootdisk_dir}"
if git clone --depth=1 "$bootdisk_url" "${temp_dir}/${bootdisk_dir}"; then
    log_ok " Done. bootdisk repo successfully cloned."
else
    log_err " Failed to clone bootdisk repo, exiting."
    exit 1
fi

if [[ $clone_kexectools_repo == true ]]; then
    log_info " Cloning kexectools from"
    echo "         repo $kexectools_url"
    echo "         branch $kexectools_branch"
    echo "         commit $kexectools_commit_sha"
    echo "         to local (build) dir $kexectools_loc_build_dir"

    mkdir -p "${temp_dir}/${kexectools_loc_build_dir}"
    git clone -b "$kexectools_branch" "$kexectools_url" \
        "${temp_dir}/${kexectools_loc_build_dir}"
    cd "${temp_dir}/${kexectools_loc_build_dir}"
    if git reset --hard "$kexectools_commit_sha"; then
        log_ok " Done. kexec-tools successfully cloned and set up."
    else
        log_err " Failed to clone and set up kexec-tools, exiting."
        exit 1
    fi
fi

busybox_pkg_url=${busybox_url_base}/${bb_tarball_repo_name}
busybox_pkg_loc=${temp_dir}/downloads/${bb_tarball_local_name}
do_download "Busybox" "$busybox_pkg_url" "$busybox_pkg_loc"

iproute2_pkg_url=${iproute2_url_base}/${ipr2_tarball_repo_name}
iproute2_pkg_loc=${temp_dir}/downloads/${ipr2_tarball_local_name}
do_download "iproute2" "$iproute2_pkg_url" "$iproute2_pkg_loc"

if [[ $no_e2fsprogs != true ]]; then
    e2fsprogs_pkg_url=${e2fsprogs_url_base}/${e2fs_tarball_repo_name}
    e2fsprogs_pkg_loc=${temp_dir}/downloads/${e2fs_tarball_local_name}
    do_download "e2fsprogs" "$e2fsprogs_pkg_url" "$e2fsprogs_pkg_loc"
fi

petitboot_pkg_url=${petitboot_url_base}/${pb_tarball_repo_name}
petitboot_pkg_loc=${temp_dir}/downloads/${pb_tarball_local_name}
do_download "Petitboot" "$petitboot_pkg_url" "$petitboot_pkg_loc"

eudev_pkg_url=${eudev_url_base}/${eudev_tarball_repo_name}
eudev_pkg_loc=${temp_dir}/downloads/${eudev_tarball_local_name}
do_download "eudev" "$eudev_pkg_url" "$eudev_pkg_loc"

log_info " Downloading the script 'extract-vmlinux' from Linux src ..."
if wget "$extract_vmlinux_url" -O "${temp_dir}/downloads/extract-vmlinux"; then
    log_ok " Done. The script 'extract-vmlinux' successfully downloaded."
else
    log_err " Failed to download 'extract-vmlinux'; kernel"
    echo "         decompression in the initramfs would not work, exiting."
    exit 1
fi

log_info " Downloading magic file definitions for kernel and initramfs ..."
have_all_magic=true
for file_magic in "${file_magic_arr[@]}"; do
    if ! wget "${file_magic_url_base}/${file_magic}" -O "${temp_dir}/downloads/${file_magic}"; then
        log_warn " Failed to download magic file ${file_magic}."
        have_all_magic=false
    fi
done
if [[ $have_all_magic == true ]]; then
    log_ok " Done. All magic file definitions successfully downloaded."
else
    echo " Kernel decompression will not work due to failed downloads."
fi

# ---------------------------------- Build ---------------------------------

log_info " Building kexec-tools ..."
cd "${temp_dir}/${kexectools_loc_build_dir}"
log_info " Applying kexec-tools patches (a failed patch is fatal; the"
echo "         resulting initramfs would be suspect and must not be used) ..."
if ! patch -N -p1 <\
    "${temp_dir}/${bootdisk_dir}/${kt_patch_dir}/${kt_fix_initrd_in_mem_pos_patch_name}"; then
    log_err " kexec-tools patch ${kt_fix_initrd_in_mem_pos_patch_name}"
    echo "         failed to apply, exiting."
    exit 1
fi
log_ok " All kexec-tools patches applied successfully."
# 'autoupdate' (shipped with the autoconf package) rewrites obsolete
# autoconf macros in configure.ac in place: the riscv64 fork's
# configure.ac uses some (e.g. AC_HELP_STRING); the aarch64 tarball's
# is already clean, so this is a no-op there. Run it explicitly so
# that ./bootstrap (autoconf, which generates ./configure; the
# committed Makefile.in files mean no automake is needed) runs
# without obsolescence warnings.
autoupdate configure.ac
check_rc $? "kexec-tools autoupdate"
./bootstrap
check_rc $? "kexec-tools bootstrap"
./configure --prefix=/usr
check_rc $? "kexec-tools configure"
make -j "$no_comp_cores"
check_rc $? "kexec-tools make"
[[ -f ./build/sbin/kexec ]] || { log_err " kexec binary not found after build, exiting."; exit 1; }
tar -czf "${temp_dir}/initramfs/usr/share/kexectools/build.tgz" config.log configure.ac Makefile
log_info " Installing kexec binary to initramfs tree ..."
strip "./build/sbin/kexec" -o "${temp_dir}/initramfs/sbin/kexec_bin"
cd "${temp_dir}/initramfs/sbin"
log_info_n " Installing kexec wrapper script (and symlink) ..."
echo -e "$kexec_wrapper" >kexec_wrapper.sh
chmod 0755 kexec_wrapper.sh
ln -s kexec_wrapper.sh kexec
echo " Done."
log_ok " Finished building and installing kexec-tools."

log_info_n " Writing some notes on kexectools to /usr/share/kexectools ..."
echo -e "$README_memmax" \
    > "${temp_dir}/initramfs/usr/share/kexectools/README_memmax.txt"
echo " Done."

log_info " Building Busybox ..."
tar -xjf "${temp_dir}/downloads/${bb_tarball_local_name}" -C "${temp_dir}/busybox"
cd "${temp_dir}/busybox/busybox-${busybox_ver}"
make defconfig
check_rc $? "busybox make defconfig"

# We will compile a separate iproute2.
sed -i 's/CONFIG_IPROUTE=y/\# CONFIG_IPROUTE is not set/g' .config
# On Linux >= 6.8 UAPI support for CBQ was removed so we disable traffic ctrl.
sed -i 's/CONFIG_TC=y/\# CONFIG_TC is not set/g' .config
if [[ $no_e2fsprogs != true ]]; then
    sed -i 's/CONFIG_MKE2FS=y/\# CONFIG_MKE2FS is not set/g' .config
fi

# We need to use the full version of grep (/usr/bin/grep) copied from the host.
sed -i 's/CONFIG_GREP=y/\# CONFIG_GREP is not set/g' .config
sed -i 's/CONFIG_EGREP=y/\# CONFIG_EGREP is not set/g' .config
sed -i 's/CONFIG_FGREP=y/\# CONFIG_FGREP is not set/g' .config
sed -i 's/CONFIG_PGREP=y/\# CONFIG_PGREP is not set/g' .config
sed -i 's/CONFIG_FEATURE_GREP_CONTEXT=y/\# CONFIG_FEATURE_GREP_CONTEXT is not set/g' .config

# Verify that the .config exists and is non-empty (make defconfig or one of
# the seds above may have failed silently).
[[ -s .config ]] || { log_err " Busybox .config missing/empty, exiting."; exit 1; }

# make menuconfig
LDFLAGS=--static make -j "$no_comp_cores"
check_rc $? "busybox make"
[[ -f ./busybox ]] || { log_err " busybox binary not found after build, exiting."; exit 1; }
cp .config dot_config
tar -czf "${temp_dir}/initramfs/usr/share/busybox/build.tgz" dot_config Makefile
log_info_n " Installing Busybox binary to initramfs tree ..."
cp "./busybox" "${temp_dir}/initramfs/bin" # This is the stripped version.
cp "./examples/udhcp/simple.script" "${temp_dir}/initramfs/usr/share/udhcpc/"
cd "${temp_dir}/initramfs/bin"
ln -s busybox sh
cd "${temp_dir}/initramfs/sbin"
ln -s /bin/ip ip # Petitboot (in default config.h) expects this.
echo " Done."
log_ok " Finished building and installing Busybox."

log_info_n " Writing Busybox notes/README to /usr/share/busybox ..."
echo -e "$README_PB_Busybox" \
    > "${temp_dir}/initramfs/usr/share/busybox/README_PB_Busybox.txt"
echo " Done."
log_info_n " Writing /etc/motd ..."
echo -e "$etc_motd" > "${temp_dir}/initramfs/etc/motd"
chmod 0644 "${temp_dir}/initramfs/etc/motd"
echo " Done."

log_info " Building iproute2 (ip command) ..."
tar -xf "${temp_dir}/downloads/${ipr2_tarball_local_name}" -C "${temp_dir}/iproute2"
cd "${temp_dir}/iproute2/iproute2-${iproute2_ver}"
./configure --prefix=/usr
check_rc $? "iproute2 configure"
make -j "$no_comp_cores"
check_rc $? "iproute2 make"
[[ -f ./ip/ip ]] || { log_err " ip binary not found after build, exiting."; exit 1; }
tar -czf "${temp_dir}/initramfs/usr/share/iproute2/build.tgz" config.mk Makefile
log_info_n " Installing iproute2 (ip) binary to initramfs tree ..."
strip "./ip/ip" -o "${temp_dir}/initramfs/bin/ip"
echo " Done."
log_ok " Finished building and installing iproute2 (ip command)."

if [[ $no_e2fsprogs != true ]]; then
    log_info " Building e2fsprogs ..."
    tar -xf "${temp_dir}/downloads/${e2fs_tarball_local_name}" -C "${temp_dir}/e2fsprogs"
    cd "${temp_dir}/e2fsprogs/e2fsprogs-${e2fsprogs_ver}"
    mkdir build
    cd ./build
    ../configure --prefix=/usr
    check_rc $? "e2fsprogs configure"
    make -j "$no_comp_cores"
    check_rc $? "e2fsprogs make"
    [[ -f ./misc/mke2fs ]] || { log_err " mke2fs binary not found after build, exiting."; exit 1; }
    tar -czf "${temp_dir}/initramfs/usr/share/e2fsprogs/build.tgz" config.log Makefile
    log_info_n " Installing e2fsprogs binaries to initramfs tree ..."
    strip "./misc/badblocks" -o "${temp_dir}/initramfs/sbin/badblocks"
    strip "./misc/dumpe2fs" -o "${temp_dir}/initramfs/sbin/dumpe2fs"
    strip "./misc/tune2fs" -o "${temp_dir}/initramfs/sbin/tune2fs"
    strip "./misc/mke2fs" -o "${temp_dir}/initramfs/sbin/mke2fs"
    strip "./e2fsck/e2fsck" -o "${temp_dir}/initramfs/sbin/e2fsck"
    strip "./resize/resize2fs" -o "${temp_dir}/initramfs/sbin/resize2fs"
    echo " Done."
    log_ok " Finished building and installing e2fsprogs."
fi

log_info " Building Petitboot ..."
tar -xf "${temp_dir}/downloads/${pb_tarball_local_name}" -C "${temp_dir}/petitboot"
cd "${temp_dir}/petitboot/petitboot-v${petitboot_ver}"

log_info " Applying Petitboot patches (a failed patch is fatal; the"
echo "         resulting initramfs would be suspect and must not be used) ..."
for pb_patch in "${pb_patch_list[@]}"; do
    if ! patch -N -p1 --ignore-whitespace <\
      "${temp_dir}/${bootdisk_dir}/${pb_patch_dir}/${pb_patch}"; then
        log_err " Petitboot patch ${pb_patch} failed to apply, exiting."
        exit 1
    fi
done
log_ok " All Petitboot patches applied successfully."

if [[ $use_build_ver_tag == true ]]; then
    ./configure PACKAGE_VERSION="${petitboot_ver} [${build_ver_tag}]" \
      --prefix=/usr --enable-busybox --with-ncurses --without-twin-x11 \
      --without-twin-fbdev --with-signed-boot
else
    ./configure --prefix=/usr --enable-busybox --with-ncurses --without-twin-x11 \
      --without-twin-fbdev --with-signed-boot
fi
check_rc $? "petitboot configure"
make -j "$no_comp_cores"
check_rc $? "petitboot make"
[[ -f ./ui/ncurses/petitboot-nc ]] || { log_err " petitboot-nc binary not found after build, exiting."; exit 1; }
tar -czf "${temp_dir}/initramfs/usr/share/petitboot/build.tgz" config.log Makefile
log_info_n " Installing Petitboot executable files to initramfs tree ..."
strip "./utils/pb-config" -o "${temp_dir}/initramfs/usr/sbin/pb-config"
cp "./utils/pb-console" "${temp_dir}/initramfs/usr/sbin"
chmod +x "${temp_dir}/initramfs/usr/sbin/pb-console"
strip "./discover/pb-discover" -o "${temp_dir}/initramfs/usr/sbin/pb-discover"
strip "./utils/pb-event" -o "${temp_dir}/initramfs/usr/sbin/pb-event"
cp "./utils/pb-exec" "${temp_dir}/initramfs/usr/sbin"
cp "./utils/pb-plugin" "${temp_dir}/initramfs/usr/sbin"
cp "./utils/pb-sos" "${temp_dir}/initramfs/usr/sbin"
cp "./utils/pb-udhcpc" "${temp_dir}/initramfs/usr/sbin"
chmod +x "${temp_dir}/initramfs/usr/sbin/pb-udhcpc"
strip "./ui/ncurses/petitboot-nc" -o "${temp_dir}/initramfs/usr/sbin/petitboot-nc"
cp "./utils/scsi-rescan" "${temp_dir}/initramfs/usr/sbin"
cp "./utils/bb-kexec-reboot" "${temp_dir}/initramfs/usr/share/petitboot"
cp ./utils/hooks/{01,20,90}-* "${temp_dir}/initramfs/usr/share/petitboot"
echo " Done."
log_ok " Finished building and installing Petitboot."

log_info_n " Writing buildinfo README to /usr/share/petitboot ..."
echo -e "$README_petitboot_initrd" \
  > "${temp_dir}/initramfs/usr/share/petitboot/README_petitboot_initrd.txt"
echo " Done."

log_info " Building eudev ..."
tar -xf "${temp_dir}/downloads/${eudev_tarball_local_name}" -C "${temp_dir}/eudev"
cd "${temp_dir}/eudev/eudev-${eudev_ver}"
mkdir build
cd ./build
../configure --prefix=/usr --enable-blkid --disable-kmod
check_rc $? "eudev configure"
make -j "$no_comp_cores"
check_rc $? "eudev make"
[[ -f ./src/udev/udevd ]] || { log_err " udevd binary not found after build, exiting."; exit 1; }
tar -czf "${temp_dir}/initramfs/usr/share/eudev/build.tgz" config.log Makefile
log_info " Installing eudev binaries and udev rules to initramfs tree ..."
strip "./src/udev/udevadm" -o "${temp_dir}/initramfs/usr/bin/udevadm"
strip "./src/udev/udevd" -o "${temp_dir}/initramfs/usr/bin/udevd"
strip "./src/collect/collect" -o "${temp_dir}/initramfs/usr/bin/collect"
for id_item in ata_id cdrom_id dmi_memory_id fido_id scsi_id; do
    strip "./src/${id_item}/${id_item}" -o "${temp_dir}/initramfs/usr/lib/udev/${id_item}"
done
for udev_rule_item in "${eudev_udev_rules_list[@]}"; do
    cp -v "../rules/${udev_rule_item}" \
        "${temp_dir}/initramfs/usr/lib/udev/rules.d"
done
echo " Done."
log_ok " Finished building and installing eudev."

cd "${temp_dir}/downloads"
log_info " Patching the script 'extract-vmlinux' ..."
if ! patch -N -p1 --ignore-whitespace <\
        "${temp_dir}/${bootdisk_dir}/${misc_patch_dir}/extract-vmlinux.patch"; then
    log_err " The patch on 'extract-vmlinux' was not successfully"
    echo "         applied, exiting."
    exit 1
else
    echo " Done."
fi

log_info_n " Installing the script 'extract-vmlinux-pb' ..."
cp extract-vmlinux "${temp_dir}/initramfs/usr/sbin/extract-vmlinux-pb"
chmod 0755 "${temp_dir}/initramfs/usr/sbin/extract-vmlinux-pb"
echo " Done."

if [[ $have_all_magic == true ]]; then
    log_info_n " Generating the file 'magic.mgc' for the 'file' command ..."
    cd "${temp_dir}/initramfs/usr/share/misc"
    for idx in "${!file_magic_arr[@]}" ; do
        cat "${temp_dir}/downloads/${file_magic_arr[idx]}" | sed -n "${file_magic_cut[idx]}" >>magic
    done
    if file -m magic -C && [[ -f "magic.mgc" ]]; then
        chmod 0755 magic.mgc
        mv magic magic.txt
        echo " Done."
    else
        log_warn " The 'file' command failed to compile the magic file."
        echo "            Kernel decompression will not work."
    fi
fi

# ----------------------------- Find and copy libs ---------------------------

log_info "Finding and listing all libraries required by the executables:"
lib_file_list=()
pre_path=${temp_dir}/initramfs
for exe_name in "${dyn_linked_exe_list[@]}"; do
    exe_name_full=${pre_path}${exe_name}
    # The virtual (kernel) file linux-vdso.so.1 and the interpreter
    # ld-linux-riscv64-lp64d.so.1 are omitted from the list.
    ldd_out=$(ldd "$exe_name_full" 2>&1) || true
    libs_this_exe=$(grep -vE "linux-vdso.so.1|ld-linux-riscv64-lp64d.so.1" <<< "$ldd_out" | cut -d "(" -f1 | cut -d ">" -f2 | tr -d ' ')
    if grep -q "not found" <<< "$ldd_out"; then
        log_err "Not all libraries for ${exe_name} found, exiting.
              Required:
               ${libs_this_exe}"
        exit 1
    else
        echo "Libs (except virtual) required by ${exe_name}:"
        echo "$libs_this_exe"
        if [[ -n $libs_this_exe ]]; then
            # (One library path per line; append each as an array element.)
            mapfile -t _libs_this_exe <<< "$libs_this_exe"
            lib_file_list+=("${_libs_this_exe[@]}")
        fi
    fi
done

mapfile -t lib_file_list_sorted < <(printf '%s\n' "${lib_file_list[@]}" | sort -u)
log_info "Libraries needed by the executables (as per ldd):"
for list_item in "${lib_file_list_sorted[@]}"; do
    echo "$list_item"
done

log_info "Libraries (actual installed name/version) provided to the executables:"
lib_file_inst_list=()
for list_item in "${lib_file_list_sorted[@]}"; do
    lib_file_inst_full=$(realpath "$list_item")
    lib_file_inst_list+=("$lib_file_inst_full")
    echo "$lib_file_inst_full"
done

log_info "Copying interpreter and libraries from host to initramfs tree ..."
# Copy the interpreter and set up the soft link.
cp -v /usr/lib/riscv64-linux-gnu/ld-linux-riscv64-lp64d.so.1 "${temp_dir}/initramfs/usr/lib/riscv64-linux-gnu/ld-linux-riscv64-lp64d.so.1"
cd "${temp_dir}/initramfs/usr/lib"
ln -s riscv64-linux-gnu/ld-linux-riscv64-lp64d.so.1 ld-linux-riscv64-lp64d.so.1
for list_item in "${lib_file_inst_list[@]}"; do # in ${temp_dir}/initramfs/usr/lib
    cp -v "$list_item" "${temp_dir}/initramfs${list_item}"
done
echo " Done."

log_info " Running ldconfig for the libraries in the initramfs tree."
ldconfig -vr "${temp_dir}/initramfs"
log_ok " Finished with libraries."

tot_run_time=$(run_time "stop" "$run_time_start")

# ------------------------------- Packing it up ------------------------------

log_info " Preparing to pack up the initramfs tree into a gzipped cpio archive ..."
cd "${temp_dir}/initramfs"
my_username=$(whoami)
# The sudo grace period is often several mins so you only enter the p/w once.
# (No prompt when already root, e.g. in a CI container.)
if [[ $(id -u) -ne 0 ]]; then
    echo "Enter your password to change ownership (root) of files in initramfs tree:"
fi
sudo chown -R root:root "${temp_dir}/initramfs"
sudo find . | cpio -H newc -o | gzip -c > "../${initrd_pb_name}"
pack_rc=("${PIPESTATUS[@]}")
if [[ ${pack_rc[0]} -ne 0 || ${pack_rc[1]} -ne 0 || ${pack_rc[2]} -ne 0 ]]; then
    log_err " Packing the initramfs failed (find|cpio|gzip rc:"
    echo "         ${pack_rc[*]}), exiting."
    exit 1
fi
initrd_full=${temp_dir}/${initrd_pb_name}
# Verify the packed initramfs. Note: a failed find/cpio can still leave a
# *valid* gzip of an empty/partial cpio stream, so gzip -t alone is not
# enough; the archive must also contain the expected entries.
[[ -s $initrd_full ]] || { log_err " Packed initramfs ${initrd_pb_name} is missing or empty, exiting."; exit 1; }
gzip -t "$initrd_full" || { log_err " Packed initramfs ${initrd_pb_name} failed gzip integrity check, exiting."; exit 1; }
# (cpio -t lists entries without a leading './', e.g. 'init'.)
initrd_cpio_list=$(gzip -dc "$initrd_full" | cpio -t 2>/dev/null)
initrd_entries=$(grep -c . <<< "$initrd_cpio_list") || true
if [[ $initrd_entries -lt 30 ]] || ! grep -qE '^\.?/?init$' <<< "$initrd_cpio_list"; then
    log_err " Packed initramfs ${initrd_pb_name} looks incomplete"
    echo "            ($initrd_entries entries; 'init' entry: $(grep -qE '^\.?/?init$' <<< "$initrd_cpio_list" && echo present || echo MISSING)), exiting."
    exit 1
fi
log_ok " Packed initramfs verified ($initrd_entries entries, 'init' present)."
sudo chown "${my_username}:${my_username}" "../${initrd_pb_name}"
mv "${temp_dir}/${initrd_pb_name}" "$result_dir"
echo " Done. Resulting initramfs: ${initrd_pb_name}"

# Typically the sudo cache timeout is 5m or so so this is not needed:
# echo "Enter your password to change back ownership (you) of initramfs tree:"
my_user=$(whoami)
sudo chown -R "${my_user}:${my_user}" "${temp_dir}/initramfs"

cd "$this_script_dir"
log_ok " Finished building and packing the Petitboot initramfs."

log_ok_n " Saving some build info to result dir ..."
cd "${temp_dir}/"
if [[ $no_e2fsprogs == true ]]; then
    initramfs_tree_name=initramfs_file_tree_noe2fs.txt
else
    initramfs_tree_name=initramfs_file_tree.txt
fi
tree initramfs > "${result_dir}/${initramfs_tree_name}"
# Save the script-defined (non-exported) shell variables for build
# forensics. Exported (environment) variables are deliberately excluded:
# in a CI/CD environment they include tokens/secrets (e.g. CI_JOB_TOKEN,
# GITHUB_TOKEN) which must not end up in the result dir or artifacts.
env_var_list=$(compgen -e)
compgen -v | while read -r line; do
    # Skip the bookkeeping variable below, then skip all exported vars.
    if [[ $line == env_var_list ]]; then continue; fi
    if ! grep -qxF "$line" <<< "$env_var_list"; then
        # (${!line-} rather than ${!line}: under 'set -u' an indirect
        # expansion of bash's automatic empty arrays, e.g. BASH_ALIASES,
        # is an unbound-variable error; the '-' guard yields the same
        # empty value as before.)
        echo "$line=${!line-}"
    fi
done | gzip -c > "${result_dir}/pb_build_vars.txt.gz"
echo " Done."

log_ok_n " Adding timestamp tag to result and temporary dirs ..."
timestamp_iso=$(date -u +"%y%m%dT%H%M"Z)
# Guard against a same-minute re-run: mv-ing a dir into an *existing* dir
# would nest it inside, and later steps (release notes) would pick the old
# dir. If the target name is taken, append a numeric suffix instead.
tstamp_suffix=
while [[ -e "${result_dir}_${timestamp_iso}${tstamp_suffix}" || -e "${temp_dir}_${timestamp_iso}${tstamp_suffix}" ]]; do
    if [[ -z $tstamp_suffix ]]; then
        tstamp_suffix=2
    else
        tstamp_suffix=$((tstamp_suffix + 1))
    fi
done
result_dir_tstamped=${result_dir}_${timestamp_iso}${tstamp_suffix}
mv "$result_dir" "$result_dir_tstamped"
temp_dir_tstamped=${temp_dir}_${timestamp_iso}${tstamp_suffix}
mv "$temp_dir" "$temp_dir_tstamped"
echo " Done."

log_info " The finished initramfs and other output files can be found in"
echo "         ${result_dir_tstamped}"
build_ok=true

# ---------------------------------- Cleanup ---------------------------------

log_info " Cleanup of build area:"

if [[ -t 0 ]]; then
    echo -n "Do you want to delete the build directories?    [n/Y] >"
    read -r do_del_pkgblddirs || do_del_pkgblddirs=""
    if [[ "$do_del_pkgblddirs" != "n" ]]; then
        rm -rf "${temp_dir_tstamped}"/{bootdisk,kexectools,busybox,iproute2,e2fsprogs,petitboot,eudev}
    fi
else
    echo "Non-interactive run: keeping the build directories."
fi

if [[ -t 0 ]]; then
    echo -n "Do you want to delete the download directory?   [n/Y] >"
    read -r do_del_downloads || do_del_downloads=""
    if [[ "$do_del_downloads" != "n" ]]; then
        rm -rf "${temp_dir_tstamped}/downloads"
    fi
else
    echo "Non-interactive run: keeping the download directory."
fi

if [[ -t 0 ]]; then
    echo -n "Do you want to delete the initramfs build tree? [n/Y] >"
    read -r do_del_initramfsdir || do_del_initramfsdir=""
    if [[ "$do_del_initramfsdir" != "n" ]]; then
        if [[ $(id -u) -ne 0 ]]; then
            echo "Enter your password to delete the initramfs dir (owned by root):"
        fi
        sudo rm -rf "${temp_dir_tstamped}/initramfs"
    fi
else
    echo "Non-interactive run: keeping the initramfs build tree."
fi

test_empty_temp=""
if [[ -d ${temp_dir_tstamped} ]]; then
    test_empty_temp=$(ls -A "${temp_dir_tstamped}")
fi
if [[ -z "$test_empty_temp" ]]; then
    echo "Removing the empty directory for temporary files (${temp_dir_tstamped}) ..."
    rmdir "$temp_dir_tstamped"
    echo " Done."
fi

log_ok " Finished executing ${this_script}"
log_info "Run time (excl. user dialogue) [h:m:s]: $tot_run_time"
