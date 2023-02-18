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
(The process is analogous to that of `u-root`, see
[`README_u-root-bootdisk.md`](README_u-root-bootdisk.md).)

`Petitboot` is capable of reading and parsing several different boot
[configuration file formats](https://open-power.github.io/petitboot/func/parsers.html),
such as grub setups, syslinux and `Petitboot`'s own
[native format.](https://lists.ozlabs.org/pipermail/petitboot/2022-January/001516.html)
More documentation about `Petitboot` can be found
[here](https://open-power.github.io/petitboot).
`Petitboot` also has a built-in shell from which the
[commands of BusyBox](https://www.busybox.net/downloads/BusyBox.html)
are available so `petit-bootdisk` can serve as a rescue disk.

Variants
--------

The `petit-bootdisk` exists in two variants; one with the chainloader
`u-boot.ext` and one without the chainloader (which boots using board
resident/vendor `u-boot` together with boot scripts on the `petit-bootdisk`).
The latter bootdisk has a name ending in `-nc` ("no chainload") and enables a
faster boot process but may not work for all TV-boxes/SBCs (this depends on the
resident/vendor version of `u-boot`) whereas the bootdisk using chainloading
can probably be made to work for most TV-boxes/SBCs (several alternative
`u-boot.ext` are available on the chainloader bootdisk).
The non chainloaded disk is the easiest to set up, however.

(Note that the term chainloading is used to describe two diffrent things here.
First, the bootdisk itself which is chainloaded by the board resident/vendor
`u-boot`.
Second, on one of the bootdisks the binary `u-boot.ext` is used to chainload
the kernel and initramfs that runs `Petitboot`.)

It should be noted also that the bootdisks were developed for booting on
TV-boxes with a rather old code base for the resident/vendor `u-boot` (often
dating back to 2015) when `u-boot` was lacking some modern booting concepts.
More recent versions of (e.g. resident/vendor) `u-boot` implement
[`u-boot` Standard Boot](https://u-boot.readthedocs.io/en/latest/develop/bootstd.html)
and should e.g. be able to directly detect and parse `extlinux.conf` files.
Therefore, newer resident/vendor `u-boot` should be able to directly boot a
non chainloaded (`-nc`) bootdisk with an added `extlinux/extlinux.conf`
(provided it is configured correctly, see e.g.
[the `u-boot` reference](https://u-boot.readthedocs.io/en/latest/develop/distro.html#boot-configuration-files)
or cf. a chainloaded disk).

Downloads
---------

The actual bootdisk images are hosted outside of Gitlab, at the link below

[petit-bootdisk and petit-bootdisk-nc](https://mega.nz/folder/WclhUTpJ#jobsjgxDvph2OfXZYwyxOw)

The version of `Petitboot` on the `petit-bootdisk`(s) above is v1.13.

The bootdisks are released as tarballs since no special disk is needed, only
a single FAT partition large enough to hold all the files.
The skeleton image `bootdisk_skel.img` (one single, empty, 120M FAT partition)
can be used as a basis when building a bootdisk from a tarball of the bootdisk
files (just uncompress the tarball onto the skeleton image).

Caveats
-------

At present, the following caveats exist for booting ARM64 with `petit-bootdisk`:

- The device tree (dtb) blob present on the target image (as indicated in the
`grub.cfg` or `extlinux.conf` file) is not picked up and loaded along with the
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

- Regardless of where the bootdisk is installed (i.e. SD, USB or even eMMC)
it seems that it cannot boot (via kexec) kernels residing on SD. So, in
particular, if the bootdisk is installed on SD it will boot into `Petitboot`
but then the (kexec) loading of a kernel residing on the same SD will fail.
(This has been observed on s922x devices.)

Part of the idea with the bootdisk was to be able to have the bootdisk on SD
and have several different USBs with boot target Linux distros attached during
boot, and then simply use the bootdisk as a boot selection tool.
This works as intended on the two platforms tested (see below) but for other
boxes some experimentation may be needed with e.g. the bootdisk on USB, with
different `u-boot.ext` etc.

The above assumes that the boot order of `u-boot` is set up so that external
media is searched first, typically starting with SD (this is sometimes called
"multiboot").
If this is not enabled by default, a "toothpick" reset with an appropriate
Linux image attached (such as one of the bootdisks) can in general be used to
alter the boot order on TV-boxes. (Descriptions of this procedure are easy to
find.)

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
[`README_working_distros.md`](README_working_distros.md).

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
files on the bootdisks and in
[`README_diy-bootdisk.md`](README_diy-bootdisk.md).
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
