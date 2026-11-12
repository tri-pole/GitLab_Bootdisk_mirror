#!/bin/bash

# petitboot_build_wrapper.bash
# 26-11-06: v0.11, Tripole (added aarch64)
# 26-11-03: v0.1, Qwen
#
# Build the aarch64 or riscv64 Petitboot initramfs locally, for development
# and debugging. (Official builds run in the GitLab pipeline; .gitlab-ci.yml.)
#
# Usage: ./petitboot_build_wrapper.bash <arch>
#   where <arch> is one of aarch64 or riscv64
#
# The build runs in an ubuntu:24.04 (Noble) aarch64/riscv64 docker container:
#   - on an x86_64 host: aarch64/riscv64 is emulated via qemu-user (binfmt),
#     set up automatically below (expect ~30-60 min build time);
#   - on a aarch64/riscv64 host (e.g. a VF2): the container runs natively
#     (no binfmt needed) - but note that even native riscv64 builds are slow.
# Noble (24.04) is used deliberately: from Resolute (26.04) on, Ubuntu's
# riscv64 port mandates the RVA23S64 profile, which pre-RVA23 hardware
# (e.g. the Vision Five 2) does not implement.
#
# Prerequisites: docker installed, user in the docker group, sudo (for chown).
# Run from anywhere; the script cd's to its own directory (typ. the repo root).
#
# Output: result_{aarch64,riscv64}_<timestamp>/ in the repo root (the initrd and
# RELEASE_NOTES_<tag>.md), build log in build_{aarch64,riscv64}_<timestamp>.log.

set -u

i_msg="[\033[94m Info \033[0m]"
ok_msg="[\033[92m OK \033[0m]"
e_msg="[\033[91m Error \033[0m]"

this_dir=$(dirname "$(readlink -f "$0")")
cd "$this_dir" || exit 1

# --- Argument check -----------------------------------------------------------

if [[ "$#" -ne 1 || ("$1" != "aarch64" && "$1" != "riscv64") ]]; then
   echo -e ${e_msg}" Usage: $0 <arch>"
   echo -e ${e_msg}"   where <arch> is one of aarch64 or riscv64"
   exit 1
else
   build_arch=$1
fi

# --- Prerequisite checks ------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    echo -e ${e_msg}" docker is not installed, exiting."
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo -e ${e_msg}" Cannot talk to the docker daemon (are you in the docker"
    echo -e ${e_msg}" group?), exiting."
    exit 1
fi

if [[ ! -f "petitboot_mkinitrd_${build_arch}.bash" || ! -f "petitboot_gen_relnotes.bash" ]]; then
    echo -e ${e_msg}" One of petitboot_mkinitrd_${build_arch}.bash or"
    echo -e ${e_msg}" petitboot_gen_relnotes.bash is missing, exiting."
    exit 1
fi

# ---- Ensure qemu-user/binfmt for aarch64/riscv64 (no-op if already regd.) ----
host_arch=$(uname -m)
if [[ "$host_arch" != "$build_arch" ]]; then
    echo -e ${i_msg}" Host is $host_arch; setting up qemu-user emulation for $build_arch ..."
    if ! docker run --rm --privileged tonistiigi/binfmt:latest --install ${build_arch}; then
        echo -e ${e_msg}" Failed to set up binfmt for ${build_arch}, exiting."
        exit 1
    fi
else
    echo -e ${i_msg}" Host is ${host_arch}; the container will run natively."
fi

# --- Run the build -------------------------------------------------------------
log_file=build_${build_arch}_$(date -u '+%y%m%dT%H%M')Z.log
echo -e ${i_msg}" Running the build; this takes a while. Log: $log_file"
case $build_arch in
    "aarch64")
	docker run --rm --platform linux/aarch64 -v "$this_dir":/mnt -w /mnt ubuntu:24.04 \
          bash -c '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y --no-install-recommends \
        autoconf automake bison build-essential ca-certificates cpio curl flex gawk gettext \
        git gperf libasprintf-dev libblkid-dev libdevmapper-dev libdw-dev libelf-dev \
        libgd-tools libgettextpo-dev libgpgme-dev liblzma-dev libncurses-dev \
        libssl-dev libtool libudev-dev pkg-config sudo tree u-boot-tools \
        wget zstd file gpg
        ./petitboot_mkinitrd_aarch64.bash </dev/null
        bash petitboot_gen_relnotes.bash "$(ls -d result_aarch64_*/ | sort -r | head -1)"
        '  2>&1 | tee "$log_file"
        rc=${PIPESTATUS[0]}
	;;
    "riscv64")
        docker run --rm --platform linux/riscv64 -v "$this_dir":/mnt -w /mnt ubuntu:24.04 \
          bash -c '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends \
        autoconf automake bison build-essential ca-certificates cpio flex gawk gettext git \
        gperf libasprintf-dev libblkid-dev libdevmapper-dev libdw-dev libelf-dev \
        libgd-tools libgettextpo-dev libgpgme-dev liblzma-dev libncurses-dev \
        libssl-dev libtool libudev-dev pkg-config sudo tree wget zstd file gpg
        ./petitboot_mkinitrd_riscv64.bash </dev/null
        bash petitboot_gen_relnotes.bash "$(ls -d result_riscv64_*/ | sort -r | head -1)"
        ' 2>&1 | tee "$log_file"
        rc=${PIPESTATUS[0]}
	;;
esac
if [[ $rc -ne 0 ]]; then
    echo -e ${e_msg}" Build failed (rc=$rc); see $log_file, exiting."
    exit 1
fi
echo -e ${ok_msg}" Build finished; see $log_file and result_${build_arch}_* in $this_dir"
