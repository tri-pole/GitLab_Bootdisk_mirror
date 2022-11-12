# Working Linux distributions

## Background

This document provides an annotated list over Linux distributions that are
known to work with the bootdisks.

## Scope

Here we only give basic information on working distributions and, occasionally,
minor hints on how to get a distro up and running with the bootdisks.
For detailed information the reader is referred to the adjacent README files.
The installation target for the Linux distribution is USB everywhere below
(with the bootdisk installed on SD).

The list covers distributions that have been tested and found working on
Beelink GT King Pro and Ugoos Am6 plus (both Amlogic s922x).
The list doesn't include images made with our image making scripts (e.g. for
Ubuntu, Debian, ArchLinux) since these images can all be booted both with the
bootdisks and with `u-boot`.

Unless otherwise noted, everything works as intended on the distributions
listed (HDMI video, HDMI sound, Ethernet, WiFi, Bluetooth), but see the caveats
below.
Also, unless otherwise noted (and where applicable), the editions of the
distributions listed are the latest stable or long term stable (e.g. Debian
Bullseye and Ubuntu Jammy).

### Caveats

To get sound over HDMI to work (at least on s922x) it is in general required to
run a certain script once (as ordinary user).
The script is called `g12_sound.sh` and can be found e.g.
[here](https://gitlab.manjaro.org/manjaro-arm/packages/community/oc4-post-install/-/blob/master/g12_sound.sh).
Likewise, in order to get WiFi and Bluetooth up and working it is sometimes
required to locate and install the right firmware files for the chips in
question (various Internet sources describe this).

## Distributions

In general, the requirements for a Linux ARM64 distribution to boot and run
from USB is that there is available a kernel and initramfs with sufficient
support for the boot medium (here USB) and for the TV-box/SBC (SoC) in
question.
For some of the distributions everything is in place on the images already as
posted on the download site, on others only minor tweaks are needed (such as
setting up a `grub.cfg` file).
For some distributions a new kernel needs to be installed and for others a
new image may need to be built because of shortcomings in the existing
installers.
(Examples of these scenarios and details are given in the adjacent README
files.)
Here, we only give a short summary of the steps needed to get a certain
distro up and running.

### Ubuntu

#### Ubuntu Server

Ubuntu Server ARM64 can be booted directly using the live iso (burned to USB).
Using the installer on the iso to install to disk does not work currently but
Ubuntu Server can be installed using the install method described in
README_ubuntu_inst.md

#### Ubuntu Desktop

Ubuntu Desktop ARM64 can be installed using the method described in
README_ubuntu_inst.md, or more conveniently, using the script
`debuntu_dbstrap.bash`.
It can also be installed by exchanging the kernel on a Ubuntu Raspberry Pi
image, see README_ubuntu_frompi.md
The ARM64 live iso images can be run as-is.

### Fedora

The Fedora 36 Generic ARM64 images can be booted and run as-is.
(The images can be found e.g. [here](https://alt.fedoraproject.org/alt/).)

### Debian

Debian ARM64 can be installed and run using the debootstrap procedure
described in README_debian_inst.md, or more conveniently, using the script
`debuntu_dbstrap.bash`.

### openSuse

The installer (iso)
[images](https://download.opensuse.org/ports/aarch64/distribution/leap/15.4/iso/)
for openSuse ARM64 can be run directly to install openSuse.
Alternatively, a network install procedure can be used, see
README_distro_inst_disk.md

The pre made openSuse images for ARM64, called
[appliances](https://download.opensuse.org/ports/aarch64/distribution/leap/15.4/appliances/),
can be booted with the bootdisks as long as a new `grub.cfg` file is setup.
This file should be placed at `/boot/grub/grub.cfg` and can e.g. look like
(for edition Leap 15.4)
```
menuentry "openSuse (kernel 5.14.21-150400.24.18-default)" {

linux  /boot/Image-5.14.21-150400.24.18-default root=UUID=f77b5d5a-8d8f-4020-add2-a18f31432b10 loglevel=3 splash=silent systemd.show_status=1
initrd /boot/initrd-5.14.21-150400.24.18-default

}
```
(One can add a `devicetree` directive here also, but it is currently redundant
when booting with the bootdisks, see the associated READMEs.)
On first boot it takes some time before the login screen appears and the root
password is "linux".

### Devuan

Devuan ARM64 can be installed using the debootstrap method described and the
end of README_debian_inst.md

### Armbian

The Armbian Generic ARM64 images can be booted and run as-is.

The images for specific boards can be run if a simple `grub.cfg` file is added.
For instance, on Ugoos Am6 plus the image for Odroid N2 can be booted and run
with a file `/boot/grub/grub.cfg` like so (example for release 22.08.1):

```
menuentry "Armbian (kernel 5.19.5-meson64)" {

linux  /boot/vmlinuz-5.19.5-meson64 root=UUID=68fce3a0-0094-49ab-98db-1741d0916724 console=ttyAML0,115200 console=tty1 consoleblank=0
initrd /boot/initrd.img-5.19.5-meson64

}
```

Note: On some earlier releases of the Generic images (e.g. 22.08) HDMI might
not work with the default kernel (`linux-image-current-arm64`) on some TV-boxes.
However, log in via ssh (root@uefi-arm64, p/w "1234") still works and it is
pissible to go through the initial setup from there and then install e.g.
e.g. the kernel `linux-image-current-meson64` and reboot to have working HDMI.

#### Ophub's builds

Ophub's [builds](https://github.com/ophub/amlogic-s9xxx-armbian) of Armbian can
be booted with a simple `grub.cfg` just like the board specific Armbian images.
However, Ophub's images already have a template for `extlinux.conf` (named
`extlinux.conf.bak`) which `u-root-bootdisk` can parse.
Therefore, it is easy to simply edit this file and use `u-root-bootdisk` for
booting.
For instance, on Ugoos Am6 plus the image for s922x can be booted with an
`/extlinux/extlinux.conf` file like so (example for Ophub build 220901):

```
label Armbian
    kernel /vmlinuz-5.10.140-ophub
    initrd /initrd.img-5.10.140-ophub
    fdt /dtb/amlogic/meson-g12b-ugoos-am6.dtb
    append root=UUID=9e7e9115-0312-4d0a-9587-8b0089cb6837 rootflags=data=writeback rw rootfstype=ext4 console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 loglevel=1 voutmode=hdmi disablehpd=false overscan=100 sdrmode=auto
```

### Other distributions

As mentioned above, in general it is easy to get an ARM64 Linux distro to boot
and run with the bootdisks as long as some basic requirements are fulfilled.
When this is the case, it is mostly a matter of setting up a `grub.cfg` file,
as shown above.

Another example where a simple `grub.cfg` setup is sufficient is the
TwisterOS ArmbianV2-0-3 image for rk3399 which only requires a
`/boot/grub/grub.cfg` setup like so

```
menuentry "TwisterOS (kernel 5.10.43-rockchip64)" {

linux /boot/vmlinuz-5.10.43-rockchip64 root=UUID=f43869ab-391c-4c4b-98c0-2663c796d171 rootwait rootfstype=ext4 console=ttyAML0,115200n8 console=tty1 no_console_suspend consoleblank=0 loglevel=1
initrd /boot/initrd.img-5.10.43-rockchip64

}
```

There is also the image TwisterOS203-n2p-FINAL for OdroidN2/N2+ which likewise
can be run with a `grub.cfg` file like so

```
menuentry "TwisterOS (kernel 5.13.12-meson64)" {

linux /boot/vmlinuz-5.13.12-meson64 root=UUID=209ca851-3a74-48ed-a97c-27e3a45bcdcc rootwait rootfstype=ext4 console=ttyAML0,115200n8 console=tty1 no_console_suspend consoleblank=0 loglevel=1
initrd /boot/initrd.img-5.13.12-meson64

}
```

#### Custom

For other distributions, it can be convenient to make a custom image by going
through the following steps. (This applies to, for example, Manjaro ARM64
images on USB that can be made bootable via the bootdisks.)

- Copy over all the files from the original image to a newly made USB with one
  single large ext4 partition (using e.g. `rsync` to retain all structure).
  (Since no bootloader is used in the MBR and gap before the partition on the
  USB, the gap before the first partition can be made mininal.)
  
- Set up a new `/boot/grub/grub.cfg` file.
  (The proper kernel command line options are dependent on the kernel used and
  the SoC.)

- Sometimes needed for first boot: Copy over a "a first boot kernel+initramfs"
  which is known to work for the TV-box in question
  (e.g. one of
  [Ophub's kernels](https://github.com/ophub/amlogic-s9xxx-armbian)).

- Do a first boot and upgrade e.g. to the final kernel desired, and then do the
  rest of the customization from there (and update `grub.cfg` accordingly
  unless it is done automagically by an installed grub).

However, it should also be noted that if a Linux distribution image has a valid
syslinux/extlinux configuration then the `u-root-bootdisk` can in general be
used to boot the image (from USB) with minor alterations since `u-root` can
parse also such boot configurations (cf. the comments on Ophub's images above).
