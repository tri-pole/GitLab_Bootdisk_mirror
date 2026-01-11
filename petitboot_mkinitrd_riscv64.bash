#!/bin/bash

# petitboot_mkinitrd_riscv64.bash
# 24-12-18: v0.1
# 26-01-01: v0.11
# 26-01-11: v0.12
# Author: Tripole

# Script to build and pack Petitboot for RISCV64 in an initramfs (cpio+gzip).

# Requirements: RISCV64 build host with normal build environment (see below)
# where the user running the script must be in the sudo group. (At the end
# of the build proper ownership of files in the initramfs needs to be set.)

# Tested on: Ubuntu 22.04.5 host running in QEMU (qemu-system-riscv64) on
# x86_64 and Ubuntu 24.04.1 running on VisionFive 2. (Cross compilation is
# not possible since some libs/utils are copied from the build host, see
# below.) The initramfs has been tested on VisionFive 2, v1.3b.

# Dependencies: GNU build tools w/ compiler suite, installed dependencies for
# the packages kexec, busybox, iproute2, e2fsprogs, petitboot and eudev.
# For example, on a default installation of Debian 12.8 or Ubuntu Server
# 22.04.5 all the dependencies should be satisfied by installing the following
# packages (along with their dependencies):
# autoconf bison build-essential flex gawk gettext git gperf libasprintf-dev
# libblkid-dev libdevmapper-dev libdw-dev libelf-dev libgd-tools
# libgettextpo-dev libgpgme-dev liblzma-dev libncurses-dev libssl-dev libtool
# libudev-dev pkg-config tree u-boot-tools wget
# The build host must also have installed some commands that are copied (along
# with some conf files), namely file, grep, unzstd (see copy_*_list below).

# Patches: There are some patches for Petitboot applied to enhance/adjust
# functionality and there are patches needed to get RISCV64 support in the
# version (fork) of kexec-tools that we use here (see below). These patches
# downloaded and applied as part of the build. The script extract-vmlinux from
# Linux src is downloaded and patched at build time as well.

# Usage: The script can be run as an ordinary user but near the end it will
# ask for the user password to execute a sudo command to change ownership of
# the files in the initramfs. During execution of this script, two dirs will
# be created in the same directory as this script; one result dir and one
# temp file directory hearchy. (Near the end of this script you will be asked
# which of the temp dirs you want to delete.) Run time for the script is ~30m
# in QEMU (on a reasonably modern box) and less than 15m on bare metal.

# Inspiration taken from: https://www.raptorengineering.com/content/kb/1.html

# About the build: By default, the build config files etc. for each component
# are stored also in the resulting initramfs; search for build.tgz in the code
# below (these files are small, but you can omit them to save space).

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
# - Sometimes it is necessary to hit "Rescan devices" in Petitboot in order to
#   see all bootable devices attached (if devices respond slowly, e.g. on USB).
#   (There is a default delay of a few secs when starting the Petitboot main
#   menu window to allow for all devices to be detected before the display is
#   drawn but when many devices are connected the scan may take longer.)
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

# --------------------------------- Parameters -------------------------------

# If used, this tag is inserted inside the header in the Petitboot main menu
# where it normally says e.g. Petitboot (v1.15) so that instead it will say
# something like Petitboot (v1.15 (mytaglinehere))
to_day=$(date +"%y%m%d")
mytag="3p-$to_day"
build_ver_tag="$mytag"
# If the next line is set to true, the build_ver_tag is shown in the top
# margin in the Petitboot main menu (after the Petitboot version number)
# and the tag is also applied to the resulting initramfs(s) (see below).
use_build_ver_tag=true # {true_false}

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
bootdisk_url="https://gitlab.com/tripole-inc/bootdisk.git"
bootdisk_dir=bootdisk # Clone into dir, relative to $temp_dir

# Script to decompress the Linux kernel.
extract_vmlinux_url="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/scripts/extract-vmlinux?h=v6.18.2"
misc_patch_dir="misc_patches" # Relative to $bootdisk_dir

# Definitions for categories 'linux', 'archive' and 'compress' for 'file' cmd.
file_magic_ver="FILE5_46"
file_magic_url_base="https://raw.githubusercontent.com/file/file/refs/tags/${file_magic_ver}/magic/Magdir"
file_magic_arr=(linux archive compress)
file_magic_cut=("524,530p" "327,419p" "1,458p") # Arguments to sed -n below.

kexectools_ver="sf-rv-Image-56552e1"
kexectools_branch="rv-Image"
kexectools_url="https://github.com/sugarfillet/kexec-tools.git"
kexectools_commit_sha="56552e1a2f1f445f40dcbadf27129fcd7215df5c"
kexectools_loc_build_dir="kexectools/kexec-tools-${kexectools_ver}"
kt_patch_dir="kexectools_patches" # Relative to $bootdisk_dir
kt_fix_initrd_in_mem_pos_patch_name="kexec_fix_initrd_in_mem_pos.patch"
clone_kexectools_repo=true

busybox_ver="1.36.1"
busybox_url_base="https://busybox.net/downloads"
busybox_tarball_rpo=busybox-${busybox_ver}.tar.bz2
busybox_tarball_loc=busybox-v${busybox_ver}.tar.bz2
# busybox_bch=$(sed -e 's/\./_/g' <<< $busybox_ver)
# busybox_git_url="https://git.busybox.net/busybox"

iproute2_ver="6.12.0"
iproute2_url_base="https://github.com/iproute2/iproute2/archive/refs/tags"
# iproute2_url_base="https://git.kernel.org/pub/scm/network/iproute2/iproute2.git/snapshot"
iproute2_tarball_rpo=v${iproute2_ver}.tar.gz
iproute2_tarball_loc=iproute2-$iproute2_tarball_rpo

e2fsprogs_ver="1.47.2"
e2fsprogs_url_base="https://github.com/tytso/e2fsprogs/archive/refs/tags"
e2fsprogs_tarball_rpo=v${e2fsprogs_ver}.tar.gz
e2fsprogs_tarball_loc=e2fsprogs-$e2fsprogs_tarball_rpo

petitboot_ver="1.15"
petitboot_url_base="https://github.com/open-power/petitboot/releases/download"/v${petitboot_ver}
petitboot_tarball_rpo=petitboot-v${petitboot_ver}.tar.gz
petitboot_tarball_loc=$petitboot_tarball_rpo
pb_patch_dir="petitboot_patches" # Relative to dir of this script.
pb_1v13_add_grubcfg_path_patch_fname="pb_1v13_add_grubcfg_path_patch.patch"
pb_1v13_ui_and_bootcfg_patch_fname="pb_1v13_ui_and_bootcfg_patch.patch"
pb_add_riscv64_functionality_patch_fname="pb_add_riscv64_functionality.patch"

pb_patch_dir="petitboot_patches" # Relative to $bootdisk_dir
pb_1v13_add_grubcfg_path_patch_fname="pb_1v13_add_grubcfg_path.patch"
pb_1v13_ui_and_bootcfg_patch_fname="pb_1v13_ui_and_bootcfg.patch"

eudev_ver="3.2.14"
eudev_url_base="https://github.com/eudev-project/eudev/releases/download"/v${eudev_ver}
eudev_tarball_rpo=eudev-${eudev_ver}.tar.gz
eudev_tarball_loc=eudev-v${eudev_ver}.tar.gz
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
terminfo_dir="/usr/lib/terminfo"
pb_term_list="ansi dumb linux vt220"

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
    dyn_linked_exe_list=${dyn_linked_exe_list_noe2fs[@]}
else
    dyn_linked_exe_list=(${dyn_linked_exe_list_noe2fs[@]}
                         ${dyn_linked_exe_list_e2fs[@]})
fi

# These files are not necessary for Petitboot to start but decompression of
# kernel/initramfs will not work if file or grep (the complete one) is missing.
# (The binary for can probably be omitted.)
copy_file_list=("/usr/bin/file" "/usr/bin/grep" "/usr/bin/unzstd" "/usr/bin/gpg")

stat_linked_exe_list=("/bin/busybox")

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
    # We leave one core for other work (typically no_comp_cores = 4 or more).
    no_comp_cores=$(($no_comp_cores -1))
else
    no_comp_cores=1
fi

# ---------------------------------- Here docs -------------------------------

README_petitboot_initrd=$(cat <<EOF

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

usr_share_udhcpc_default_script=$(cat <<"EOF"
#!/bin/sh

/usr/share/udhcpc/simple.script "$@"
/usr/sbin/pb-udhcpc "$@"
EOF
)

init_script=$(cat <<"EOF"
#!/bin/sh

# 22-07-29, 23-10-07, 26-01-05, Tripole
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
#   via the shell that kxec_wrapper is executed in (Petitboot main UI or the  
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

remote_mode=""
netdev="eth0"
if [ "$pb_nonet" = "false" ] && [ ! -z "$pb_rootpw" ] && \
     ( [ ! -z "$pb_ipstr" ] || [ ! -z "$pb_hostname" ] ) ; then
    if [ ! -z "$pb_hostname" ]; then
        remote_mode="dhcp"
    else
        remote_mode="static"
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
if [ "$pb_no_autoboot" = "true" ] ; then
   pb_discover_cmd="/usr/sbin/pb-discover -a"
fi

# The verbose setting here only gives a little more info in the PB log.
pb_nc_cmd="/usr/sbin/petitboot-nc -v"

# This hack with a delay + some writing to the tty seems to be needed for the
# ncurses menu/UI to come up correctly (on some monitors/ttys). Also, some time
# may be needed for udev/pb-discover to detect all devices/partitions properly.
if [ "$delay" -gt "1" ]; then
    echo -n "Starting Petitboot in ..."
    while [ "$delay" -gt "0" ] ; do
        echo -n "${delay}..."
        sleep 1s
        delay=$((delay -1))
    done
else
    echo "Starting Petitboot ..."
    sleep 1s
fi

if [ "$pb_nonet" = "true" ] ; then
    # Set up a network namespace to deny Petiboot access to external networks.
    /bin/ip netns add mininet
    /bin/ip netns exec mininet /bin/ip link set dev lo up
    /bin/ip netns exec mininet $pb_discover_cmd 2>/dev/null &
    /bin/ip netns exec mininet $pb_nc_cmd
elif [ ! -z "$remote_mode" ] ; then
    mkdir /dev/pts
    mount -t devpts none /dev/pts
    echo "23 stream tcp nowait root /usr/sbin/telnetd telnetd -l /bin/login" > /etc/inetd.conf
    echo -e "export pb_mem_max=$pb_mem_max" > /root/.profile
    echo -e "$pb_discover_cmd 2>/dev/null &" >> /root/.profile
    echo -e "$pb_nc_cmd" >> /root/.profile
    echo "root:x:0:0:root:/root:/bin/sh" > /etc/passwd
    echo -e "${pb_rootpw}\\n${pb_rootpw}" | passwd >/dev/null 2>&1
    echo "[ -- Petitboot in remote mode -- ]"
    ip_addr=$(echo $pb_ipstr | cut -d '/' -f1)
    if [ "$remote_mode" = "dhcp" ]; then
        hostname $pb_hostname
        udhcpc -i $netdev -x hostname:$pb_hostname
        echo "[ -- Waiting for telnet login (root, tcp/23) on host: '$pb_hostname' -- ]"
    else
        hostname pb-$ip_addr
        ip addr add $pb_ipstr dev $netdev
        sleep 1
        ip link set dev $netdev up
        echo "[ -- Waiting for telnet login (root, tcp/23) on IP: $ip_addr -- ]"
    fi
    /usr/sbin/telnetd
    echo "[ To resume Petitboot UI here, do: killall telnetd && source /root/.profile ]"
else
    $pb_discover_cmd 2>/dev/null &
    $pb_nc_cmd
fi

# Lockdown is related to (failed) secure boot (search for LOCKDOWN in PB src).
if [ -e /etc/pb-lockdown ] ; then
    echo "Failed to launch Petitboot, rebooting!"
    echo 1 > /proc/sys/kernel/sysrq
    echo b > /proc/sysrq-trigger
else
    echo "No Petitboot UI on console. Dropping to a shell here."
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
# kexec reboot. It is unclear what exactly causes this but it is related to how
# kernels (possibly with help of u-boot) handle the info in the dtb to
# determine the (total) physical memory size in cases when this size is not
# explicitly stated in the dtb. Some kernels (e.g. openSUSE's) are always aware
# of all memory, but others (e.g. Debian's) are not.
# Since kexec loads the new initrd at the top of the memory, as seen by the
# first (loading) kernel, this can be outside what the second (loaded) kernel
# is aware of.
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
EOF
)

kexec_wrapper=$(cat <<"EOF"
#!/bin/sh

# 26-01-01, 26-01-07, Tripole

# This script performs filtering of the kexec call from Petitboot and can do
# (optional) decompression of kernels before calling kexec (the binary).
# The script can use two arguments from the kernel command line; pb_no_decompr
# and pb_mem_max. If pb_no_decompr=true then the code for kernel decompression
# below is disabled and the kernel is loaded as-is (always). The argument
# pb_mem_max can be used to restrict the loading region of the initrd during
# kexec which can sometimes be needed (for more info, see the file
# /usr/share/kexectools/README_memmax.txt).
# For RISCV64 we use a kexec binary which is based on a patched version of the
# code due to Nick Kossifidis and Song Shuai (sugarfillet) described here:
# https://lkml.iu.edu/hypermail/linux/kernel/2309.1/07133.html.

kexec_binary="/sbin/kexec_bin" # The real McCoy.

# The environment variables pb_no_decompr and pb_mem_max are explained below.
if [ -z "$pb_no_decompr" ]; then
    pb_no_decompr=false
fi
call_memmax_str=""
if [ ! -z "$pb_mem_max" ]; then
    call_memmax_str=" --mem-max="$pb_mem_max
fi

# The kexec call (issued by Petitboot) invoking this script can be only one of
# the following two forms (for details, see e.g. boot.c in the Petitboot src
# and/or run /usr/sbin/petitboot-nc -v in ./init):
# (1) kexec -e {-f} # The -f switch is added by Petitboot only after -e fails.
# (2) kexec -{l,s} --initrd=/path/to/initrd \
#                  --dtb=/path/to/dtb \
#                  --append=<can_be_several_whitespace_separated_substrings> \
#                  /path/to/kernel
# where the all options except the last /path/to/kernel are optional.
# The call kexec -s (file based kexec syscall) is here translated to kexec -l
# (ordinary kexec operation).
# (The kexec binary accepts both --command-line and --append (to command line).
# If --command-line is absent it uses the contents from --append as cmd. line.)

# In this script we unpack the kexec call, filter the arguments, and send a
# repackaged version to kexec_binary (after optional kernel decompression).

call_str=""
case "$1" in
    "-s"|"-l")
        shift # We drop the leading -s or -l in "$@"
        arg_str="$@"; num_args="$#"
        par_str=""; kernel_str=""; arg_num=1
        while [ "$arg_num" -lt "$num_args" ]; do # All args before kernel.
            par_str=${par_str}" "$1
            shift; arg_num=$((arg_num +1))
        done
        kernel_str="$1"
        par_str=$(echo $par_str | xargs) # Trim leading and trailing space.

        # If compression is enabled, check first if the kernel is uncompressed.
        # If it is not, then decompress the kernel.
        kernel_path=$kernel_str
        if [ "$pb_no_decompr" != "true" ]; then
            kernel_path_real=$(realpath $kernel_str)
            file $kernel_path_real | grep -q 'Linux kernel.*boot executable' >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                kernel_path=/tmp/vmlinux-pb
                eval "extract-vmlinux-pb $kernel_path_real >$kernel_path" 2>/dev/null
            fi
        fi

        # Base part of call_str.
        if [ -z "$par_str" ]; then
            call_str="--load $kernel_path"
        else
            call_str="--load $kernel_path $par_str"
        fi

        # Add the optional kexec mem-max argument (see trailing remarks).
        call_str=${call_str}${call_memmax_str}
    ;;
    "-e")
        # If telnetd is running (remote mode), kill it before kexec -e.
        kill -s SIGTERM $(pidof telnetd) >/dev/null 2>&1
        call_str=$1
    ;;
    *)
        echo "${0}: Malformed command string, exiting."
        exit 1
esac

# echo "Call string sent to kexec executable: [$call_str]"

eval "$kexec_binary $call_str"
EOF
)

# --------------------------------- Functions -------------------------------

do_download() {
    bundle_name=$1
    bundle_pkg_url=$2
    bundle_pkg_loc=$3
    if [[ ! -f $bundle_pkg_loc ]]; then
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
    else
        echo -e ${k_msg}" Skipping download of ${bundle_name}; file already exists."
    fi
}

# ------------------------------- Preliminaries -----------------------------

PATH=${PATH}:/usr/sbin

this_arch=$(arch)

if [[ "$this_arch" == "riscv64" ]]; then
    uboot_arch=riscv
else
    echo -e ${e_msg}" -- Unsupported arch: ${this_arch}, exiting. --"
    exit 1
fi

# Tag to be applied to the name of the resulting initrd (and the uInitrd).
if [[ $use_build_ver_tag == true ]]; then
    initrd_pb_tag=v${petitboot_ver}-${this_arch}-${build_ver_tag}
else
    initrd_pb_tag=v${petitboot_ver}-${this_arch}
fi
initrd_pb_name=initrd-pb-${initrd_pb_tag}
uInitrd_pb_name=uInitrd-pb-${initrd_pb_tag}

if [[ $no_e2fsprogs != true ]]; then
    echo -e ${i_msg}" -- Builting the Petitboot initramfs for $this_arch (with e2fsprogs) --"
else
    echo -e ${i_msg}" -- Builting the Petitboot initramfs for $this_arch (without e2fsprogs) --"
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
mkdir ${temp_dir}/initramfs/usr/lib/${this_arch}-linux-gnu
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
mkdir ${temp_dir}/initramfs/usr/share/misc
mkdir ${temp_dir}/initramfs/var
mkdir ${temp_dir}/initramfs/var/log
mkdir ${temp_dir}/initramfs/var/log/petitboot
mkdir ${temp_dir}/initramfs/var/run
mkdir ${temp_dir}/initramfs/var/run/netns
cd ${temp_dir}/initramfs
ln -s usr/lib lib
echo " Done."

echo -e -n ${i_msg}" Setting up 'init' script in initramfs ..."
echo -e "$init_script" >${temp_dir}/initramfs/init
chmod +x ${temp_dir}/initramfs/init
echo " Done."

echo -e ${i_msg}" Setting up basic configuration files in initramfs tree ..."
echo    "         /etc/{group,mdev.conf,nsswitch.conf}"
echo -e "$etc_group" >${temp_dir}/initramfs/etc/group
touch ${temp_dir}/initramfs/etc/mdev.conf
echo -e "$etc_nsswitch_conf" >${temp_dir}/initramfs/etc/nsswitch.conf
echo    "         /usr/share/udhcpc/default.script"
echo -e "$usr_share_udhcpc_default_script" \
>${temp_dir}/initramfs/usr/share/udhcpc/default.script
chmod 0755 ${temp_dir}/initramfs/usr/share/udhcpc/default.script
echo " Done."

echo -e -n ${i_msg}" Setting up 'sysinfo' script in initramfs tree ..."
cd ${temp_dir}/initramfs/sbin
echo -e "$sbin_sysinfo" >sysinfo
chmod +x sysinfo
ln -s sysinfo dmidecode
echo " Done."

# The terminal used by Petitboot is defined in ${pb_build}/utils/pb-console
# as TERM=linux which is often defined in /lib/terminfo/l/linux (but note
# that we have sýmlinked /lib to /usr/lib above).
echo -e -n ${i_msg}" Copying terminfo files from host to initramfs ..."
for terminfo_file in $pb_term_list ; do
    terminfo_dir_lett=${terminfo_file:0:1}
    terminfo_file_path=${terminfo_dir}/${terminfo_dir_lett}/${terminfo_file}
    if [[ -f "$terminfo_file_path" ]]; then # We do not resolve symlinks here.
        # echo "Found terminfo file ${terminfo_file}, copying."
        mkdir -p ${temp_dir}/initramfs/usr/lib/terminfo/${terminfo_dir_lett}
        cp $terminfo_file_path \
          ${temp_dir}/initramfs/usr/lib/terminfo/${terminfo_dir_lett}
    else
        echo -e ${e_msg}" Cannot find the terminfo file ${terminfo_file}, exiting."
        exit 1
    fi
done
echo " Done."

# Petitboot will start without these files, but it may not function properly.
for loc_file in ${copy_file_list[@]}; do
    mkdir -p $(dirname $loc_file)
    echo -e -n ${i_msg}" Copying the file $loc_file to initramfs tree ..."
    if [[ -f $loc_file ]]; then
        cp $loc_file ${temp_dir}/initramfs${loc_file}
        chmod 0755 ${temp_dir}/initramfs${loc_file}
        echo " Done."
    else
        echo -e ${w_msg}" Could not find the file ${loc_file}."
    fi
done

# -------------------------------- Downloads --------------------------------

# This is small so we always clone it.
echo -e ${i_msg}" Cloning the bootdisk repo $bootdisk_url"
echo            "         to the local dir ${temp_dir}/${bootdisk_dir}"
git clone --depth=1 "$bootdisk_url" "${temp_dir}/${bootdisk_dir}"
if [[ $? == 0 ]]; then
    echo -e ${k_msg}" Done. bootdisk repo successfully cloned."
else
    echo -e ${e_msg}" Failed to clone bootdisk repo, exiting."
    exit 1
fi

if [[ $clone_kexectools_repo == true ]]; then
    echo -e ${i_msg}" Cloning kexectools from"
    echo "         repo $kexectools_url"
    echo "         branch $kexectools_branch"
    echo "         commit $kexectools_commit_sha"
    echo "         to local (build) dir $kexectools_loc_build_dir"

    mkdir -p ${temp_dir}/${kexectools_loc_build_dir}
    git clone -b $kexectools_branch $kexectools_url \
	${temp_dir}/${kexectools_loc_build_dir}
    cd ${temp_dir}/${kexectools_loc_build_dir}
    git reset --hard $kexectools_commit_sha
    if [[ $? == 0 ]]; then
        echo -e ${k_msg}" Done. kexec-tools successfully cloned and set up."
    else
        echo -e ${e_msg}" Failed to clone and set up kexec-tools, exiting."
        exit 1
    fi
fi

busybox_pkg_url=${busybox_url_base}/${busybox_tarball_rpo}
busybox_pkg_loc=${temp_dir}/downloads/${busybox_tarball_loc}
do_download "Busybox" $busybox_pkg_url $busybox_pkg_loc

iproute2_pkg_url=${iproute2_url_base}/${iproute2_tarball_rpo}
iproute2_pkg_loc=${temp_dir}/downloads/${iproute2_tarball_loc}
do_download "iproute2" $iproute2_pkg_url $iproute2_pkg_loc

if [[ $no_e2fsprogs != true ]]; then
    e2fsprogs_pkg_url=${e2fsprogs_url_base}/${e2fsprogs_tarball_rpo}
    e2fsprogs_pkg_loc=${temp_dir}/downloads/${e2fsprogs_tarball_loc}
    do_download "e2fsprogs" $e2fsprogs_pkg_url $e2fsprogs_pkg_loc
fi

petitboot_pkg_url=${petitboot_url_base}/${petitboot_tarball_rpo}
petitboot_pkg_loc=${temp_dir}/downloads/${petitboot_tarball_loc}
do_download "Petitboot" $petitboot_pkg_url $petitboot_pkg_loc

eudev_pkg_url=${eudev_url_base}/${eudev_tarball_rpo}
eudev_pkg_loc=${temp_dir}/downloads/${eudev_tarball_loc}
do_download "eudev" $eudev_pkg_url $eudev_pkg_loc

echo -e ${i_msg}" Downloading the script 'extract-vmlinux' from Linux src ..."
wget $extract_vmlinux_url -O ${temp_dir}/downloads/extract-vmlinux
if [[ $? == 0 ]]; then
    echo -e ${k_msg}" Done. The script 'extract-vmlinux' successfully downloaded."
else
    echo -e ${w_msg}" Failed to download 'extract-vmlinux', kernel decompr. will not work."
fi

echo -e ${i_msg}" Downloading magic file definitions for kernel and initramfs ..."
have_all_magic=true
for file_magic in ${file_magic_arr[@]} ; do
    wget ${file_magic_url_base}/$file_magic -O ${temp_dir}/downloads/$file_magic
    if [[ $? != 0 ]]; then
        echo -e ${w_msg}" Failed to download magic file ${file_magic}."
        have_all_magic=false
    fi
done
if [[ $have_all_magic == true ]]; then
    echo -e ${k_msg}" Done. All magic file definitions successfully downloaded."
else
    echo " Kernel decompression will not work due to failed downloads."
fi

# ---------------------------------- Build ---------------------------------

echo -e ${i_msg}" Building kexec-tools ..."
cd  ${temp_dir}/${kexectools_loc_build_dir}
echo -e ${i_msg}" Applying kexec-tools patches ..."
kt_patches_applied_ok=true
case "$kexectools_ver" in
    "sf-rv-Image-56552e1")
        patch -N -p1 <\
          ${temp_dir}/${bootdisk_dir}/${kt_patch_dir}/${kt_fix_initrd_in_mem_pos_patch_name}
        if [[ "$?" != 0 ]]; then
            kt_patches_applied_ok=false
        fi
    ;;
    *)
        echo " (No patches available for version $kexectools_ver of kexec-tools.)"
    ;;
esac
if [[ $kt_patches_applied_ok == true ]]; then
    echo -e ${k_msg}" All kexec-tools patches applied successfully."
else
    echo -e ${w_msg}" Not all kexec-tools patches applied successfully, check messages."
fi
autoupdate
./bootstrap
./configure --prefix=/usr
make -j $no_comp_cores
tar -czf ${temp_dir}/initramfs/usr/share/kexectools/build.tgz config.log configure.ac Makefile
echo -e ${i_msg}" Installing kexec binary to initramfs tree ..."
strip ./build/sbin/kexec -o ${temp_dir}/initramfs/sbin/kexec_bin
cd ${temp_dir}/initramfs/sbin
echo -e -n ${i_msg}" Installing kexec wrapper script (and symlink) ..."
echo -e "$kexec_wrapper" >kexec_wrapper.sh
chmod 0755 kexec_wrapper.sh
ln -s kexec_wrapper.sh kexec
echo " Done."
echo -e ${k_msg}" Finished building and installing kexec-tools."

echo -e -n ${i_msg}" Writing some notes on kexectools to /usr/share/kexectools ..."
echo -e "$README_memmax" \
    >${temp_dir}/initramfs/usr/share/kexectools/README_memmax.txt
echo " Done."

echo -e ${i_msg}" Building Busybox ..."
tar -xjf ${temp_dir}/downloads/${busybox_tarball_loc} -C ${temp_dir}/busybox
cd ${temp_dir}/busybox/busybox-${busybox_ver}
make defconfig

# We will compile a separate iproute2.
sed -i 's/CONFIG_IPROUTE=y/\# CONFIG_IPROUTE is not set/g' .config
if [[ $no_e2fsprogs != true ]]; then
    sed -i 's/CONFIG_MKE2FS=y/\# CONFIG_MKE2FS is not set/g' .config
fi

# We need to use the full version of grep (/usr/bin/grep) copied from the host.
sed -i 's/CONFIG_GREP=y/\# CONFIG_GREP is not set/g' .config
sed -i 's/CONFIG_EGREP=y/\# CONFIG_EGREP is not set/g' .config
sed -i 's/CONFIG_FGREP=y/\# CONFIG_FGREP is not set/g' .config
sed -i 's/CONFIG_PGREP=y/\# CONFIG_PGREP is not set/g' .config
sed -i 's/CONFIG_FEATURE_GREP_CONTEXT=y/\# CONFIG_FEATURE_GREP_CONTEXT is not set/g' .config

# make menuconfig
LDFLAGS=--static make -j $no_comp_cores
cp .config dot_config
tar -czf ${temp_dir}/initramfs/usr/share/busybox/build.tgz dot_config Makefile
echo -e -n ${i_msg}" Installing Busybox binary to initramfs tree ..."
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

echo -e ${i_msg}" Building iproute2 (ip command) ..."
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
          ${temp_dir}/${bootdisk_dir}/${pb_patch_dir}/${pb_1v13_add_grubcfg_path_patch_fname}
        if [[ "$?" != 0 ]]; then
            pb_patches_applied_ok=false
        fi
        patch -N -p1 --ignore-whitespace <\
          ${temp_dir}/${bootdisk_dir}/${pb_patch_dir}/${pb_1v13_ui_and_bootcfg_patch_fname}
        if [[ "$?" != 0 ]]; then
            pb_patches_applied_ok=false
        fi
	patch -N -p1 --ignore-whitespace <\
	  ${temp_dir}/${bootdisk_dir}/${pb_patch_dir}/${pb_add_riscv64_functionality_patch_fname}
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
echo -e -n ${i_msg}" Installing Petitboot executable files to initramfs tree ..."
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

cd ${temp_dir}/downloads
echo -e ${i_msg}" Patching the script 'extract-vmlinux' ..."
patch -N -p1 --ignore-whitespace <\
        ${temp_dir}/${bootdisk_dir}/${misc_patch_dir}/extract-vmlinux.patch
if [[ "$?" != 0 ]]; then
    echo -e ${w_msg}"\n The patch on 'extract-vmlinux' was not successfully applied."
else
    echo " Done."
fi

echo -e -n ${i_msg}" Installing the script 'extract-vmlinux-pb' ..."
cp extract-vmlinux ${temp_dir}/initramfs/usr/sbin/extract-vmlinux-pb
chmod 0755 ${temp_dir}/initramfs/usr/sbin/extract-vmlinux-pb
echo " Done."

if [[ $have_all_magic == true ]]; then
    echo -e -n ${i_msg}" Generating the file 'magic.mgc' for the 'file' command ..."
    cd ${temp_dir}/initramfs/usr/share/misc
    for idx in "${!file_magic_arr[@]}" ; do
        cat ${temp_dir}/downloads/"${file_magic_arr[idx]}" | sed -n "${file_magic_cut[idx]}" >>magic
    done
    file -m magic -C
    if [[ ! -f "magic.mgc" ]]; then
        echo -e ${w_msg}" The 'file' command failed to compile the magic file."
        echo "            Kernel decompression will not work."
    else
        chmod 0755 magic.mgc
        mv magic magic.txt
        echo " Done."
    fi
fi

# ----------------------------- Find and copy libs ---------------------------

echo -e ${i_msg}" Finding and listing all libraries required by the executables:"
lib_file_list=()
pre_path=${temp_dir}/initramfs
for exe_name in ${dyn_linked_exe_list[@]}; do
    exe_name_full=${pre_path}${exe_name}
    # libs_this_exe=$(objdump -p $exe_name_full | grep "NEEDED" | sed 's/NEEDED//g' | tr -d " ") # Note reliable
    # The next line is perhaps not reliable, but for now it will do.
    # The virtual (kernel) file linux-vdso.so.1 and the interpreter
    # ld-linux-riscv64-lp64d.so.1 are omitted from the list.
    libs_this_exe=$(ldd $exe_name_full | grep -vE "linux-vdso.so.1|ld-linux-riscv64-lp64d.so.1" | cut -d "(" -f1 | cut -d ">" -f2 | tr -d ' ')
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

echo -e ${i_msg}" Copying interpreter and libraries from host to initramfs tree ..."
# Copy the interpreter and set up the soft link.
cp -v /usr/lib/riscv64-linux-gnu/ld-linux-riscv64-lp64d.so.1 ${temp_dir}/initramfs/usr/lib/riscv64-linux-gnu/ld-linux-riscv64-lp64d.so.1
cd ${temp_dir}/initramfs/usr/lib
ln -s riscv64-linux-gnu/ld-linux-riscv64-lp64d.so.1 ld-linux-riscv64-lp64d.so.1
for list_item in ${lib_file_inst_list[@]}; do # in ${temp_dir}/initramfs/usr/lib
    lib_file_inst_full=$(realpath $list_item)
    cp -v ${lib_file_inst_full} ${temp_dir}/initramfs${lib_file_inst_full}
done
echo " Done."

echo -e ${i_msg}" Running ldconfig for the libraries in the initramfs tree."
ldconfig -vr ${temp_dir}/initramfs
echo -e ${k_msg}" Finished with libraries."

# ------------------------------- Packing it up ------------------------------

echo -e ${i_msg}" Preparing to pack up the initramfs tree into a gzipped cpio archive ..."
cd ${temp_dir}/initramfs
my_username=$(whoami)
echo "Enter your password to change ownership (root) of files in initramfs tree:"
# The sudo grace period is often several mins so you only enter the p/w once.
sudo chown -R root:root ${temp_dir}/initramfs
sudo find . | cpio -H newc -o | gzip -c > ../${initrd_pb_name}
sudo chown $my_username:$my_username ../${initrd_pb_name}
mv ${temp_dir}/${initrd_pb_name} $result_dir
echo " Done. Resulting initramfs: ${initrd_pb_name}"

# Typically the sudo cache timeout is 5m or so so this is not needed:
# echo "Enter your password to change back ownership (you) of initramfs tree:"
my_user=$(whoami)
sudo chown -R $my_user:$my_user ${temp_dir}/initramfs

cd $this_script_dir
echo -e ${k_msg}" Finished building and packing the Petitboot initramfs."

echo -e -n ${k_msg}" Saving some build info to result dir ..."
cd ${temp_dir}/
if [[ $no_e2fsprogs == true ]]; then
    initramfs_tree_name=initramfs_file_tree_noe2fs.txt
else
    initramfs_tree_name=initramfs_file_tree.txt
fi
tree initramfs >${result_dir}/${initramfs_tree_name}
compgen -v | while read line; do echo $line=${!line}; done \
    | gzip -c >${result_dir}/pb_build_vars.txt.gz
echo " Done."

echo -e -n ${k_msg}" Adding timestamp tag to result and temporary dirs ..."
timestamp_iso=$(date +%y%m%dT%H%M)
result_dir_tstamped=${result_dir}_${timestamp_iso}
mv $result_dir $result_dir_tstamped
temp_dir_tstamped=${temp_dir}_${timestamp_iso}
mv $temp_dir $temp_dir_tstamped
echo " Done."

echo -e ${i_msg}" The finished initramfs and other output files can be found in"
echo -e "         "${result_dir_tstamped}

# ---------------------------------- Cleanup ---------------------------------

echo -e ${i_msg}" Cleanup of build area:"

echo -n "Do you want to delete the build directories?    [n/Y] >"
read do_del_pkgblddirs
if [[ "$do_del_pkgblddirs" != "n" ]]; then
    rm -rf ${temp_dir_tstamped}/{bootdisk,kexectools,busybox,iproute2,e2fsprogs,petitboot,eudev}
fi

echo -n "Do you want to delete the download directory?   [n/Y] >"
read do_del_downloads
if [[ "$do_del_pkgblddirs" != "n" ]]; then
    rm -rf ${temp_dir_tstamped}/downloads
fi

echo -n "Do you want to delete the initramfs build tree? [n/Y] >"
read do_del_initramfsdir
if [[ "$do_del_initramfsdir" != "n" ]]; then
    echo "Enter your password to delete the initramfs dir (owned by root):"
    sudo rm -rf ${temp_dir_tstamped}/initramfs
fi

test_empty_temp=$(ls -A ${temp_dir_tstamped})
if [[ -z "$test_empty_temp" ]]; then
    echo -e "Removing the empty directory for temporary files (${temp_dir_tstamped}) ..."
    rmdir ${temp_dir_tstamped}
    echo " Done."
fi

echo -e ${k_msg}" Finished executing ${this_script}"
