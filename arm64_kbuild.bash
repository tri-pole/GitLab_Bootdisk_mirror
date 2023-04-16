#!/bin/bash

# arm64_kbuild.bash
# 23-03-20: v0.1
# Author: Tripole

# Script to compile the Linux kernel for ARM64 and package the result (together
# with an initramfs) in a tarball. The script must be executed (as root) on an
# Ubuntu/Debian type machine, either natively on aarch64/ARM64 or virtualized
# (using qemu-aarch64-static) on x86_64/amd64.

# Usage: (as root or using sudo) ./arm64_kbuild.bash [path-to-kernel-config]

# The script is configured to run make menuconfig using the kernel config given
# on the command line as default config (or using a defconfig, if no config is
# supplied). (If you do edits at the menu, remember to save the config under
# the name .config before exiting; compilation will then start automatically.)

# As part of the build process an initramfs is produced, based on an official
# Ubuntu rootfs (e.g. Jammy), and u-boot tagged versions of both kernel and
# initramfs (i.e. uImage and uInitrd) are created as well.

# It is possible to use both the GNU toolchain and the Clang/LLVM toolchain.
# (It is assumed that the appropriate one is downloaded and installed, see
# below.) Apart from the toolchain, a standard build environment is required
# along with a few standard Linux commands (see below). (A basic build
# environment is provided with the package build-essential but it is also
# required to have tools such as flex, bison, libncurses-dev (for menuconfig)
# and, if applicable, cross compiling tools such as gcc-aarch64-linux-gnu.
# The Linux kernel also requires (depending on config) things as libssl-dev.)

# The script has been tested on x86_64 VMs (running in qemu-system-x86_64) with
# Ubuntu Focal and Jammy, respectively and on ARM64 Jammy (qemu-system-aarch64).
# This script should be considered as a template or proof-of-concept, nothing
# more (so please fork it, adapt it, improve it).

# Inspiration taken from:
# https://www.kernel.org/doc/html/latest/index.html
# https://linux-kernel-labs.github.io/refs/heads/master/labs/arm_kernel_development.html
# https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/rebuild

# ------------------------------- parameters ---------------------------------

# Q: Which parameters do I (really) need to edit?
# A: Well, as always, "it depends". (Best to browse through them all, I guess.)

# Kernel name/number/url for kernel source from kernel.org.
kern_ver_num=6.1.24
kern_url_base="https://cdn.kernel.org/pub/linux/kernel/v6.x"
kern_txz_name=linux-${kern_ver_num}.tar.xz
kern_txz_url=${kern_url_base}/${kern_txz_name}

# Name for compiled (output) kernel and packages (tarballs).
# Note: In the config file you should have these two settings
# CONFIG_LOCALVERSION=""
# CONFIG_LOCALVERSION_AUTO is not set
kern_tag_str="-koop-3pole"
kern_out_str=${kern_ver_num}${kern_tag_str}

# List of names for SoC vendor for which you want to create a dtb package
# (tarball). (All of these SoCs must be enabled in the kernel config.)
socdtbs_list=("amlogic" "allwinner" "rockchip")

# Official Ubuntu rootfs tarball (used to make the initramfs).
# (Pick a release that "is close" to what you intend to run the kernel on.)
distro_release=jammy # {focal,jammy,kinetic,luna} (small caps)
distro_urlbase="https://cdimage.ubuntu.com/ubuntu-base"
# At cdimage.ubuntu.com, three different formats for URLs seem to be used:
# (1) Daily build of a development edition (e.g. Lunar).
# (2) Release build of a non LTS release (e.g. Kinetic).
# (3) Daily build of an LTS release (e.g. Focal, Jammy).
case "$distro_release" in
    "lunar")
        distro_buildfile=${distro_release}-base-arm64.tar.gz
        distro_buildurl=${distro_urlbase}/daily/current/${distro_buildfile}
    ;;
    "kinetic")
        distro_buildfile=ubuntu-base-22.10-base-arm64.tar.gz
        distro_urlbase=$distro_urlbase/releases
        distro_buildurl=${distro_urlbase}/kinetic/release/${distro_buildfile}
    ;;
    "focal" | "jammy")
        distro_buildfile=${distro_release}-base-arm64.tar.gz
        distro_urlbase=$distro_urlbase/${distro_release}
        distro_buildurl=${distro_urlbase}/daily/current/${distro_buildfile}
    ;;
    *)
        echo "The distro release $distro_release is unknown, exiting."
        exit 1
    ;;
esac

# These two parameters define the kernel memory load address and starting point,
# respectively, for u-boot. They are used below to create uImage from Image.
# The values must be adapted to the box/SoC. For e.g some Amlogic s922x SoC
# (GT King pro, Ugoos AM6) both values are 0x1080000 see
# https://linux-meson.com/howto.html and also
# https://www.kernel.org/doc/html/latest/arm64/booting.html
# Note: When booting mainline (kernel.org) kernel using uImage there can be a
# warning in dmesg that the kernel is misaligned at boot (with these values).
k_load_addr=0x1080000
k_entry_addr=0x1080000

# Compilation parameters, see e.g.
# https://www.kernel.org/doc/html/latest/index.html
# https://www.kernel.org/doc/html/latest/kbuild/llvm.html

targ_arch="arm64"

# A few examples of working parameter settings (use one, comment out the other).

# For an Ubuntu Jammy x86_64 host with GNU toolchain from Ubuntu stable repos
# the following settings can be used (tested with kernel 5.15.y, 6.1.y, 6.2.y):
kern_make_opts=" ARCH=$targ_arch CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=$kern_tag_str "

# For an Ubuntu Jammy x86_64 host with external ARM GNU toolchain from
# https://developer.arm.com the
# following settings can be used (tested with kernel 6.2.5):
# toolchain_dir=/opt/toolchain
# gnu_arm_tchain_name=arm-gnu-toolchain-12.2.rel1-x86_64-aarch64-none-linux-gnu
# xcompile_str="${toolchain_dir}/${gnu_arm_tchain_name}/bin/aarch64-none-linux-gnu-"
# export PATH=${xcompile_str}/bin:${PATH}
# kern_make_opts=" ARCH=$targ_arch CROSS_COMPILE=$xcompile_str LOCALVERSION=$kern_tag_str "

# For an Ubuntu Focal x86_64 host with external clang+llvm toolchain from
# https://github.com/llvm/llvm-project/releases
# the following settings can be used (tested with kernel 5.15.103 and 6.1.20):
#clangllvm_tchain_dir=/usr/local/toolchain/clang+llvm-13.0.0-x86_64-linux-gnu-ubuntu-20.04
#cc_str="${clangllvm_tchain_dir}/bin/clang"
#ld_str="${clangllvm_tchain_dir}/bin/ld.lld"
#export PATH=${clangllvm_tchain_dir}/bin:${PATH}
#kern_make_opts=" ARCH=$targ_arch CC=$cc_str LD=$ld_str LLVM=1 LLVM_IAS=1 LOCALVERSION=$kern_tag_str "

# Number of threads for kernel compilation (set to 0 for automatic selection).
compile_ncores=0

#-----------------------------------------------------------------------

# Some (but not all) commands used below to create the image.
reqd_cmdlist=("systemd-nspawn" "tar" "gzip" "wget")

reqd_cmdlist_virt=("qemu-aarch64-static")

# Location (dir) of demporary files (downloads) (for size, see below).
work_dir=$PWD
tmpfile_dir=${work_dir}/temp_files

# Location of unpacked kernel source and the output files produced by the build.
kern_src_dir=${work_dir}/kern_src
kern_out_dir=${work_dir}/kern_out

# Location of local patches to be applied
patch_src_dir=${work_dir}/my_patches

# Approximate max usage of kernel sources (unpacked), object files and rootfs
# (not including toolchain). The number grows slowly with kernel versions.
required_MiB=5500

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

update-initramfs -k $kern_out_str -c

# On ARM64 it is common to use the name vmlinuz also for uncompressed kernels.
echo "Making uImage-${kern_out_str} from vmlinuz-${kern_out_str} ..."
mkimage -n "uImage" -A arm64 -O linux -T kernel -C none \
    -a $k_load_addr -e $k_entry_addr \
    -d /boot/vmlinuz-${kern_out_str} /boot/uImage-${kern_out_str}
echo " Done."

echo "Making uInitrd-${kern_out_str} from initrd.img-${kern_out_str} ..."
mkimage -A arm64 -O linux -T ramdisk -C gzip \
    -d /boot/initrd.img-${kern_out_str} /boot/uInitrd-${kern_out_str}
echo " Done."
EOF
)

README_koop_3pole=$(cat <<EOF
The files in the tar.gz packages here are produced by the script
$calling_cmd_name
from https://gitlab.com/tripole-inc/bootdisk

Notes:
The vmlinuz file is an uncompressed ARM64 kernel (i.e. an Image).

The uImage is made with load address and entry point set as
load_address=$k_load_addr
entry_point=$k_entry_addr

The initrd.imd is based on a daily build of the offical Ubuntu rootfs (on ext4).
EOF
)

# --------------------------- preparations/checks ----------------------------

if [[ $EUID -ne 0 ]]; then
    echo -e ${e_msg}" This script must be run as root, exiting."
    exit 1
fi

arch_str=$(uname -m)
if [[ "$arch_str" != "aarch64" && "$arch_str" != "x86_64" ]]; then
    echo ${e_msg}" The architecture is not one of x86_64 or aarch64, exiting."
    exit 1
fi

have_all_cmds=yes
if [[ "$arch_str" == "aarch64" ]]; then
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

if [[ $# -eq 1 ]] ; then
    kconfig_file=$1
    if [[ -f $kconfig_file ]] ; then
        echo -e ${i_msg}" Using kernel config file"
        echo "         $kconfig_file"
    else
        echo -e ${w_msg}" The suggested kernel config file $kconfig_file does not exist!"
    fi
fi

#----------------------------------- code -----------------------------------

echo -e "\n\033[92m -- Making kernel package $kern_out_str -- \033[0m"

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

echo -n -e ${i_msg}" Making a directory for the rootfs (for initramfs) ..."
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

echo -e ${i_msg}" Downloading the kernel source tarball..."
wget -P $tmpfile_dir -nv $kern_txz_url
if [[ $? -ne 0 ]]; then
    echo -e ${e_msg}" Unable to download the kernel source tarball, exiting."
    exit 1
fi
echo -e ${k_msg}" Done."

echo -n -e ${i_msg}" Unpacking the kernel source tarball..."
tar -xf ${tmpfile_dir}/${kern_txz_name} -C $kern_src_dir
sync
echo " Done."

echo -n -e ${i_msg}" Setting up directories for kernel output files..."
mkdir -p ${kern_out_dir}/headers
mkdir -p ${kern_out_dir}/modules
mkdir -p ${kern_out_dir}/${kern_out_str}
echo " Done."

cd ${kern_src_dir}/linux-${kern_ver_num}

if [[ ! -z "$(ls -A $patch_src_dir)" ]]; then
    echo -e ${i_msg}" Applying patches..."
        for my_patch_file in $(ls -A ${patch_src_dir}/*.patch) ; do
            patch -N -p1 < $my_patch_file
        done
    echo " Done."
fi

echo -e ${i_msg}" Preparing for menuconfig..."
make $kern_make_opts mrproper
if [[ ! -z $kconfig_file ]] ; then
   cp $kconfig_file ${kern_src_dir}/linux-${kern_ver_num}/.config
fi
make $kern_make_opts menuconfig

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
tar -czf ${kern_out_dir}/${kern_out_str}/modules-${kern_out_str}.tar.gz *
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
    cd ${kern_src_dir}/linux-${kern_ver_num}/arch/arm64/boot/dts/${socdtbs_name}
    no_dtbs=$(find . -type f -name '*.dtb' | wc -l)
    if [[ $no_dtbs -eq 0 ]] ; then
        echo -e ${w_msg}" Unable to locate any dtbs for ${socdtbs_name} in kernel source tree, skipping."
    else
        echo -n -e ${i_msg}" Found $no_dtbs dtbs for ${socdtbs_name}, packing..."
        tar -czf ${kern_out_dir}/${kern_out_str}/dtb-${socdtbs_name}-${kern_out_str}.tar.gz *.dtb
        echo " Done."
    fi
done
#echo -e ${k_msg}" Done."

echo -n -e ${i_msg}" Copying over kernel files and modules to rootfs..."
cd ${kern_src_dir}/linux-${kern_ver_num}
rm -rf ${rootfs_dir}/boot/*
cp System.map ${rootfs_dir}/boot/System.map-${kern_out_str}
cp .config ${rootfs_dir}/boot/config-${kern_out_str}
# On ARM64 it is common to use the name vmlinuz also for uncompressed kernels.
cp arch/arm64/boot/Image ${rootfs_dir}/boot/vmlinuz-${kern_out_str}
# On Ubuntu (and thus in rootfs) /lib is a symlink to /usr/lib
mkdir -p ${rootfs_dir}/lib/modules
cp -r ${kern_out_dir}/modules/lib/modules/${kern_out_str} ${rootfs_dir}/lib/modules
echo " Done."

echo -n -e ${i_msg}" Preparing for chroot jail..."
echo -e "$ubuntu_custom_inst" >${rootfs_dir}/root/ubuntu_custom_inst.bash
chmod 0755 ${rootfs_dir}/root/ubuntu_custom_inst.bash
echo " Done."

if [[ $arch_str != "aarch64" ]]; then
    echo -n -e ${i_msg}" Installing local qemu-aarch64-static binary..."
    qemu_binary_loc=$(which qemu-aarch64-static)
    cp $qemu_binary_loc ${rootfs_dir}/usr/bin
    echo " Done."
fi

echo -e ${i_msg}" Entering chroot jail. Installing some pkgs., running some scripts..."
systemd-nspawn -q --resolv-conf=copy-host --timezone=off -D ${rootfs_dir} \
               /root/ubuntu_custom_inst.bash
rm ${rootfs_dir}/root/ubuntu_custom_inst.bash
echo -e ${k_msg}" Done in chroot jail."
sleep 2 # Just to be able to read some of the messages.

if [[ $arch_str != "aarch64" ]]; then
    echo -n -e ${i_msg}" Removing local qemu-aarch64-static binary..."
    rm ${rootfs_dir}/usr/bin/qemu-aarch64-static
    echo " Done."
fi

echo -n -e ${i_msg}" Packing the files in boot/ (e.g. kernel and initramfs)..."
cd ${rootfs_dir}/boot/
tar -czf ${kern_out_dir}/${kern_out_str}/boot-${kern_out_str}.tar.gz *
echo " Done."

echo -n -e ${i_msg}" Computing sha256sums for all the generated tarballs..."
cd ${kern_out_dir}/${kern_out_str}
sha256sum * >sha256sums-${kern_out_str}
echo " Done."

echo -n -e ${i_msg}" Adding README file..."
echo -n -e "$README_koop_3pole" >README_koop-3pole.txt
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
