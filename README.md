# bootdisk

__TL;DR:__ On an SBC or TV-box with working u-boot you can get a boot
manager+loader by replacing the default Linux initramfs with an initramfs
containing `Petitboot` or `u-root` (provided your default Linux kernel has
`kexec()`).

__News:__ We have added some documentation and material for RISCV64, such as
build scripts for Linux images and kernels (both tested on VisionFive 2), and
we have moved some material to the [attic](attic). The move reflects our change
of focus going forward which will be less on Linux images for ARM64.

This repo contains, mostly, information about some
[bootloaders](https://en.wikipedia.org/wiki/Bootloader) and
[bootdisks](https://en.wikipedia.org/wiki/Boot_disk) for
[SBCs](https://en.wikipedia.org/wiki/Single-board_computer) and
[TV-boxes](https://en.wikipedia.org/wiki/Digital_media_player).
With these bootloaders and bootdisks you can boot e.g. many ("generic") ARM64
Linux images from major distributions that have grub boot configurations, such
as Fedora, Ubuntu, Debian and openSuse.
A good use case for SBCs/TV-boxes is to have a bootdisk installed on SD and
have several Linux distros installed on USBs to choose from.
The bootloaders can be compiled for, and function, also on RISCV64 but the
required `kexec` functionality (see below) is not yet fully developed for this
architecture.

The terms bootdisk should here be interpreted in a generalized sense to mean
either a bootdisk in the traditional sense or simply a dedicated boot
partition (used early in the boot chain) that holds one of these bootloaders
to act as a new intermediate stage in the boot process.
With such an inserted stage in the boot process additional capabilities can be
added, such as the ability to boot from a variety of attached media, not only
the primary one.
Bootdisks can be built around the two bootloaders
[`Petitboot`](https://open-power.github.io/petitboot/)
and [`u-root`](https://u-root.org/), both of which employ a
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
(The bootloader components of `u-root` are known by other names, one of them
being `Linuxboot`, but for brevity we shall refer to these components
collectively as `u-root`.)
Both `Petitboot` and `u-root` are implemented in the form of an initramfs.

General info about the bootdisk concepts `petit-bootdisk` and `u-root-bootdisk`
(incl. download links) can be found in the files
[`README_petit-bootdisk.md`](README_petit-bootdisk.md) and
[`README_u-root-bootdisk.md`](README_u-root-bootdisk.md), respectively.
In [`README_working_distros.md`](README_working_distros.md) there is a an
annotated list of Linux ARM64 distributions that can be installed and booted
with the bootdisks.
Instructions for (manually) recreating or adapting the bootdisks can be found
in the file [`README_diy-bootdisk.md`](README_diy-bootdisk.md).

#### Building Petitboot and u-root

An initramfs for `Petitboot` can be built from the C source either manually,
as outlined in [`README_diy-bootdisk.md`](README_diy-bootdisk.md), or e.g.
using the script [`petitboot_mkinird.bash`](petitboot_mkinitrd.bash).
(This script can be executed natively on an ARM64/RISCV64 host or an
ARM64/RISCV64 build host run in a QEMU emulator, see below.)
Initramfses with `Petitboot` built using the script
[`petitboot_mkinird.bash`](petitboot_mkinitrd.bash) can be found
[here](https://mega.nz/folder/WclhUTpJ#jobsjgxDvph2OfXZYwyxOw).

An initramfs for `u-root` can be built from the `Go` source using a recent
version of (the toolchain) `Go`, as outlined in
[`README_diy-bootdisk.md`](README_diy-bootdisk.md).
Initramfses with `u-root` built like this can be found
[here](https://mega.nz/folder/SMt1VLSY#VTR2-eZv4jC7PH4hASp0tg).

### RISCV64 Linux images

Linux images with Debian or Ubuntu for RISCV64 can be created with the script
[`debuntu_dbstrap_riscv64.bash`](debuntu_dbstrap_riscv64.bash).
Images built with this script can be downloaded from
[here](https://mega.nz/folder/PAtXyRgA#SI9z7Hgz2n-S7BLk2SuM2A).

### ARM64 Linux images

A collection of READMEs and scripts about creation of Linux images for ARM64
can be found in the [`attic area`](attic/Creating_Linux_images_ARM64) but this
information should be regarded as obsolete and will not be actively maintained.

### Image creation using QEMU

A convenient way to create an ARM64/RISCV64 Linux image is to run a native
ARM64/RISCV64 installer (e.g. in iso file format) in QEMU on e.g. an x86_64
host and install directly onto an SD/USB attached to the host.
These images will typically be UEFI images and can be booted on a
SBC/TV-box using e.g. Petitboot/u-root.
A short description of how use QEMU for image creation like this
is given in [`README_QEMU_inst.md`](README_QEMU_inst.md).

### RISCV64 Linux kernel

Linux kernels for RISCV64 can be created with the script
[`riscv64_kbuild.bash`](riscv64_kbuild.bash) on an x86_64 or RISCV64 build
host.
The script produces simple gzipped tarballs with boot files (kernel image,
initramfs etc.), the module tree, header files and dtbs, for the board
manufacturers selected.
At present, it is mostly intended to produce (slimmed) kernels for the
VisionFive 2.
Downloads of such tarballs can be found
[here](https://mega.nz/folder/jJdTCSQQ#he0JD-96HmJIQDow-QC-VQ).

### ARM64 Linux kernel

Kernels for ARM64 can be created with the script
[`arm64_kbuild.bash`](arm64_kbuild.bash) on an x86_64 or ARM64 build host.
The script produces gzipped tarballs with boot files (kernel image, initramfs
etc.), the module tree, header files and dtbs, for the board manufacturers
selected.
For instance, it can be used to produce the `3pole` line of ARM64 kernels
(which have `kexec()` enabled and can be used with `Petitboot/u-root`).
These kernels are adapted for Amlogic TV-boxes but has support also for
Rockchip and Allwinner.
Downloads of the `3pole` series of kernels can be found
[here](https://mega.nz/folder/GJNjjSAY#Zru4DqCa6hyYnnkGuw02Rw).

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
