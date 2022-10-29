# bootdisk

This repo contains information relating to
[bootdisks](https://en.wikipedia.org/wiki/Boot_disk) for TV-boxes/SBCs based on
the ARM64 architecture.
With these bootdisks you can boot e.g. many ("generic") ARM64 Linux images with
UEFI+grub from major distributions such as Fedora 36, Ubuntu (e.g. Jammy),
Debian (e.g. Bullseye) and openSuse (Leap 15.4 and Tumbleweed).
A good use case for TV-boxes is to have the bootdisk installed on SD and have
several Linux distros installed on USBs to choose from.

All the bootdisks employ a chainloading mechanism based on the Linux
[`kexec`](https://en.wikipedia.org/wiki/Kexec)
[system call](https://wiki.archlinux.org/title/Kexec) and the bootdisks come in
two variants; one pair of disks based on the
[`Petitboot`](https://open-power.github.io/petitboot/) boot loader and another
pair based on the [`u-root`](https://u-root.org/) boot loader.
The `Petitboot` boot loader provides a somewhat nicer UI and can boot
[grub](https://wiki.archlinux.org/title/GRUB) configurations defined in
`grub.cfg` whereas the `u-root` boot loader can boot grub configurations as well
as a subset of
[syslinux](https://wiki.syslinux.org/wiki/index.php?title=SYSLINUX)
configurations,
[including](https://github.com/u-root/u-root/blob/main/pkg/boot/syslinux/syslinux.go)
the `extlinux.conf` configurations used by `u-boot`.

General info about the bootdisks `petit-bootdisk` and `u-root-bootdisk`
(incl. download links) can can be found in the files
[`README_petit-bootdisk.md`](README_petit-bootdisk.md) and
[`README_u-root-bootdisk.md`](README_u-root-bootdisk.md), respectively.
In [`README_working_distros.md`](README_working_distros.md) there is a an
annotated list of distributions that can be installed and booted with the
bootdisks.
Instructions for recreating or adapting the bootdisks can be found in the file
[`README_diy-bootdisk.md`](README_diy-bootdisk.md)

### Making ARM64 Linux images

This repo also contains scripts and information on how to create ARM64 Linux
images.

#### The easier way (with scripts)

There are three scripts available to generate images (as well as downloads of
the images).
These images are CLI/server images but is it easy to add a graphical desktop;
typically it can be installed with a single command (see comments inside the
scripts).
All scripts can be run natively on an ARM64 Ubuntu/Debian machine but also on
an x86_64 Ubuntu/Debian machine (using qemu-aarch64-static) to generate an
ARM64 image.
The generated image can be booted using any of the bootdisks but also with
[`u-boot`](https://en.wikipedia.org/wiki/Das_U-Boot) (using the
resident/vendor version installed on the TV-box/SBC).

__Opbuntu:__ With the script [`ubuntu_mkimg.bash`](ubuntu_mkimg.bash) it
is easy to produce an Ubuntu image (Focal, Jammy, Kinetic) with
[Ophub/Flippy kernel.](https://github.com/ophub/kernel/tree/main/pub/stable)
This kernel is adapted specifically for Amlogic TV-boxes (but has support also
for Rockchip and Allwinner).
The script uses a daily official build of the Ubuntu
[rootfs](https://cdimage.ubuntu.com/ubuntu-base) as a base.
Images built using this script can be
[downloaded from here](https://1drv.ms/u/s!Aqo_UY80B5WOgRhJtp07M3M-EjW1?e=KwnM48).

__Debuntu:__ Debian (Bullseye) and Ubuntu (Focal, Jammy, Kinetic) images of
"standard" type (with Debian/Ubuntu kernel) can be produced with the script
[`debuntu_dbstrap.bash`](debuntu_dbstrap.bash) which employs the
[debootstrap](https://wiki.debian.org/Debootstrap) mechanism to create the base
system.
Images built using this script can be [downloaded from here](https://1drv.ms/u/s!Aqo_UY80B5WOgSd5w5tnP9COEgeZ?e=zxF2uB).

__Arch Linux:__ An image of Arch Linux ARM64 can be produced with the script
[`archlnx_mkimg.bash`](archlnx_mkimg.bash) which uses the official Arch Linux
[rootfs](http://os.archlinuxarm.org/os) tarball (with kernel) as a basis.
An image built using this script can be
[downloaded from here](https://1drv.ms/u/s!Aqo_UY80B5WOgUmwtYSHQ2O5Al1T?e=wdBIPh).

The script `debuntu_inst.bash` is an older (deprecated) script for image
creation using debootstrap.

#### The harder way (with bare hands)

A working Ubuntu desktop image for a TV-box can also be obtained by a
straightforward conversion procedure starting with a Raspberry Pi image, see
[`README_ubuntu_frompi.md`](README_ubuntu_frompi.md).
A completely manual approach to installing Ubuntu and Debian on a SD/USB is
described in [`README_ubuntu_inst.md`](README_ubuntu_inst.md) and
[`README_debian_inst.md`](README_debian_inst.md), respectively
(the latter also covers Devuan).
All the images so created can be booted with the bootdisks.

## Screenshots

Some (low resolution) screenshots of some of the bootdisk screens.

### petit-bootdisk and petit-bootdisk-nc

![Boot menu in Petitboot](/images/petitboot-bootscreen.png "petitboot")*The
boot menu screen encountered after boot with a Petitboot bootdisk.*

### u-root-bootdisk and u-root-bootdisk-nc

![Boot menu in u-root](/images/u-root-bootmenu.png "u-root boot")*The menu
of bootable images displayed after u-root has scanned the attached devices
(here three USB sticks attached via a USB hub).*

## Disclaimer

All information here is to the best of my knowledge.
I take no responsibility for any consequences of its use, so use at your own
risk.
