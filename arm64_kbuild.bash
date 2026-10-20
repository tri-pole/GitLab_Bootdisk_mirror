#!/bin/bash
#
# arm64_kbuild.bash
# v0.15 - 2026-10-19: reference rewrite of v0.13 (by Tripole), mostly by Qwen.
#
# Script to compile the ARM64 Linux kernel and package the result in a tarball.
# The script must be executed (as root) on an Ubuntu/Debian type machine,
# either natively on aarch64/ARM64 or virtualized (using qemu-aarch64-static)
# on x86_64/amd64. The output of the script is a set of tarballs containing (1)
# a kernel image file (uncompressed but called vmlinuz), an initramfs
# (initrd.img, gzipped, based on an Ubuntu rootfs, as well as u-boot tagged
# uInitrd), config and System.map files, (2) dtb files for the SoCs specified,
# (3) header files, (4) a modules tree and (5) any patches applied during the
# build process. (sha256sums for all tarballs are included.) A standard kernel
# build environment is required (some of the requirements are checked below,
# but far from all).
#
# Usage: (as root or w/ sudo) ./arm64_kbuild.bash [path-to-kernel-config]
#
# The script is configured to run make menuconfig using the kernel config given
# on the command line as default config (or using the stock arm64 defconfig, if
# no config is supplied). If you do edits at the menu, remember to save the
# config under the name .config before exiting; compilation will then start
# automatically. The stdout logs are long, use tee to capture them in a file.
#
# It is possible to use both the GNU toolchain and the Clang/LLVM toolchain.
# (It is assumed that the appropriate one is downloaded and installed, see
# below.) Apart from the toolchain, a standard build environment is required
# along with a few standard Linux commands (see check_prereqs below).
#
# For detailed changes relative to previous version (v0.13), see CHANGELOG.md
# (In summary, a bunch of bugs were fixed, many frail constructions were made
# robust and the code was grouped into functions making it much more readable.)
#
# Inspiration taken from:
# https://www.kernel.org/doc/html/latest/index.html
# https://linux-kernel-labs.github.io/refs/heads/master/labs/arm_kernel_development.html
# https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/rebuild


set -Eeuo pipefail
shopt -s nullglob

# --------------------------- helpers and traps ------------------------------

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

log_info() { printf '[%s Info %s] %s\n' "$c_info" "$c_reset" "$*"; }
log_warn() { printf '[%s Warning %s] %s\n' "$c_warn" "$c_reset" "$*"; }
log_err()  { printf '[%s Error %s] %s\n' "$c_err" "$c_reset" "$*" >&2; }
log_ok()   { printf '[%s OK %s] %s\n' "$c_ok" "$c_reset" "$*"; }
banner()   { printf '\n--%s %s %s--\n' "$c_ok" "$*" "$c_reset"; }

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

# State variables (the work dirs are initialised below; the ${var:-} guards in
# cleanup() make the traps safe even if the script dies before that).
build_ok=false
arch_str=""
kconfig_file_full=""
kern_tree=""
patch_files=()
failed_patches=()

on_error() {
    local rc=$?
    log_err "Command failed at line $1 (exit code $rc)."
    exit "$rc"
}

cleanup() {
    local rc=$?
    if $build_ok; then
        if [[ ${docleanup_after:-no} == "yes" ]]; then
            rm -rf "${tmpfile_dir:-}" "${rootfs_dir:-}" "${kern_src_dir:-}" \
                "${kern_out_dir:-}" 2>/dev/null || true
            log_ok "Temporary files and directories cleaned up."
        fi
        return 0
    fi
    local existing=() d
    for d in "${tmpfile_dir:-}" "${rootfs_dir:-}" "${kern_src_dir:-}" \
             "${kern_out_dir:-}"; do
        if [[ -n $d && -e $d ]]; then
            existing+=("$d")
        fi
    done
    if [[ ${#existing[@]} -gt 0 ]]; then
        log_warn "Build did not complete (exit $rc). Work dirs kept for inspection: ${existing[*]}"
    else
        log_err "Build did not complete (exit $rc)."
    fi
    return 0
}

trap 'on_error $LINENO' ERR
trap cleanup EXIT

# ------------------------------- parameters ---------------------------------

# Q: Which parameters do I (really) need to edit?
# A: Well, as always, "it depends". (The ones you most often need to change
# (if you (re)compile one kernel series often) are collected near the top.)

# Kernel version number for the kernel, in x.y.z format.
# Note: for an x.y kernel (e.g. 6.7) you must add (pad with) a zero to make
# it x.y.z format (e.g. 6.7.0).
kern_ver_num=7.2.11

# Name for compiled (output) kernel and packages (tarballs).
# Note: in the config file you should have these two settings
# CONFIG_LOCALVERSION=""
# # CONFIG_LOCALVERSION_AUTO is not set
kern_tag_str="-koop-3pole"
kern_out_str="${kern_ver_num}${kern_tag_str}"

# Alternatively, a locally provided kernel source tarball can be used.
# Such a tarball must have the same file name format as the tarballs from
# kernel.org and be placed in the dir pointed to by loc_kern_tarball_dir (a
# dir path relative to the working dir, see $kern_loc_src_dir below).
use_loc_kern_src=no # {yes,no}
#loc_kern_tarball_dir=mainline_kern

# Path to local patch dir (see $patch_src_dir below), relative to the working
# dir. If the directory does not exist or contains no *.patch files, no
# patches are applied.
#loc_patch_dir=patches/tripole/aarch64/6.12
#loc_patch_dir=patches/manjaro/6.16.0-1
loc_patch_dir=dummy_dir

# List of names for SoC vendor for which you want to create a dtb package
# (tarball). (All of these SoCs must be enabled in the kernel config.)
socdtbs_list=("amlogic" "allwinner" "rockchip")
#socdtbs_list=("rockchip")

# If you want legacy u-boot images of kernel and initramfs (uImage, uInitrd)
# to be made, say yes here (see also kernel load address and starting point
# below).
make_uboot_imgs=yes

# If you want to enable clang LTO (LTO_CLANG_THIN) for kernels >= 5.12 when
# using the Clang/LLVM toolchain, say yes here. With the GNU toolchain LTO is
# not applicable and the config is left untouched.
enable_lto=no # {yes,no}

# These two parameters define the kernel memory load address and starting
# point, respectively, for u-boot. They are used below to create uImage from
# Image. The values must be adapted to the box/SoC. For e.g. some Amlogic
# s922x SoC (GT King pro, Ugoos AM6) both values are 0x1080000, see
# https://linux-meson.com/howto.html and also
# https://www.kernel.org/doc/html/latest/arm64/booting.html
# Note: When booting a mainline (kernel.org) kernel using uImage there can be
# a warning in dmesg that the kernel is misaligned at boot (with these values).
k_load_addr=0x1080000
k_entry_addr=0x1080000

# Compilation parameters, see e.g.
# https://www.kernel.org/doc/html/latest/index.html
# https://www.kernel.org/doc/html/latest/kbuild/llvm.html

targ_arch="arm64"

# A few examples of working parameter settings (use one, comment out the other).
# The options are kept in an array so that they are passed to make verbatim
# (a space in e.g. kern_tag_str can no longer break the LOCALVERSION option).

# For an Ubuntu aarch64 host with GNU toolchain from the Ubuntu repos:
# kern_make_opts=(ARCH="$targ_arch" LOCALVERSION="$kern_tag_str")

# For an Ubuntu x86_64 host with GNU toolchain from the Ubuntu repos:
kern_make_opts=(ARCH="$targ_arch" CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION="$kern_tag_str")

# For an Ubuntu x86_64 host with external ARM GNU toolchain from
# https://developer.arm.com :
# toolchain_dir=/opt/toolchain
# gnu_arm_tchain_name=arm-gnu-toolchain-12.3.rel1-x86_64-aarch64-none-linux-gnu
# export PATH="${toolchain_dir}/${gnu_arm_tchain_name}/bin:${PATH}"
# kern_make_opts=(ARCH="$targ_arch" \
#     CROSS_COMPILE="${toolchain_dir}/${gnu_arm_tchain_name}/bin/aarch64-none-linux-gnu-" \
#     LOCALVERSION="$kern_tag_str")

# For an Ubuntu x86_64 host with external clang+llvm toolchain from
# https://github.com/llvm/llvm-project/releases :
# clangllvm_tchain_dir=/usr/local/toolchain/clang+llvm-13.0.0-x86_64-linux-gnu-ubuntu-20.04
# export PATH="${clangllvm_tchain_dir}/bin:${PATH}"
# kern_make_opts=(ARCH="$targ_arch" CC="${clangllvm_tchain_dir}/bin/clang" \
#     LD="${clangllvm_tchain_dir}/bin/ld.lld" LLVM=1 LLVM_IAS=1 LOCALVERSION="$kern_tag_str")

# Number of threads for kernel compilation (set to 0 for automatic selection).
compile_ncores=0

# Official Ubuntu rootfs tarball (used to make the initramfs).
# (Pick a release that "is close" to what you intend to run the kernel on.)
distro_release=noble # {noble,jammy} (small caps)
distro_urlbase="https://cdimage.ubuntu.com/ubuntu-base"
# Note: at cdimage.ubuntu.com the LTS releases live under
# /releases/<release>/release/ ; the file name has to be updated when a new
# point release (e.g. 24.04.6) is published.

# Approximate max usage of kernel sources (unpacked), object files and rootfs
# (not including toolchain) w/o debugging symbols (grows slowly w/ versions).
# (Memory requirements are not large, 4G is sufficient.)
required_MiB=6000

# Do we want to clean up all temporary files and directories afterwards?
docleanup_after=yes # {yes,no}

# Working dir: all temporary and output files are placed here. By default the
# current working dir (i.e. where the script is invoked from); can be
# overridden with the WORK_DIR environment variable.
work_dir=${WORK_DIR:-$PWD}

# Location (dir) of temporary files (downloads).
tmpfile_dir=${work_dir}/temp_files

# Location of unpacked kernel source and the output files produced by the build.
kern_src_dir=${work_dir}/kern_src
kern_out_dir=${work_dir}/kern_out

# Location of directory for locally provided kernel (optional) source tarball.
kern_loc_src_dir=${work_dir}/${loc_kern_tarball_dir:-}

# Location of local patches to be applied.
patch_src_dir=${work_dir}/${loc_patch_dir:-}

# Temporary mount point (dir) used during initramfs creation.
rootfs_dir=${work_dir}/rootfs_tmp

# Name of the calling command (used in the README).
calling_cmd_name=${0##*/}

# Canonical (absolute) path of the patch dir. (realpath -m canonicalises the
# path without requiring any component to exist, unlike readlink -f which
# fails when intermediate components are missing; a missing dir is handled in
# main.)
patch_src_dir_fpath=$(realpath -m -- "$patch_src_dir") ||
    die "Cannot resolve the patch dir path '$patch_src_dir'."

# --------------------------- here-docs (chroot) -----------------------------

# The script run inside the Ubuntu rootfs chroot (see build_initramfs).
# The here-doc is QUOTED ('EOF'): values are NOT baked in at definition time;
# instead the needed variables are passed as environment variables when
# systemd-nspawn is invoked with --setenv statments.
ubuntu_custom_inst=$(cat <<'EOF'
#!/bin/bash
set -euo pipefail

: "${KERN_OUT_STR:?KERN_OUT_STR not set}"
: "${MAKE_UBOOT_IMGS:?MAKE_UBOOT_IMGS not set}"
: "${K_LOAD_ADDR:?K_LOAD_ADDR not set}"
: "${K_ENTRY_ADDR:?K_ENTRY_ADDR not set}"

echo "Installing packages ..."
apt-get update
apt-get -y install apt-utils
DEBIAN_FRONTEND=noninteractive apt-get -y install \
    initramfs-tools linux-firmware u-boot-tools

# To be able to boot kernels with old (e.g. vendor/resident) u-boot we use gzip.
sed -i 's/COMPRESS=zstd/COMPRESS=gzip/g' /etc/initramfs-tools/initramfs.conf

echo "Creating a new initramfs for inclusion in boot package ..."
update-initramfs -k "$KERN_OUT_STR" -c
echo " Done."

if [[ "$MAKE_UBOOT_IMGS" == "yes" ]]; then
    echo "Making u-boot tagged versions of kernel and initramfs."
    # On ARM64 the name vmlinuz is often used also for uncompressed kernels.
    mkimage -n "uImage" -A arm64 -O linux -T kernel -C none \
        -a "$K_LOAD_ADDR" -e "$K_ENTRY_ADDR" \
        -d "/boot/vmlinuz-${KERN_OUT_STR}" "/boot/uImage-${KERN_OUT_STR}"
    mkimage -A arm64 -O linux -T ramdisk -C gzip \
        -d "/boot/initrd.img-${KERN_OUT_STR}" "/boot/uInitrd-${KERN_OUT_STR}"
    echo " Done."
fi
EOF
)

# --------------------------- preparations/checks ----------------------------

validate_params() {
    [[ $kern_ver_num =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        die "kern_ver_num '$kern_ver_num' is not in x.y.z format."
    case $kern_ver_num in
        5.*|6.*|7.*) ;;
        *) die "The kernel series ${kern_ver_num%%.*}.x.y is not supported (5.x-7.x supported), exiting." ;;
    esac
    case $use_loc_kern_src in yes|no) ;; *) die "use_loc_kern_src must be yes or no." ;; esac
    case $make_uboot_imgs in yes|no) ;; *) die "make_uboot_imgs must be yes or no." ;; esac
    case $docleanup_after in yes|no) ;; *) die "docleanup_after must be yes or no." ;; esac
    case $enable_lto in yes|no) ;; *) die "enable_lto must be yes or no." ;; esac
    [[ $compile_ncores =~ ^[0-9]+$ ]] || die "compile_ncores must be a non-negative integer."
    [[ ${#socdtbs_list[@]} -gt 0 ]] || die "socdtbs_list is empty."
    [[ ${#kern_make_opts[@]} -gt 0 ]] || die "kern_make_opts is empty (uncomment one of the toolchain settings)."
    if [[ $use_loc_kern_src == "yes" ]]; then
        [[ -n ${loc_kern_tarball_dir:-} ]] ||
            die "use_loc_kern_src=yes but loc_kern_tarball_dir is not set."
        [[ -d $kern_loc_src_dir ]] ||
            die "loc_kern_tarball_dir '$kern_loc_src_dir' does not exist."
    fi
    # Official Ubuntu rootfs tarball (used to make the initramfs).
    case $distro_release in
        "noble")
            distro_buildfile=ubuntu-base-24.04.5-base-arm64.tar.gz
            distro_buildurl="${distro_urlbase}/releases/noble/release/${distro_buildfile}"
            ;;
        "jammy")
            distro_buildfile=ubuntu-base-22.04-base-arm64.tar.gz
            distro_buildurl="${distro_urlbase}/releases/jammy/release/${distro_buildfile}"
            ;;
        *)
            die "The distro release '$distro_release' is unknown (supported: noble, jammy), exiting."
            ;;
    esac
}

# Kernel series (v5.x/v6.x/v7.x) and the kernel.org source tarball name/URL.
# (It is assumed that the kernel source is compressed with xz and that the
# compressed kernel source tarball name is of the form linux-x.y.z.tar.xz
# (or linux-x.y.tar.xz for x.y.0 releases).)
derive_kernel_vars() {
    kern_series_major=${kern_ver_num%%.*}
    kern_series="v${kern_series_major}.x"
    kern_url_base="https://cdn.kernel.org/pub/linux/kernel/${kern_series}"
    # Strip a trailing .0 in the version (kernel.org names such tarballs x.y).
    kern_txz_name="linux-${kern_ver_num%.0}.tar.xz"
    kern_txz_url="${kern_url_base}/${kern_txz_name}"
}

check_prereqs() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root (use sudo), exiting."
    arch_str=$(uname -m)
    case $arch_str in
        aarch64|x86_64) ;;
        *) die "The architecture '$arch_str' is not one of x86_64 or aarch64, exiting." ;;
    esac
    local reqd_cmdlist=( "systemd-nspawn" "make" "tar" "gzip" "wget" "patch" "sha256sum" "nproc" "realpath" )
    if [[ $arch_str != "aarch64" ]]; then
        reqd_cmdlist+=( "qemu-aarch64-static" )
    fi
    local missing=() chk_cmd
    for chk_cmd in "${reqd_cmdlist[@]}"; do
        if ! command -v "$chk_cmd" >/dev/null; then
            missing+=("$chk_cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "The required commands are missing: ${missing[*]}"
    fi
    if [[ $arch_str != "aarch64" && ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
        log_warn "No binfmt_misc entry for qemu-aarch64 found; systemd-nspawn will not be able to exec the arm64 rootfs. Install/enable qemu-user-static."
    fi
}

prepare_workdirs() {
    log_info "Making directories for temporary and output files ..."
    # Wipe and recreate so that a rerun can never mix stale files into the
    # new package.
    rm -rf "$tmpfile_dir" "$rootfs_dir" "$kern_src_dir" "$kern_out_dir"
    mkdir -p "$tmpfile_dir" "$rootfs_dir" "$kern_src_dir" \
        "${kern_out_dir}/headers" "${kern_out_dir}/modules" "${kern_out_dir}/${kern_out_str}"
    log_ok "Done."
}

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

# -------------------------------- downloads ---------------------------------

download_rootfs() {
    log_info "Downloading the root (base) file system tarball ..."
    log_info " $distro_buildurl"
    wget -P "$tmpfile_dir" -nv "$distro_buildurl" ||
        die "Unable to download the rootfs tarball from $distro_buildurl"
    log_ok "Done."
}

extract_rootfs() {
    log_info "Unpacking the root (base) file system tarball ..."
    tar -xf "${tmpfile_dir}/${distro_buildfile}" -C "$rootfs_dir" ||
        die "Failed to unpack the rootfs tarball."
    log_ok "Done."
}

prepare_kernel_src() {
    if [[ $use_loc_kern_src != "yes" ]]; then
        log_info "Downloading the kernel source tarball $kern_txz_name"
        log_info " from $kern_txz_url"
        log_info " to $tmpfile_dir"
        wget -P "$tmpfile_dir" -nv "$kern_txz_url" ||
            die "Unable to download the kernel source tarball from $kern_txz_url"
    else
        log_info "Copying locally provided kernel source tarball $kern_txz_name"
        log_info " from $kern_loc_src_dir"
        log_info " to $tmpfile_dir"
        cp -v "${kern_loc_src_dir}/${kern_txz_name}" "$tmpfile_dir" ||
            die "Unable to find the local kernel source tarball in $kern_loc_src_dir"
    fi
    log_info "Unpacking the kernel source tarball ..."
    tar -xf "${tmpfile_dir}/${kern_txz_name}" -C "$kern_src_dir" ||
        die "Failed to unpack the kernel source tarball."
    # There must be exactly one linux-* dir after the extraction (the workdir
    # was wiped in prepare_workdirs, so a multi-match would mean a broken
    # tarball).
    local dirs=( "$kern_src_dir"/linux-* )
    [[ ${#dirs[@]} -eq 1 ]] ||
        die "Expected exactly one linux-* directory in $kern_src_dir after extraction, found ${#dirs[@]}."
    local want="$kern_src_dir/linux-$kern_ver_num"
    if [[ ${dirs[0]} != "$want" ]]; then
        # Handle the case with kernels with numbers x.y only (instead of x.y.z).
        log_info "Renaming ${dirs[0]##*/} -> linux-$kern_ver_num"
        mv -v "${dirs[0]}" "$want" || die "Rename of the kernel source dir failed."
    fi
    kern_tree="$want"
    cd "$kern_tree" || die "Cannot cd into $kern_tree."
    log_ok "Kernel source ready: $kern_tree"
}

# ----------------------------------- timer ----------------------------------

run_time () {
local epoch_secs_now=$(date +"%s")
case "$#" in
    "1" ) # $1 is a dummy argument.
        local result=$epoch_secs_now
    ;;
    "2" )
        local run_time_secs=$(($epoch_secs_now -$2))
        local result=$(date -d@$run_time_secs -u +"%H:%M:%S")
    ;;
    * )
        echo "Error in function run_time(), exiting."
        exit 1
    ;;
esac
echo $result
}

# ---------------------------------- patches ---------------------------------

apply_patches() {
    if [[ ${#patch_files[@]} -eq 0 ]]; then
        log_info "No patch files found in $patch_src_dir_fpath; skipping."
        return 0
    fi
    local p rc
    for p in "${patch_files[@]}"; do
        log_info "Processing patch file ${p##*/}"
        if patch -N -p1 < "$p"; then
            log_ok "  ${p##*/} applied cleanly."
        else
            rc=$?
            log_warn "  ${p##*/} was NOT applied cleanly (exit $rc)!"
            failed_patches+=("$p")
        fi
    done
    if [[ ${#failed_patches[@]} -gt 0 ]]; then
        log_info "Summary of failed patch files:"
        local f
        for f in "${failed_patches[@]}"; do
            log_warn "  $f"
        done
        if confirm "Do you want to continue despite the failed patches? [N,y] "; then
            log_warn "Continuing despite failed patches, as you wish."
        else
            die "Aborting due to failed patches."
        fi
    fi
}

# ------------------------------ configuration -------------------------------

configure_kernel() {
    log_info "Running make mrproper ..."
    make "${kern_make_opts[@]}" mrproper || die "make mrproper failed."
    local conf_method=olddefconfig
    if [[ -n $kconfig_file_full ]] &&
        confirm "Do you want to edit (via menuconfig) the supplied config file
 $kconfig_file_full ? [N,y] "; then
        conf_method=menuconfig
    fi
    # KCONFIG_DEFCONFIG_LIST is only passed to make when the config file
    # exists: passing it empty (or with a missing file) would suppress the
    # kernel's own fallback list of default configs and make the config step
    # fail (see the review of v0.13).
    local kconfig_mkargs=()
    if [[ -n $kconfig_file_full ]]; then
        kconfig_mkargs=( KCONFIG_DEFCONFIG_LIST="$kconfig_file_full" )
    fi
    log_info "Preparing the kernel config (method: $conf_method) ..."
    make "${kconfig_mkargs[@]}" "${kern_make_opts[@]}" "$conf_method" ||
        die "Kernel configuration ($conf_method) failed."

    # For kernels 5.12 and above we enable clang LTO (it can offer some
    # advantages), but only when the Clang/LLVM toolchain is actually in use
    # (with the GNU toolchain LTO_CLANG_THIN depends on CC_IS_CLANG and would
    # be silently dropped at the next kconfig run).
    # https://www.phoronix.com/review/clang-lto-kernel
    local ver_x=${kern_ver_num%%.*}
    local ver_y=${kern_ver_num#*.}
    ver_y=${ver_y%%.*}
    local lto_ok=false
    if (( ver_x > 5 )) || { (( ver_x == 5 )) && (( ver_y >= 12 )); }; then
        lto_ok=true
    fi
    local use_llvm=false opt
    for opt in "${kern_make_opts[@]}"; do
        if [[ $opt == LLVM=1 || $opt == CC=* ]]; then
            use_llvm=true
        fi
    done
    if [[ $enable_lto == "yes" ]]; then
        if $use_llvm && $lto_ok; then
            scripts/config -e LTO_CLANG_THIN
            log_ok "LTO_CLANG_THIN enabled (clang toolchain, kernel ${ver_x}.${ver_y}.z)."
        else
            log_warn "enable_lto=yes but LTO is not applicable (clang in use: $use_llvm; kernel >= 5.12: $lto_ok); LTO left as in the config."
        fi
    else
        scripts/config -d LTO_CLANG_THIN
    fi
}

# ---------------------------------- build -----------------------------------

build_kernel() {
    local ncores
    if [[ $compile_ncores -eq 0 ]]; then
        ncores=$(nproc)
        if (( ncores <= 2 )); then
            compile_ncores=1
        else
            compile_ncores=$(( ncores - 1 ))
        fi
        log_info "Number of threads for compilation automagically set to: $compile_ncores"
    fi
    log_info "Compilation options: ${kern_make_opts[*]}"
    log_info "Compiling kernel, modules and dtbs ..."
    make "${kern_make_opts[@]}" Image modules dtbs -j"$compile_ncores" ||
        die "Kernel compilation FAILED."
    log_ok "Done compiling kernel, modules and dtbs."
    log_info "Installing modules in local dir ..."
    make "${kern_make_opts[@]}" INSTALL_MOD_PATH="${kern_out_dir}/modules" modules_install ||
        die "modules_install FAILED."
    log_ok "Done installing modules in local dir."
}

# --------------------------------- packaging --------------------------------

package_modules() {
    local modlib="${kern_out_dir}/modules/lib/modules"
    [[ -d "${modlib}/${kern_out_str}" ]] ||
        die "Module directory ${modlib}/${kern_out_str} is missing; was modules_install run?"
    log_info "Packing modules ..."
    # --exclude=build/--exclude=source: do not pack the (dangling) symlinks
    # that modules_install creates into the source tree.
    tar --exclude=build --exclude=source \
        -czf "${kern_out_dir}/${kern_out_str}/modules-${kern_out_str}.tar.gz" \
        -C "$modlib" "$kern_out_str" ||
        die "Packing the modules tarball failed."
    log_ok "Done."
}

package_headers() {
    # The code below for extracting the header files is based on the function
    # deploy_kernel_headers() in the file scripts/package/builddeb (by
    # W. Akkerman) in the Linux kernel source tree.
    log_info "Extracting header files ..."
    local hdr_list_file="${tmpfile_dir}/hdr_file_list.txt"
    local obj_list_file="${tmpfile_dir}/obj_file_list.txt"

    # Make header source file list.
    : > "$hdr_list_file"
    find . arch/"$targ_arch" -maxdepth 1 -name 'Makefile*' >> "$hdr_list_file"
    find include scripts -type f -o -type l >> "$hdr_list_file"
    find arch/"$targ_arch" -name Kbuild.platforms -o -name Platform >> "$hdr_list_file"
    # Unquoted command substitution on purpose: the inner find may print
    # several directories.
    # shellcheck disable=SC2046
    find $(find arch/"$targ_arch" -name include -o -name scripts -type d) -type f >> "$hdr_list_file"

    # Make header object file list.
    : > "$obj_list_file"
    find arch/"$targ_arch"/include Module.symvers include scripts -type f >> "$obj_list_file"
    if grep -q "CONFIG_OBJTOOL=y" include/config/auto.conf; then
        echo "tools/objtool/objtool" >> "$obj_list_file"
    fi
    if grep -q "CONFIG_GCC_PLUGINS=y" include/config/auto.conf; then
        find scripts/gcc-plugins -name '*.so' >> "$obj_list_file"
    fi

    # Use tar to conveniently copy the files in the lists (w/ relative paths).
    tar -cf - -T "$hdr_list_file" | tar -xf - -C "${kern_out_dir}/headers"
    tar -cf - -T "$obj_list_file" | tar -xf - -C "${kern_out_dir}/headers"

    # Copy .config manually to be where it's expected to be.
    cp -f .config "${kern_out_dir}/headers/.config"

    log_info "Packing headers ..."
    # Note: tar '.' (not '*') so that dot files such as .config are included.
    tar -czf "${kern_out_dir}/${kern_out_str}/headers-${kern_out_str}.tar.gz" \
        -C "${kern_out_dir}/headers" . ||
        die "Packing the headers tarball failed."
    log_ok "Done."
}

package_dtbs() {
    local soc dtsdir list_file n
    for soc in "${socdtbs_list[@]}"; do
        dtsdir="arch/${targ_arch}/boot/dts/${soc}"
        if [[ ! -d $dtsdir ]]; then
            log_warn "No dts directory '$dtsdir' in the kernel source tree; skipping '$soc'."
            continue
        fi
        # In older kernels the file dtbs-list is not auto generated so we make one.
        list_file="${tmpfile_dir}/${soc}_dtbs-list"
        ( cd "$dtsdir" && find . -type f -name '*.dtb' > "$list_file" )
        n=$(wc -l < "$list_file")
        if [[ $n -eq 0 ]]; then
            log_warn "Unable to locate any dtbs for '${soc}' in kernel source tree, skipping."
            continue
        fi
        log_info "Found $n dtbs for '${soc}', packing ..."
        tar -czf "${kern_out_dir}/${kern_out_str}/dtb-${soc}-${kern_out_str}.tar.gz" \
            -C "$dtsdir" -T "$list_file" ||
            die "Packing the dtb tarball for '${soc}' failed."
        log_ok "Done."
    done
}

stage_rootfs() {
    log_info "Copying over kernel image and config to rootfs ..."
    [[ -f System.map ]] || die "System.map not found in $kern_tree; the build seems incomplete."
    [[ -f arch/arm64/boot/Image ]] || die "arch/arm64/boot/Image not found in $kern_tree; the build seems incomplete."
    rm -rf "${rootfs_dir:?}/boot"
    mkdir -p "${rootfs_dir:?}/boot"
    cp System.map "${rootfs_dir}/boot/System.map-${kern_out_str}"
    cp .config "${rootfs_dir}/boot/config-${kern_out_str}"
    # On ARM64 it is common to use the name vmlinuz also for uncompressed kernels.
    cp arch/arm64/boot/Image "${rootfs_dir}/boot/vmlinuz-${kern_out_str}"
    log_ok "Done."
    log_info "Copying over modules to rootfs ..."
    # On Ubuntu (and thus in rootfs) /lib is a symlink to /usr/lib
    mkdir -p "${rootfs_dir}/lib/modules"
    cp -r "${kern_out_dir}/modules/lib/modules/${kern_out_str}" "${rootfs_dir}/lib/modules/" ||
        die "Copying the modules to the rootfs failed."
    log_ok "Done."
}

build_initramfs() {
    log_info "Preparing for chroot jail ..."
    printf '%s\n' "$ubuntu_custom_inst" > "${rootfs_dir}/root/ubuntu_custom_inst.bash"
    chmod 0755 "${rootfs_dir}/root/ubuntu_custom_inst.bash"
    log_ok "Done."
    if [[ $arch_str != "aarch64" ]]; then
        log_info "Installing local qemu-aarch64-static binary into the rootfs ..."
        cp "$(command -v qemu-aarch64-static)" "${rootfs_dir}/usr/bin/" ||
            die "Failed to copy qemu-aarch64-static into the rootfs."
        log_ok "Done."
    fi
    log_info "Entering chroot jail. Installing some pkgs., running some scripts ..."
    # systemd-nspawn does not inherit the caller's environment so the
    # variables for the chroot script are passed as environment variables here.
        systemd-nspawn \
        --setenv KERN_OUT_STR="$kern_out_str" \
        --setenv MAKE_UBOOT_IMGS="$make_uboot_imgs" \
        --setenv K_LOAD_ADDR="$k_load_addr" \
        --setenv K_ENTRY_ADDR="$k_entry_addr" \
        -q --resolv-conf=copy-host --timezone=off -D "$rootfs_dir" \
        /root/ubuntu_custom_inst.bash ||
        die "The chroot script failed (see the output above)."
    rm -f "${rootfs_dir}/root/ubuntu_custom_inst.bash"
    if [[ $arch_str != "aarch64" ]]; then
        log_info "Removing local qemu-aarch64-static binary from the rootfs ..."
        rm -f "${rootfs_dir}/usr/bin/qemu-aarch64-static"
        log_ok "Done."
    fi
    log_ok "Done in chroot jail."
}

pack_boot() {
    log_info "Packing the files in boot/ (e.g. kernel and initramfs) ..."
    tar -czf "${kern_out_dir}/${kern_out_str}/boot-${kern_out_str}.tar.gz" \
        -C "${rootfs_dir}/boot" . ||
        die "Packing the boot tarball failed."
    log_ok "Done."
}

pack_patches() {
    if [[ ${#patch_files[@]} -eq 0 ]]; then
        return 0
    fi
    log_info "Packing the applied patch files ..."
    tar -czf "${kern_out_dir}/${kern_out_str}/patches-${kern_out_str}.tar.gz" \
        -C "$patch_src_dir_fpath" "${patch_files[@]##*/}" ||
        die "Packing the patches tarball failed."
    log_ok "Done."
}

make_checksums() {
    log_info "Computing sha256sums for all the generated (gzipped) tarballs ..."
    (
        cd "${kern_out_dir}/${kern_out_str}"
        files=( *.tar.gz )
        [[ ${#files[@]} -gt 0 ]] || exit 1
        sha256sum -- "${files[@]}" > "sha256sums-${kern_out_str}"
    ) || die "Computing the sha256sums failed."
    log_ok "Done."
}

add_readme() {
    log_info "Adding README file ..."
    cat > "${kern_out_dir}/${kern_out_str}/README_kernels.txt" <<EOF
The files in the tar.gz packages here are produced by the script
$calling_cmd_name
from https://gitlab.com/tripole-inc/bootdisk where also more info about this
kernel package can be found.

Notes:
The vmlinuz file is an uncompressed ARM64 kernel (i.e. an Image).

The uImage is made with load address and entry point set as
load_address=$k_load_addr
entry_point=$k_entry_addr

The initrd.img is based on the official Ubuntu rootfs from
the release $distro_release
EOF
    log_ok "Done."
}

make_final_package() {
    log_info "Packing up the final tarball with everything in it ..."
    tar -cf "${kern_out_dir}/${kern_out_str}.tar" -C "$kern_out_dir" "$kern_out_str" ||
        die "Packing the final tarball failed."
    local dest="${work_dir}/${kern_out_str}.tar"
    # Back up (instead of silently clobbering) an old package from a previous
    # build with the same name.
    if [[ -f $dest ]]; then
        log_warn "Existing package $dest found; moving it to ${dest}.bak"
        mv -v "$dest" "${dest}.bak" || die "Could not back up the old package."
    fi
    mv -v "${kern_out_dir}/${kern_out_str}.tar" "$dest" ||
        die "Could not move the final package to $dest."
    log_info "The final package is $dest"
}

# ----------------------------------- main -----------------------------------

main() {
    [[ $# -le 1 ]] || die "Usage: $calling_cmd_name [path-to-kernel-config]"

    if [[ $# -eq 1 ]]; then
        kconfig_file_full=$(readlink -f -- "$1") || die "Cannot resolve the config path '$1'."
        [[ -f $kconfig_file_full ]] || die "The suggested kernel config file '$kconfig_file_full' does not exist!"
        log_info "Kernel config file: $kconfig_file_full"
    else
        log_info "No kernel config supplied; the stock arm64 defconfig will be used."
    fi

    validate_params
    derive_kernel_vars
    check_prereqs

    banner "Making kernel package $kern_out_str"

    # Collect the patch files (nullglob: a missing/empty dir yields an empty
    # array).
    patch_files=()
    if [[ -d $patch_src_dir_fpath ]]; then
        patch_files=( "$patch_src_dir_fpath"/*.patch )
    fi
    if [[ ! -d $patch_src_dir_fpath ]]; then
        log_info "Patches directory '$patch_src_dir_fpath' does not exist; no patches will be applied."
    elif [[ ${#patch_files[@]} -eq 0 ]]; then
        log_info "Patches directory (empty): $patch_src_dir_fpath"
    else
        log_info "Patches directory: $patch_src_dir_fpath (${#patch_files[@]} patch file(s))"
    fi

    space_prompt
    prepare_workdirs

    download_rootfs
    extract_rootfs
    prepare_kernel_src
    apply_patches

    banner "Starting the compilation process"
    configure_kernel
    run_time_start=$(run_time "start") # We measure only the actual build.
    build_kernel

    package_modules
    package_headers
    package_dtbs
    stage_rootfs
    build_initramfs
    pack_boot
    pack_patches
    make_checksums
    add_readme
    make_final_package

    build_ok=true
    log_ok "Kernel package build complete!"
    tot_run_time=$(run_time "stop" $run_time_start)
    log_info "Run time (excl. src d/l, unpack and configuration) [h:m:s]: "$tot_run_time
}

main "$@"
