# bootdisk

This repo contains information relating to
[bootdisks](https://en.wikipedia.org/wiki/Boot_disk)
for TV-boxes/SBCs based on the ARM64 architecture.
With these bootdisks you can e.g. boot many ("generic") ARM64 Linux images with
UEFI+grub from major distributions such as Fedora 36, Ubuntu (e.g. Jammy),
Debian (e.g. Bullseye) and openSuse (Leap 15.4 and Tumbleweed).
A good use case for TV-boxes is to have the bootdisk installed on SD and have
several Linux distros installed on USBs to choose from.

All the bootdisks employ a chainloading mechanism based on the Linux
`kexec()` system call and the bootdisks come in two variants; one pair of
disks based on the `u-root` boot loader and another pair based on the
`Petitboot` boot loader. The disks are named after the chainloader.

General info about the bootdisks `u-root-bootdisk` and `petit-bootdisk`
(incl. download links) can can be found in the README files with associated
names.
In README_working_distros.md there is a an annotated list of distributions
that can be installed and booted with the bootdisks.
Instructions for recreating or adapting the bootdisks can be found in the file
README_diy-bootdisk.md

### Making ARM64 Linux images

This repo also contains scripts and info on how to create ARM64 Linux images.

#### The easy way (with scripts)

There are two scripts available to generate images.

(1) With the script `ubuntu_mkimg.bash` it is easy to produce an Ubuntu
CLI/server image (Focal, Jammy or Kinetic) with ophub/flippy kernel (an
Ubuntu kernel can be installed after first boot).
The script uses a daily official build of the Ubuntu rootfs as a base.
This script can be run natively on an ARM64 Ubuntu/Debian machine but also
non natively on an x86_64 Ubuntu/Debian machine (using qemu-aarch64-static)
to generate an ARM64 image.
The generated image can be booted using any of the bootdisks but also using
`u-boot`.
Images built using this script can be [downloaded form here](https://1drv.ms/u/s!Aqo_UY80B5WOgRhJtp07M3M-EjW1?e=KwnM48).

(2) "Pure" Debian (Bullseye) and Ubuntu (Jammy) images CLI/server can be
produced with the script `debuntu_dbstrap.bash` which uses the debootstrap
mechanism to create the base system.
Also this script can be run natively on an ARM64 Ubuntu/Debian machine but also
non natively on an x86_64 Ubuntu/Debian machine (using qemu-aarch64-static)
to generate an ARM64 image.
The generated image can be booted using any of the bootdisks but also using
`u-boot`.
Images built using this script can be [downloaded from here](https://1drv.ms/u/s!Aqo_UY80B5WOgSd5w5tnP9COEgeZ?e=zxF2uB).

(3) The script `debuntu_inst.bash` is an older (deprecated) script for image
creation using debootstrap.

#### The somewhat harder way (with bare hands)

A working Ubuntu desktop image for a TV-box can also easily be obtained by a
simple conversion procedure starting with a Raspberry Pi image, see
README_ubuntu_frompi.md.
Also this image can be booted with the bootdisks.

## Screenshots

Some (low resolution) screenshots of some of the bootdisk screens.

### u-root-bootdisk and u-root-bootdisk-nc

![Prompt in u-root](/images/u-root-shellscreen.png "u-root shell")*The screen
encountered after boot with a u-root bootdisk. If the command "boot" is entered
at the prompt (lower left corner) a scan for bootable configurations over the
attached devices is started.*

![Boot menu in u-root](/images/u-root-bootmenu.png "u-root boot")*The menu
of bootable images displayed after u-root has scanned the attached devices
(here three USB sticks attached via a USB hub).*

### petit-bootdisk and petit-bootdisk-nc

![Boot menu in Petitboot](/images/petitboot-bootscreen.png "petitboot")*The
boot menu screen encountered after boot with a Petitboot bootdisk.*
