# bootdisk

This repo contains information about some
[bootloaders](https://en.wikipedia.org/wiki/Bootloader) and
[bootdisks](https://en.wikipedia.org/wiki/Boot_disk) for
[TV-boxes](https://en.wikipedia.org/wiki/Digital_media_player) and
[SBCs](https://en.wikipedia.org/wiki/Single-board_computer) based on the ARM64
architecture.
With these bootloaders and bootdisks you can boot e.g. many ("generic") ARM64
Linux images from major distributions that have grub boot configurations, such
as Fedora, Ubuntu, Debian and openSuse.
A good use case for TV-boxes/SBCs is to have a bootdisk installed on SD and
have several Linux distros installed on USBs to choose from.

The bootdisks are built around the two bootloaders
[`Petitboot`](https://open-power.github.io/petitboot/)
and [`u-root`](https://u-root.org/).
Both `Petitboot` and `u-root` employ a
[chainloading](https://en.wikipedia.org/wiki/Chain_loading) mechanism
utilizing the Linux [`kexec`](https://en.wikipedia.org/wiki/Kexec)
[system call](https://wiki.archlinux.org/title/Kexec).
The `Petitboot` bootloader provides a somewhat nicer UI (cf. screenshots below)
and can boot [grub](https://wiki.archlinux.org/title/GRUB) configurations
defined in `grub.cfg` whereas the `u-root` bootloader can boot (simple) grub
configurations as well as a subset of
[syslinux](https://wiki.syslinux.org/wiki/index.php?title=SYSLINUX)
configurations,
[including](https://github.com/u-root/u-root/blob/main/pkg/boot/syslinux/syslinux.go)
the `extlinux.conf` configurations used by
[`u-boot`](https://en.wikipedia.org/wiki/Das_U-Boot).
Both `Petitboot` and `u-root` are implemented in the form of an initramfs.

General info about the bootdisks `petit-bootdisk` and `u-root-bootdisk`
(incl. download links) can be found in the files
[`README_petit-bootdisk.md`](README_petit-bootdisk.md) and
[`README_u-root-bootdisk.md`](README_u-root-bootdisk.md), respectively.
In [`README_working_distros.md`](README_working_distros.md) there is a an
annotated list of distributions that can be installed and booted with the
bootdisks.
Instructions for (manually) recreating or adapting the bootdisks can be found
in the file [`README_diy-bootdisk.md`](README_diy-bootdisk.md)

#### Building Petitboot and u-root

An initramfs for `Petitboot` can be built from the C source either manually,
as outlined in [`README_diy-bootdisk.md`](README_diy-bootdisk.md), or e.g.
using the script [`petitboot_mkinird.bash`](petitboot_mkinitrd.bash).
Initramfses with `Petitboot` built using this script can be found at the
download location listed in
[`README_petit-bootdisk.md`](README_petit-bootdisk.md).

An initramfs for `u-root` can be built from the `Go` source using a
recent version of (the toolchain) `Go`, as outlined in
[`README_diy-bootdisk.md`](README_diy-bootdisk.md).
Initramfses with `u-root` built like this can be found at the download
location listed in
[`README_u-root-bootdisk.md`](README_u-root-bootdisk.md).

### ARM64 Linux images

This repo also contains scripts and information on how to create ARM64 Linux
images using various techniques.
Images can be created by hand or by running Linux distro installers in QEMU, or
by using the scripts provided here.
The images created by the scripts can be booted using any of the bootdisks but
also with `u-boot` (using the resident/vendor version of `u-boot` installed on
the TV-box/SBC).
The images created in QEMU or by hand can be booted e.g. with the bootdisks.

#### Image creation using scripts

There are several scripts available to generate images.
The images are CLI/server images but is it easy to add a graphical desktop;
typically it can be installed with a single command (see comments inside the
scripts).
All scripts can be run natively on an ARM64 Ubuntu/Debian machine but also on
an x86_64 Ubuntu/Debian machine (using qemu-aarch64-static) to generate an
ARM64 image.

__Debuntu:__ Debian (Bullseye, Bookworm, Trixie) and Ubuntu (Focal, Jammy,
Kinetic, Lunar, Mantic, Noble) images of standard type (with Debian/Ubuntu
kernel) can be produced with the script
[`debuntu_dbstrap.bash`](debuntu_dbstrap.bash) which employs the
[debootstrap](https://wiki.debian.org/Debootstrap) mechanism to create the
base system from the official Debian/Ubuntu repos.
Images built using this script can be downloaded from
[here](https://mega.nz/folder/CBM0hCTD#GDw2iXQpfeoqgWJ45E2Seg).

__Devuan:__  Images of Devuan (which is a Debian derived distro with
classic init system) can be created using debootstrap with the script
[`devuan_dbstrap.bash`](devuan_dbstrap.bash) from the official Devuan repos.
The releases of Devuan tracks those of Debian and the script can be used to
produce images of e.g. Chimaera (Bullseye) and Daedalus (Bookworm).
Images built using this script can be downloaded from
[here](https://mega.nz/folder/3AUj0RKB#hpWS6VSQUfIZshvVR04PJg).

__Tribuntu:__ With the script [`ubuntu_mkimg.bash`](ubuntu_mkimg.bash) it is
possible to produce Ubuntu images (Focal, Jammy, Kinetic, Lunar, Mantic, Noble)
using a daily official build of the Ubuntu
[rootfs](https://cdimage.ubuntu.com/ubuntu-base) as a base for the OS and
with a locally provided kernel, for instance the `koop-3pole` kernel
described below or an
[Ophub kernel](https://github.com/ophub/kernel/releases/tag/kernel_stable).
Images built according to this concept can be downloaded from
[here](https://mega.nz/folder/KJdAwK4Q#r4HNsKQRkLgT7HTD2s1GLg).

__Arch Linux:__ An image of Arch Linux ARM64 can be produced with the script
[`archlnx_mkimg.bash`](archlnx_mkimg.bash) which uses the official Arch Linux
[rootfs](http://os.archlinuxarm.org/os) tarball (with kernel) as a basis.
Images built using this script can be downloaded from
[here](https://mega.nz/folder/WVkjiY7Y#SReLKJnmRXOCgfGijuQMPg).

__Trinjaro:__ With the script [`archlnx_mkimg.bash`](archlnx_mkimg.bash) it is
also possible to produce Manjaro images with a Manjaro kernel or a locally
provided kernel, for instance one of the `koop-3pole` kernels mentioned above
or an Ophub kernel.
An image built using this recipe with a `koop-3pole` kernel can be downloaded
from [here](https://mega.nz/folder/qY8RXIDQ#0ZTPEXzlmEk4S3Z_UYdbCQ).
(Note: The Trinjaro images are very crude compared to the polished high
quality images produced by [Manjaro ARM](https://github.com/manjaro-arm).
The Trinjaro images are only meant as a proof of concept and for tinkering.)

__Related project:__ With the tools provided by
[debian-image-builder](https://github.com/pyavitz/debian-image-builder)
you can build an image of Debian, Devuan or Ubuntu for several well
known families of SoCs/boards (cf. the `defconfig` and `lib/boards` folders
there).

#### Image creation using QEMU

A convenient way to create an ARM64 Linux image is to run a native
ARM64 installer (e.g. in an iso file) in QEMU on e.g. an x86_64 host
and install directly onto an SD/USB attached to the host.
These images will typically be UEFI images and can be booted on a
TV-box/SBC using e.g. Petitboot/u-root.
A short description of how use QEMU for image creation like this
is given in [`README_QEMU_inst.md`](README_QEMU_inst.md).

#### Image creation using bare hands

There are also some (by now largely obsolete) README files describing
procedures for manually creating Ubuntu of Debian images using e.g.
conversion of a Raspberry Pi image as in
[`README_ubuntu_frompi.md`](README_ubuntu_frompi.md)
or using the debootstrap mechanism as in
[`README_ubuntu_inst.md`](README_ubuntu_inst.md),
[`README_debian_inst.md`](README_debian_inst.md).
(These procedures can serve as instructive examples but in general
the QEMU install method above would be preferrable.)

### ARM64 Linux kernel

The script [`arm64_kbuild.bash`](arm64_kbuild.bash) can be used to produce
(i.e. build and pack in a tarball, on a x86_64 Ubuntu Focal or Jammy host, or
natively on an ARM64 Ubuntu Jammy host) kernels with source from
[kernel.org](https://kernel.org) and with kernel config and patches provided
locally.
For instance, it can be used to produce the `koop-3pole` line of ARM64
kernels which use a kernel
[config](https://github.com/ophub/amlogic-s9xxx-armbian/tree/main/compile-kernel/tools/config)
from Ophub.
This kernel is adapted for Amlogic TV-boxes but has support also for Rockchip
and Allwinner.
Compiled packages of the `koop-3pole` series of kernels (and a few more) can
be found [here](https://mega.nz/folder/GJNjjSAY#Zru4DqCa6hyYnnkGuw02Rw).

## Screenshots

Some (low resolution) screenshots of some of the bootdisk screens.

### Petitboot

![Boot menu in Petitboot](/images/petitboot-bootscreen.png "petitboot")*The
boot menu screen encountered after boot with a Petitboot bootdisk.*

### u-root

![Boot menu in u-root](/images/u-root-bootmenu.png "u-root boot")*The menu
of bootable images displayed after u-root has scanned the attached devices
(here three USB sticks attached via a USB hub).*

## Disclaimer

All information here is to the best of my knowledge.
I take no responsibility for any consequences of its use, so use at your own
risk.
