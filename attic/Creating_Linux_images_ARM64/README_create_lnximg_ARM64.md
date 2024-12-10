
### ARM64 Linux images

Note: The information here is slightly outdated and the material discussed is
no longer actively maintained.

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
with a locally provided kernel, for instance the `3pole` kernels described
below or an
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
provided kernel, for instance one of the `3pole` kernels mentioned above or an
Ophub kernel.
An image built using this recipe with a `3pole` kernel can be downloaded
from [here](https://mega.nz/folder/qY8RXIDQ#0ZTPEXzlmEk4S3Z_UYdbCQ).
(Note: The Trinjaro images are very crude compared to the polished high
quality images produced by [Manjaro ARM](https://github.com/manjaro-arm).
The Trinjaro images are only meant as a proof of concept and for tinkering.)

__Related project:__ With the tools provided by
[debian-image-builder](https://github.com/pyavitz/debian-image-builder)
you can build an image of Debian, Devuan or Ubuntu for several well
known families of SoCs/boards (cf. the `defconfig` and `lib/boards` folders
there).

#### Image creation using bare hands

There are also some (by now largely obsolete) README files describing
procedures for manually creating Ubuntu or Debian images using e.g.
conversion of a Raspberry Pi image as in
[`README_ubuntu_frompi.md`](README_ubuntu_frompi.md)
or using the debootstrap mechanism as in
[`README_ubuntu_inst.md`](README_ubuntu_inst.md),
[`README_debian_inst.md`](README_debian_inst.md).
(These procedures can serve as instructive examples but in general
the QEMU install method below would be preferrable. The QEMU install method
can also be used to create hybrid images; an example is given in
[`README_alpine_inst.md`](README_alpine_inst.md).)
