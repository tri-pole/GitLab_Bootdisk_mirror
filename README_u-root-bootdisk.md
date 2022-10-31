# u-root-bootdisk

`u-root-bootdisk` is the name of a utility disk for booting various forms of
Linux images on ARM64 single board computers (SBC) and TV-boxes with a resident
`u-boot`.
Booting is done via chainloading of another bootloader, based on `u-root`,
which is located on `u-root-bootdisk` and acts as a middle stage in the
booting process.
When booting a SBC/TV-box with a `u-root-bootdisk` attached, the boot process
pauses at the `u-root` boot menu where a list of bootable devices is displayed.
After selection of a boot menu entry, the new boot configuration (kernel and
initramfs) is loaded into memory and booting proceeds with the new
configuration (utilizing a `kexec()` call).

In more detail it works as follows:
The board resident `u-boot` scans storage devices for bootable configurations,
as described by the boot scripts and configuration files known to `u-boot`.
It will detect and load a default Linux kernel and initramfs on
`u-root-bootdisk`.
This kernel and initramfs combination are specially crafted to run (a subset
of) the tools from [u-root](https://github.com/u-root).
These tools will initiate a scan for for bootable grub (or syslinux)
configurations on the attached media and the results of the scan will be
presented in a boot menu.
When an entry is selected, a function of `u-root` loads the new kernel and
initramfs from the final boot target Linux image, and then executes a `kexec()`
call into the target kernel-initramfs.
The boot process is also described in the README files on the bootdisks.

It should be noted that since `u-root` scans also for bootable syslinux
configurations (e.g. `extlinux.conf`) `u-root-bootdisk` can boot also disk
images that are set up for chainloading with `u-boot.ext` (simply because
`u-root` bypasses `u-boot.ext` on the image to be booted). Therefore,
`u-root-bootdisk` implements a unified boot solution for the final stages on
booting and provides a separating layer between the SoC/board specific parts
of the boot process and the parts shared among Linux distributions.

More information about `u-root` can be found [here](https://u-root.org).
The general purpose commands available at the `u-root` shell prompt are listed
[here](https://github.com/u-root/u-root/tree/main/cmds/core).

Variants
--------

The `u-root-bootdisk` exist in two variants; one with the chainloader
u-boot.ext and one without the chainloader (which boots using resident
`u-boot` together with boot scripts on the `u-root-bootdisk`).
The latter bootdisk has a name ending in `-nc` ("no chainload") and enable
a faster boot process but may only work for Amlogic s922x SoCs whereas the
bootdisk using chainloading can (probably) be made to work also for other SoCs
(several alternative `u-boot.ext` are available on the chainloader bootdisk).

(Note that the term chainloading is used to describe two diffrent things here.
First, the bootdisk itself which is chainloaded by the board resident `u-boot`.
Second, on one of the bootdisks the binary `u-boot.ext` is used to chainload
the kernel and initramfs that runs `u-boot`.)

Downloads
---------

The actual bootdisk images are hosted outside of Gitlab, at the links below
(here at Gitlab I have only posted various mini guides and explanatory
material):

[u-root-bootdisk](https://1drv.ms/u/s!Aqo_UY80B5WObWK9pvbIA_gvdY4?e=1IXMqD)

[u-root-bootdisk-nc](https://1drv.ms/u/s!Aqo_UY80B5WObi-Z-XGwIq3hwsM?e=5qb4Zz)

md5sums of latest release:

`u-root-bootdisk-0v32.tgz        f0a2838c986b6000d1771e75022fcabe`

`u-root-bootdisk-nc_0v33.tgz     fa059ac2c1bccd4a97a3bc2bda0c7351`

`bootdisk_skel.img.gz            6c8db71655b02a0aec70135a81a9c74c`

The version of `u-root` on the latest `u-root-bootdisk`(s) listed above is
v0.10.0.

Starting with v0.28-2 the bootdisks will only be released as tarballs (since
no special disk is needed, only a single FAT partition large enough to hold
all the files).
The skeleton image `bootdisk_skel.img` (one single, empty, 120M FAT partition)
can be used as a basis when building a bootdisk from a tarball of the bootdisk
files (just uncompress the tarball onto the skeleton image).

Caveats
-------

At present, the following three caveats exist for booting ARM64 with `u-root`:

- The device tree (dtb) blob present on the target image (as indicated in the
`grub.cfg` or `extlinux.conf` file) is not picked up and loaded along with the
target kernel and initramfs.
Instead, the dtb residing on the u-root-bootdisk (and used by the `u-root`
kernel) is inherited.
The shortcoming seems to lie in the `localboot()` function (since some lower
level functions support dtb's, see e.g. `load_linux_arm64()`) where the
`devicetree` (ARM64) directive in `grub.cfg` files is not recognized/parsed.

- The file system where the target kernel and initramfs reside must be one of
the following four types; FAT16, FAT32, EXT4 or XFS.
(The file system type is detected by `u-root` by using magic numbers during
scan so e.g. an EXT4 file system on a partition inside a hybrid iso image is
permitted.)

- The `grub.cfg` file must reside in one of a few standard locations:
On each partition searched, the `u-root` function `grub()` used in
`localboot()` searches to a depth of 4 all subdirectories of
`boot,EFI,efi,grub,grub2` for the file `grub.cfg`.

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

The u-root-bootdisks have been tested on two Amlogic s922x TV-boxes; the
Beelink GT King Pro and the Ugoos Am6 plus.
The initramfs that implements (parts of) `u-root` is generic and should work
with any other SoC but the kernel on the bootdisk that runs `u-root` might
only work with Amlogic boxes (although most of the `u-root` kernels on the
bootdisks are compiled with support also for Allwinner and Rockchip SoCs).
(More details can be found in the README files on the bootdisks.)

Linux distros tested
--------------------

The u-root-bootdisks have been tested with Fedora 36 (Gnome, KDE), openSuse
Leap 15.4 (KDE), Armbian generic ARM64 images (XFCE) and with the Ubuntu and
Debian images built according to the instructions in adjacent README files.
For a full list of distribtions that work with these bootdisks, see
README_working_distros.md

Some live images of these distros and others do not work because of the
caveats listed above but the installer images typically work as intended.
(One must then remember to create a rootfs partition of type EXT4 to be able
to boot into the newly installed system.)
In other cases, live images work (e.g. Ubuntu server and Ubuntu desktop for
recent releases) but the install-to-disk process on these live images
malfunctions. (This typically happens at the stage where an initramfs is
generated or a bootloader installed; the latter is not necessary for us since
we need only a valid grub config to boot).

Authorship
----------

Nothing of what is present on these bootdisks is my original work; I have
merely assembled and compiled other people's source code, or copied freely
available scripts, and made disk images of the result. Detailed descriptions
of the sources of my material can be found in the README files on the
bootdisks. In some cases, such as script files, the material has been used and
evolved, with small modifications, in several projects or by several people.
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
over at the Beelink forums (GT King Pro subforum) about the
u-root-bootdisks.

Acknowledgements
----------------

Many thanks to user JFL at e.g. the Beelink and Manjaro forums for helping me
test, debug and develop these bootdisks.
