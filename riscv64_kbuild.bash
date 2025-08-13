#!/bin/bash

# riscv64_kbuild.bash
# 24-11-19: v0.1
# Author: Tripole

# Script to compile the Linux kernel for RISCV64 and package the result in a
# tarball. The script must be executed on an Ubuntu/Debian type machine,
# either natively on RISCV64 or virtualized (using qemu-riscv64-static) on
# x86_64/amd64. The script is an adaption of my script arm64_kbuild.bash.
# The output from the sript is a set of tarballs containing (1) a kernel image
# file (of type Image but renamed to vmlinux), (2) an initramfs (initrd.img,
# gzipped, based on an Ubuntu rootfs), (3) config and System.map files and dtb
# files for the SoCs specified, and (4) header files.

# Usage: (as root or using sudo) ./arm64_kbuild.bash [path-to-kernel-config]

# The script is configured to run make menuconfig using the kernel config given
# on the command line as default config (or using a defconfig, if no config is
# supplied). Remember to save the config under the name .config before exiting;
# compilation will then start automatically.

# The script assumes that the GNU toolchain is used for the build so this must
# be installed (see below). Apart from the toolchain, a normal build
# environment is required along with a few standard Linux commands (see below).
# (A basic build environment is provided with the package build-essential but
# it is also required to have tools such as flex, bison, libncurses-dev (for
# menuconfig) and, if applicable, cross compiling tools such as
# gcc-riscv64-linux-gnu. The Linux kernel also requires (depending on config)
# things as libssl-dev.) The script moreover assumes that at least some
# modules are created (so not all built in.)

# The script has been tested on an x86_64 VM (running in qemu-system-x86_64)
# with Ubuntu 22.04.5 and "natively" on a RISCV64 VM (in qemu-system-riscv64)
# with Ubuntu 22.04.5. This script should be considered as a template or
# proof-of-concept, nothing more (so please fork it, adapt it, improve it).

# The script has been tested for building kernels 6.x.

# Inspiration taken from:
# https://www.kernel.org/doc/html/latest/index.html
# https://linux-kernel-labs.github.io/refs/heads/master/labs/arm_kernel_development.html
# https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/rebuild

# ------------------------------- parameters ---------------------------------

# Q: Which parameters do I (really) need to edit?
# A: Well, as always, "it depends". (The ones you most often need to change
# (if you (re)compile one kernel series often) are collected near the top.)

# It is assumed below that the kernel source is compressed with xz and that
# the compressed kernel source tarball name is of the form linux-x.y.z.tar.xz
# (or possibly linux-x.y.tar.xz).

# Kernel version number for kernel in x.y.z format.
# Note: Kernel version numbers here (in $kern_ver_num) must be in the format
# x.y.z so for an x.y kernel (e.g. 6.8) you must here add (pad with) a zero to
# make into x.y.z format (e.g. 6.8.0).
kern_ver_num=6.15.9

# Name for compiled (output) kernel and packages (tarballs).
# Note: In the config file you should have these two settings
# CONFIG_LOCALVERSION=""
# # CONFIG_LOCALVERSION_AUTO is not set
kern_tag_str="-riscv64-vf2-3pole"
kern_out_str=${kern_ver_num}${kern_tag_str}

# Alternatively, a locally provided kernel source tarball can be used.
# Such a tarball must have the same file name format as the tarballs from
# kernel.org and be placed in the dir pointed to by loc_kern_tarball_dir (a
# dir path relative to the working dir, see $kern_loc_src_dir below).
use_loc_kern_src=no # {yes,no}
#loc_kern_tarball_dir=VF2_kern

# Path to local patch dir (see $patch_src_dir below).
#loc_patch_dir=dummy_dir
loc_patch_dir=patches/tripole/riscv64/6.12

use_clang=yes # {yes,no} See below.

# List of names for SoC vendor for which you want to create a dtb tarball.
# (All of these SoCs must be enabled in the kernel config.)
#socdtbs_list=("allwinner" "canaan" "microchip" "sifive" "sophgo" "starfive" "thead")
socdtbs_list=("starfive")

kern_series_major=$(cut -b1 <<< $kern_ver_num)
case $kern_series_major in
    "5")
        kern_series="v5.x"
    ;;
    "6")
        kern_series="v6.x"
    ;;
    *)
    echo "The kernel series ${kern_series_major}.x.y is not supported, exiting."
    exit 1
esac

kern_url_base="https://cdn.kernel.org/pub/linux/kernel/${kern_series}"
kern_txz_name=linux-${kern_ver_num/%.0/}.tar.xz # Strip trailing .0 in version.
kern_txz_url=${kern_url_base}/${kern_txz_name}

# Official Ubuntu rootfs tarball (used to make the initramfs).
# (Pick a release that "is close" to what you intend to run the kernel on.)
distro_release=noble # {jammy,noble} (small caps)
distro_urlbase="https://cdimage.ubuntu.com/ubuntu-base"
# Note: At cdimage.ubuntu.com, different formats for URLs seem to be used.
case "$distro_release" in
    "noble")
        distro_buildfile=ubuntu-base-24.04.3-base-riscv64.tar.gz
        distro_urlbase=$distro_urlbase/releases
        distro_buildurl=${distro_urlbase}/noble/release/${distro_buildfile}
    ;;
    "jammy")
        distro_buildfile=ubuntu-base-22.04-base-riscv64.tar.gz
        distro_urlbase=$distro_urlbase/releases
        distro_buildurl=${distro_urlbase}/jammy/relaease/${distro_buildfile}
    ;;
    *)
        echo "The distro release $distro_release is unknown, exiting."
        exit 1
    ;;
esac

# Compilation parameters, see e.g.
# https://www.kernel.org/doc/html/latest/index.html
# https://www.kernel.org/doc/html/latest/kbuild/llvm.html

targ_arch="riscv"

if [[ "$use_clang" == "yes" ]]; then
    # For an Ubuntu Jammy x86_64 host with Clang toolchain from Ubuntu stable
    # repos (clang clang-tools llvm lld) the following settings can be used
    cc_str=/usr/bin/clang
    ld_str=/usr/bin/ld.lld
    kern_make_opts=" ARCH=$targ_arch CC=$cc_str LD=$ld_str LLVM=1 LLVM_IAS=1 LOCALVERSION=$kern_tag_str "
else
    # For an Ubuntu Jammy x86_64 host with GNU toolchain from Ubuntu stable
    # repos the following settings can be used (tested with kernel 6.x.y):
    kern_make_opts=" ARCH=$targ_arch CROSS_COMPILE=riscv64-linux-gnu- LOCALVERSION=$kern_tag_str "
fi

# Number of threads for kernel compilation (set to 0 for automatic selection).
compile_ncores=0

#-----------------------------------------------------------------------

# Some (but not all) commands used below to create the image.
reqd_cmdlist=("systemd-nspawn" "tar" "gzip" "wget")

reqd_cmdlist_virt=("qemu-riscv64-static")

# Location (dir) of temporary files (downloads) (for size, see below).w
work_dir=$PWD
tmpfile_dir=${work_dir}/temp_files

# Location of unpacked kernel source and the output files produced by the build.
kern_src_dir=${work_dir}/kern_src
kern_out_dir=${work_dir}/kern_out

# Location of directory for locally provided kernel (optional) source tarball.k
kern_loc_src_dir=${work_dir}/${loc_kern_tarball_dir}

# Location of local patches to be applied
patch_src_dir=${work_dir}/${loc_patch_dir}

# Approximate max usage of kernel sources (unpacked), object files and rootfs
# (not including toolchain) w/o debugging symbols (grows slowly w/ versions).
# (Memory requirements are not large, 4G is sufficient.)
required_MiB=6000

# Temporary mount points (dirs) used during image creation.
rootfs_dir=${work_dir}/rootfs_tmp

# Do we want to clean up all temporary files and directories afterwards?
docleanup_after=yes # {yes,no}

calling_cmd_name=${0##*/}

# Bling? Yes, we like.
i_msg="[\033[94m Info \033[0m]"
w_msg="[\033[93m Warning \033[0m]"
e_msg="[\033[91m Error \033[0m]"
k_msg="[\033[92m OK \033[0m]"

# ------------------------------- here-docs ----------------------------------

ubuntu_custom_inst=$(cat <<EOF
#!/bin/bash

apt-get update
apt-get -y install apt-utils
DEBIAN_FRONTEND=noninteractive apt-get -y install \
    initramfs-tools linux-firmware u-boot-tools

# To be able to boot kernels with old (e.g. vendor/resident) u-boot we use gzip.
sed -i 's/COMPRESS=zstd/COMPRESS=gzip/g' /etc/initramfs-tools/initramfs.conf

echo -e ${i_msg}" Creating a new initramfs for inclusion in boot package ..."
update-initramfs -k $kern_out_str -c
echo " Done."

EOF
)

README_kernels=$(cat <<EOF
The files in the tar.gz packages here are produced by the script
$calling_cmd_name
from https://gitlab.com/tripole-inc/bootdisk where also more info about this
kernel package can be found.

The initrd.imd is based on a daily build of the offical Ubuntu rootfs from
the release $distro_release
EOF
)

# --------------------------- preparations/checks ----------------------------

if [[ $EUID -ne 0 ]]; then
    echo -e ${e_msg}" This script must be run as root, exiting."
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

#----------------------------------- code -----------------------------------

echo -e "\n\033[92m -- Making kernel package $kern_out_str -- \033[0m"

if [[ $# -eq 1 ]] ; then
    kconfig_file=$1
    kconfig_file_full=$(readlink -f $kconfig_file)
    if [[ -f $kconfig_file_full ]] ; then
        echo "Kernel config file: $kconfig_file_full"
    else
        echo -e ${w_msg}" The suggested kernel config file $kconfig_file_full does not exist!"
    fi
fi

patch_src_dir_fpath=$(readlink -f $patch_src_dir)
patch_src_dir_exists=true
patch_src_dir_empty=false
if [[ -d $patch_src_dir_fpath ]]; then
    if [[ -z $(ls -A $patch_src_dir_fpath) ]]; then
        echo "Patches directory (empty): $patch_src_dir_fpath"
        patch_src_dir_empty=true
    else
        echo "Patches directory: $patch_src_dir_fpath"
    fi
else
    patch_src_dir_exists=false
fi

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

echo -e "\n\033[92m -- Starting the compilation process -- \033[0m\n"

echo -n -e ${i_msg}" Making a directory for temporary files..."
mkdir -p $tmpfile_dir
echo " Done."

echo -n -e ${i_msg}" Making a directory for the rootfs (for initramfs)..."
mkdir -p $rootfs_dir
echo " Done."

echo -e ${i_msg}" Downloading the root (base) file system tarball..."
wget -P $tmpfile_dir -nv $distro_buildurl
if [[ $? -ne 0 ]] ; then
    echo -e ${e_msg}" Unable to download the rootfs tarball, exiting."
    exit 1
fi
echo -e ${k_msg}" Done."

echo -n -e ${i_msg}" Unpacking the root (base) file system tarball..."
tar -xf ${tmpfile_dir}/${distro_buildfile} -C $rootfs_dir
sync
echo " Done."

echo -n -e ${i_msg}" Making a directory for the kernel source files..."
mkdir -p $kern_src_dir
echo " Done."

if [[ "$use_loc_kern_src" != "yes" ]]; then
    echo -e ${i_msg}" Downloading the kernel source tarball $kern_txz_name"
    echo " to $tmpfile_dir"
    wget -P $tmpfile_dir -nv $kern_txz_url
    if [[ $? -ne 0 ]]; then
        echo -e ${e_msg}" Unable to download the kernel source tarball, exiting."
        exit 1
    fi
else
    echo -e ${i_msg}" Copying locally provided kernel source tarball $kern_txz_name"
    echo " in $kern_loc_src_dir"
    echo " to $tmpfile_dir"
    cp ${kern_loc_src_dir}/${kern_txz_name} $tmpfile_dir
    if [[ $? -ne 0 ]]; then
        echo -e ${e_msg}" Unable to find the local kernel source tarball, exiting."
        exit 1
    fi
fi
echo -e ${k_msg}" Done."

echo -n -e ${i_msg}" Unpacking the kernel source tarball..."
tar -xf ${tmpfile_dir}/${kern_txz_name} -C $kern_src_dir
sync
# Handle the case with kernels with numbers x.y only (instead of x.y.z).
linux_in_pkg_name=$(readlink -nf ${kern_src_dir}/linux-*)
linux_our_name=$(readlink -nf ${kern_src_dir}/linux-${kern_ver_num})
if [[ $linux_in_pkg_name != $linux_our_name ]]; then
    mv -v $linux_in_pkg_name $linux_our_name
fi
echo " Done."

echo -n -e ${i_msg}" Setting up directories for kernel output files..."
mkdir -p ${kern_out_dir}/headers
mkdir -p ${kern_out_dir}/modules
mkdir -p ${kern_out_dir}/${kern_out_str}
echo " Done."

cd ${kern_src_dir}/linux-${kern_ver_num}

failed_patches_list=()
failed_patches_exist=false
if [[ "$patch_src_dir_exists" = true && "$patch_src_dir_empty" = false ]]; then
    echo -e ${i_msg}" Applying patches..."
        for my_patch_file in $(ls -A ${patch_src_dir_fpath}/*.patch) ; do
            echo -e ${i_msg}" Processing patch file "${my_patch_file##*/}
            patch -N -p1 < $my_patch_file
            if [[ $? -ne 0 ]]; then
                echo -e ${w_msg}" Patch was not applied cleanly!"
                failed_patches_exist=true
                echo "Adding file $my_patch_file to list of failed patches."
                failed_patches_list=("$failed_patches_list" "$my_patch_file")
                sleep 1
            fi
        done
    echo " Done."
fi

if [[ "$failed_patches_exist" = true ]]; then
    echo -n -e ${i_msg}" Summary of failed patch files:"
    for failed_patch in ${failed_patches_list[*]}; do
        echo -e "${failed_patch} \n"
    done
    echo -n -e "Do you want to continue? [N,y] "
    read cont_despite_falied_patches
    if [[ "$cont_despite_failed_patches" == "y" ]] ; then
        echo "OK, as you wish, continuing."
    else
        echo "OK, exiting."
        exit 1
    fi
fi

echo -e ${i_msg}" Preparing for config setup ..."
make $kern_make_opts mrproper
# echo -e ${w_msg}" Debug: Sleep for 5s (e.g. pause for hacking)..." ; sleep 5s

# A hacky option, following this procedure;
# https://unix.stackexchange.com/questions/253245/what-does-make-localmodconfig-do
# This will create a slimmed down kernel from a large one that works (e.g.
# Ubuntu or Debian). Note that localyesconfig will not work with this script
# unless it is followed immediately by e.g. a menuconfig where at least one
# module is selected, see comments in the head above.
# (It appears that localyesconfig doesn't work with KCONFIG_DEFCONFIG_LIST)
# cp $kconfig_file_full .config
# make $kern_make_opts LSMOD=./lsmod.txt localyesconfig

# If $kconfig_file_full is empty then a defconfig will be used in the build.
make KCONFIG_DEFCONFIG_LIST=$kconfig_file_full $kern_make_opts menuconfig

# For kernels 5.12 and above we enable clang LTO (it can offer some advantages).
# https://www.phoronix.com/review/clang-lto-kernel
# https://www.phoronix.com/news/Linux-5.12-Clang-LTO-Merged
# (If and how it interfers with other toolchains than Clang+LLVM, I don't know.)
kern_ver_x="$(cut -d "." -f1 <<< "$kern_ver_num")"
kern_ver_y="$(cut -d "." -f2 <<< "$kern_ver_num")"
if [[ $kern_ver_x -ge 6 || ( $kern_ver_x -ge 5 && $kern_ver_y -ge 12 ) ]] ; then
    echo -e ${i_msg}" Kernel ${kern_ver_x}.${kern_ver_y}.z, enabling clang LTO."
    scripts/config -e LTO_CLANG_THIN
else
    echo -e ${i_msg}" Kernel ${kern_ver_x}.${kern_ver_y}.z, disabling clang LTO."
    scripts/config -d LTO_CLANG_THIN
fi

echo -e ${i_msg}" --- Starting actual compilation ---"
echo -e ${i_msg}" Compilation options: $kern_make_opts"
sleep 3

if [[ $compile_ncores -eq 0 ]] ; then
    ncores=$(nproc)
    if [[ ncores -le 2 ]] ; then
       compile_ncores=1
    else
       compile_ncores=$(($ncores -1))
    fi
    echo -e ${i_msg}" Number of cores for compilation automagically set to: $compile_ncores"
fi

echo -n -e ${i_msg}" Compiling kernel, modules and dtbs..."
make $kern_make_opts Image modules dtbs -j $compile_ncores
echo -e ${k_msg}" Done compiling kernel, modules and dtbs."

echo -n -e ${i_msg}" Installing modules in local dir..."
make $kern_make_opts INSTALL_MOD_PATH=${kern_out_dir}/modules modules_install
echo -e ${k_msg}" Done installing modules in local dir."

echo -n -e ${i_msg}" Packing modules..."
cd ${kern_out_dir}/modules/lib/modules
tar --exclude={build,source} \
  -czf ${kern_out_dir}/${kern_out_str}/modules-${kern_out_str}.tar.gz *
echo " Done."

echo -n -e ${i_msg}" Extracting header files..."
cd ${kern_src_dir}/linux-${kern_ver_num}

# The code below for extracting the header files is based on the function
# deploy_kernel_headers() in the file scripts/package/builddeb (by W. Akkerman)
# in the Linux kernel source tree.

# Make header source file list.
hdr_list_file=${kern_out_dir}/hdr_file_list.txt
touch $hdr_list_file
find . arch/$targ_arch -maxdepth 1 -name Makefile\* > $hdr_list_file
find include scripts -type f -o -type l >> $hdr_list_file
find arch/$targ_arch -name Kbuild.platforms -o -name Platform >> $hdr_list_file
find $(find arch/$targ_arch -name include -o -name scripts -type d) -type f >> $hdr_list_file

# Make header object file list.
obj_list_file=${kern_out_dir}/obj_file_list.txt
touch $obj_list_file
find arch/$targ_arch/include Module.symvers include scripts -type f >> $obj_list_file
grep "CONFIG_OBJTOOL=y" include/config/auto.conf
if [[ $? -eq 0 ]] ; then
    echo "tools/objtool/objtool" >> $obj_list_file
fi
grep "CONFIG_GCC_PLUGINS=y" include/config/auto.conf
if [[ $? -eq 0 ]] ; then
    find scripts/gcc-plugins -name \*.so >> $obj_list_file
fi

# Use tar to conveniently copy the files in the lists (w/ relative paths).
tar -cf - -T $hdr_list_file | tar -xf - -C ${kern_out_dir}/headers
tar -cf - -T $obj_list_file | tar -xf - -C ${kern_out_dir}/headers

# Copy .config manually to be where it's expected to be.
cp -f .config ${kern_out_dir}/headers/.config

echo " Done."

echo -n -e ${i_msg}" Packing headers..."
cd ${kern_out_dir}/headers
tar -czf ${kern_out_dir}/${kern_out_str}/headers-${kern_out_str}.tar.gz *
echo " Done."

echo -e ${i_msg}" Extracting and packing packing dtbs..."
for socdtbs_name in ${socdtbs_list[*]}; do
    cd ${kern_src_dir}/linux-${kern_ver_num}/arch/${targ_arch}/boot/dts/${socdtbs_name}
    # In older kernels the file dtbs-list is not auto generated so we make one.
    find . -type f -name '*.dtb' > ${socdtbs_name}_dtbs-list
    no_dtbs=$(wc -l ${socdtbs_name}_dtbs-list | cut -d ' ' -f1)
    if [[ "$?" != "0" ]] || [[ $no_dtbs -eq 0 ]]; then
        echo -e ${w_msg}" Unable to locate any dtbs for ${socdtbs_name} in kernel source tree, skipping."
    else
        echo -n -e ${i_msg}" Found $no_dtbs dtbs for ${socdtbs_name}, packing..."
        tar -czf ${kern_out_dir}/${kern_out_str}/dtb-${socdtbs_name}-${kern_out_str}.tar.gz \
            -T ${socdtbs_name}_dtbs-list
        echo " Done."
    fi
done
#echo -e ${k_msg}" Done."

echo -n -e ${i_msg}" Copying over kernel image and config to rootfs..."
cd ${kern_src_dir}/linux-${kern_ver_num}
rm -rf ${rootfs_dir}/boot/*
cp System.map ${rootfs_dir}/boot/System.map-${kern_out_str}
cp .config ${rootfs_dir}/boot/config-${kern_out_str}
cp arch/${targ_arch}/boot/Image ${rootfs_dir}/boot/vmlinux-${kern_out_str}
echo " Done."

echo -n -e ${i_msg}" Copying over modules to rootfs..."
# On Ubuntu (and thus in rootfs) /lib is a symlink to /usr/lib
mkdir -p ${rootfs_dir}/lib/modules
cp -r ${kern_out_dir}/modules/lib/modules/${kern_out_str} ${rootfs_dir}/lib/modules
echo " Done."

echo -n -e ${i_msg}" Preparing for chroot jail..."
echo -e "$ubuntu_custom_inst" >${rootfs_dir}/root/ubuntu_custom_inst.bash
chmod 0755 ${rootfs_dir}/root/ubuntu_custom_inst.bash
echo " Done."

if [[ $arch_str != "riscv64" ]]; then
    echo -n -e ${i_msg}" Installing local qemu-riscv64-static binary..."
    qemu_binary_loc=$(which qemu-riscv64-static)
    cp $qemu_binary_loc ${rootfs_dir}/usr/bin
    echo " Done."
fi

echo -e ${i_msg}" Entering chroot jail. Installing some pkgs., running some scripts..."
systemd-nspawn -q --resolv-conf=copy-host --timezone=off -D ${rootfs_dir} \
               /root/ubuntu_custom_inst.bash
rm ${rootfs_dir}/root/ubuntu_custom_inst.bash
echo -e ${k_msg}" Done in chroot jail."
sleep 2 # Just to be able to read some of the messages.

if [[ $arch_str != "riscv64" ]]; then
    echo -n -e ${i_msg}" Removing local qemu-riscv64-static binary..."
    rm ${rootfs_dir}/usr/bin/qemu-riscv64-static
    echo " Done."
fi

echo -n -e ${i_msg}" Packing the files in boot/ (e.g. kernel and initramfs)..."
cd ${rootfs_dir}/boot/
tar -czf ${kern_out_dir}/${kern_out_str}/boot-${kern_out_str}.tar.gz *
echo " Done."

if [[ "$patch_src_dir_exists" = true && "$patch_src_dir_empty" = false ]]; then
    echo -n -e ${i_msg}" Packing the applied patch files..."
    cd $patch_src_dir
    tar -czf ${kern_out_dir}/${kern_out_str}/patches-${kern_out_str}.tar.gz *.patch
echo " Done."
fi

echo -n -e ${i_msg}" Computing sha256sums for all the generated tarballs..."
cd ${kern_out_dir}/${kern_out_str}
sha256sum * >sha256sums-${kern_out_str}
echo " Done."

echo -n -e ${i_msg}" Adding README file..."
echo -n -e "$README_kernels" >README_kernels.txt
echo " Done."

echo -n -e ${i_msg}" Packing up the final tarball with everything in it..."
cd ${kern_out_dir}
tar -czf ${kern_out_str}.tar.gz ${kern_out_str}
echo " Done."

if [[ -x ${kern_out_str}.tar.gz ]] ; then
    mv ${kern_out_str}.tar.gz ${kern_out_str}.tar.gz.bak
fi
mv ${kern_out_dir}/${kern_out_str}.tar.gz $work_dir
echo -e ${i_msg}" The final package is ${kern_out_str}.tar.gz"

if [[ "$docleanup_after" == "yes" ]] ; then
    echo -n -e ${i_msg}" Doing cleanup of temporary files..."
    rm -rf $tmpfile_dir
    rm -rf $rootfs_dir
    rm -rf $kern_src_dir
    rm -rf $kern_out_dir
    echo " Done."
fi

echo -e ${k_msg}" Kernel package build complete!"
