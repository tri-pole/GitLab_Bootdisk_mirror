# petit-bootdisk

`petit-bootdisk` is the name of a utility disk for booting various forms of
Linux images on ARM64 single board computers (SBC) and TV-boxes with a resident
`u-boot`.
Booting is done via chainloading of another bootloader, `Petitboot`, which is
located on `petit-bootdisk` and acts as a middle stage in the booting process.
When booting a SBC/TV-box with a `petit-bootdisk` attached, the boot process
pauses at the `Petitboot` boot menu where a list of bootable devices is
displayed.
After selection of a boot menu entry, the new boot configuration (kernel and
initramfs) is loaded into memory and booting proceeds with the new
configuration (utilizing a `kexec()` call).
(The process is analogous to that of `u-root`, see README_u-root-bootdisk.md)

`Petitboot` is capable of reading and parsing several different boot
configuration file formats, such as grub setups, syslinux and `Petitboot`'s own
[native format.](https://lists.ozlabs.org/pipermail/petitboot/2022-January/001516.html)
More documentation about `Petitboot` can be found
[here](https://open-power.github.io/petitboot).
`Petitboot` also has a built-in shell from which the
[commands of BusyBox](https://www.busybox.net/downloads/BusyBox.html)
are available so `petit-bootdisk` can serve as a rescue disk.

Variants
--------

The `petit-bootdisk` exists in two variants; one with the chainloader
`u-boot.ext` and one without the chainloader (which boots using resident
`u-boot` together with boot scripts on the `petit-bootdisk`).
The latter bootdisk has a name ending in `-nc` ("no chainload") and enables
a faster boot process but may only work for Amlogic s922x SoCs whereas the
bootdisk using chainloading can (probably) be made to work also for other SoCs
(several alternative `u-boot.ext` are available on the chainloader bootdisk).

(Note that the term chainloading is used to describe two diffrent things here.
First, the bootdisk itself which is chainloaded by the board resident `u-boot`.
Second, on one of the bootdisks the binary `u-boot.ext` is used to chainload
the kernel and initramfs that runs `Petitboot`.)

Downloads
---------

The actual bootdisk images are hosted outside of Gitlab, at the links below

[petit-bootdisk](https://1drv.ms/u/s!Aqo_UY80B5WOdTjyhTFQhoebEwU?e=PwkQHO)

[petit-bootdisk-nc](https://1drv.ms/u/s!Aqo_UY80B5WOerTOjvn7KxQjPcU?e=8NvWFO)

md5sums of latest release(s):

`petit-bootdisk-0v23.tgz        2b6fdeb6122123f5c72276ad642c0887`

`petit-bootdisk-nc_0v23.tgz     4ab9475a7def4a1852cb371f0017a3af`

`bootdisk_skel.img.gz           1fde903482f2b99f9ee9fec41d02609d`

The version of `Petitboot` on the `petit-bootdisk`(s) above is v1.13.

Starting with v0.22-2 the bootdisks will only be released as tarballs (since
no special disk is needed, only a single FAT partition large enough to hold
all the files).
The skeleton image `bootdisk_skel.img` (one single, empty, 120M FAT partition)
can be used as a basis when building a bootdisk from a tarball of the bootdisk
files (just uncompress the tarball onto the skeleton image).

Caveats
-------

At present, the following caveats exist for booting ARM64 with `petit-bootdisk`:

- The device tree (dtb) blob present on the target image (as indicated in the
grub.cfg or extlinux.conf file) is not picked up and loaded along with the
target kernel and initramfs.
Instead, the dtb residing on the `petit-bootdisk` (and used by the kernel
running `Petitboot`) is inherited.
This seems to be a design decision and some reasons therefore are hinted at
[here.](https://lists.ozlabs.org/pipermail/petitboot/2022-January/001516.html)

- Our build of `Petitboot` is set up to have only USB, DISK and OPTICAL as
default boot target types. Despite this, `Petitboot` sets up network interfaces
for netbooting and tries to establish network connections. Since this is not
desirable for everyone we have added an option (in v0.20) to run `Petitboot`
in a network namespace where only the loopback interface `lo` can be brought
up. More info can be found in the README file on `petit-bootdisk`
(specifically the `pb_nonet=true` kernel command line argument).

- `Petitboot` searches the following locations for a grub boot configuration
(cf. Petitboot source `discover/grub2/grub2.c`):

```
    "/grub.cfg",
    "/menu.lst",
    "/grub/grub.cfg",
    "/grub2/grub.cfg",
    "/grub/menu.lst",
    "/boot/grub/grub.cfg",
    "/boot/grub2/grub.cfg",
    "/boot/grub/menu.lst",
    "/efi/boot/grub.cfg",
    "/GRUB.CFG",
    "/MENU.LST",
    "/GRUB/GRUB.CFG",
    "/GRUB2/GRUB.CFG",
    "/GRUB/MENU.LST",
    "/BOOT/GRUB/GRUB.CFG",
    "/BOOT/GRUB/MENU.LST",
    "/EFI/BOOT/GRUB.CFG",
    "/EFI/BOOT/grub.cfg"
```

Finally, the ability to boot from external media (sometimes called "multiboot")
for the SBC or TV-box must have been enabled.
For TV-boxes this often amounts to going through a "toothpick" reset with an
appropriate Linux image attached (such as one of the bootdisks).
(Descriptions of this procedure are easy to find.)

Platforms tested
----------------

The `petit-bootdisk`(s) have been tested on two Amlogic s922x TV-boxes; the
Beelink GT King Pro and the Ugoos Am6 plus.
The initramfs that implements `Petitboot` is generic and should work with any
other SoC but the kernel on the bootdisk that runs `Petitboot` might only work
with Amlogic boxes (although the kernel on the bootidsk has been compiled
with support also for Allwinner and Rockchip SoCs).
(More details can be found in the README files on the bootdisk.)

Linux distros tested
--------------------

The petit-bootdisks have been tested with Fedora 36 (Gnome, KDE), openSuse
Leap 15.4 (KDE), Armbian generic ARM64 images (XFCE) and with the Ubuntu and
Debian images built according to the instructions in adjacent README files.
For a full list of distribtions that work with these bootdisks, see
README_working_distros.md

Some live images of these distros and others do not work because of the
caveats listed above but the installer images typically work as intended.
In other cases, live images work (e.g. Ubuntu server and Ubuntu desktop for
recent releases) but the install-to-disk process on these live images
malfunctions (typically at the stage where an initramfs is created, cf. the
other READMEs about Ubuntu/Debian install).

Authorship
----------

Nothing (almost) of what is present on these bootdisks is my original work;
I have mostly assembled and compiled (and slightly tweaked) other people's
source code, or copied freely available scripts, and made disk images of the
result.
Detailed descriptions of the sources of my material can be found in the README
files on the bootdisks.
In some cases, such as script files, the material has been used and evolved,
with small modifications, in several projects or by several people.
To properly trace the origin of various ideas/concepts one then has to follow
the links backwards from my sources. Two projects that have produced many of
the original versions of scripts are [LibreElec](https://libreelec.tv) and
[Armbian](https://www.armbian.com).

Fork it!
--------

This work is meant only as a proof-of-concept and the hope is that others will
improve and expand it.

Discourse
---------

There is a 
[thread](https://forum.bee-link.com/forum.php?mod=viewthread&tid=72255)
over at the Beelink forums (GT King Pro subforum) about the bootdisks.

Acknowledgements
----------------

Many thanks to user JFL at e.g. the Beelink and Manjaro forums for helping me
test, debug and develop these bootdisks.
