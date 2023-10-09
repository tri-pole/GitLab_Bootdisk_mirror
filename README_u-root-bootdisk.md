# u-root-bootdisk

`u-root-bootdisk` is the name of a utility disk for booting various forms of
Linux images on ARM64 single board computers (SBC) and TV-boxes with a resident
`u-boot`.
Booting is done via chainloading of another bootloader, based on `u-root`,
which is located on `u-root-bootdisk` and acts as a middle stage in the
booting process.
(`u-root` is implemented in the form of an initramfs which is run by a Linux
kernel which has the `kexec()` warm boot functionality enabled.)
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
The boot process is also described in
[`README_diy-bootdisk.md](README_diy-bootdisk.md).

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
`u-boot.ext` and one without the chainloader (which boots using board
resident/vendor `u-boot` together with boot scripts on the `u-root-bootdisk`).
The latter non chainloaded version enables a faster boot process but may not
work for all TV-boxes/SBCs (this depends on the resident/vendor version of
`u-boot` and the kernel used to boot `u-root`) whereas the bootdisk using
chainloading can probably be made to work for most TV-boxes/SBCs (several
alternative `u-boot.ext` are available on the `multi-bootdisk`, see below).
The non chainloaded disk is the easiest to set up, however.

Note: The term chainloading is used to describe two diffrent things here.
First, the bootdisk itself which is chainloaded by the board resident/vendor
`u-boot`.
Second, on one of the bootdisks the binary `u-boot.ext` is used to chainload
the kernel and initramfs that runs `u-boot`.

It should be noted also that the bootdisks were developed for booting on
TV-boxes with a rather old code base for the resident/vendor `u-boot` (often
dating back to 2015) when `u-boot` was lacking some modern booting concepts.
More recent versions of (e.g. resident/vendor) `u-boot` implement
[`u-boot` Standard Boot](https://u-boot.readthedocs.io/en/latest/develop/bootstd.html)
and should e.g. be able to directly detect and parse `extlinux.conf` files.
Therefore, newer resident/vendor `u-boot` should be able to directly boot a
non chainloaded bootdisk with an added `extlinux/extlinux.conf` (provided it
is configured correctly, see e.g.
[the `u-boot` reference](https://u-boot.readthedocs.io/en/latest/develop/distro.html#boot-configuration-files)).

Downloads
---------

The files needed to set up either a `u-root-bootdisk` or a `petit-bootdisk` are
collected on a `multi-bootdisk` hosted outside of Gitlab
[here](https://mega.nz/folder/fd0DxILD#msDXVG0mBLYvP1dyPqNzAw).

The `multi-bootdisk` is released as a tarball since no special disk is needed,
only a single FAT partition large enough to hold all the files.
The skeleton image `bootdisk_skel.img` (one single, empty, FAT partition)
at the link above can be used as a basis when building a bootdisk from a
tarball (just uncompress the tarball onto the skeleton image).

Caveats
-------

At present, the following four caveats exist for booting Linux ARM64 with
`u-root` (loaded by `u-boot`):

- The device tree (dtb) blob present on the target image (as indicated in the
`grub.cfg` or `extlinux.conf` file) is not picked up and loaded along with the
target kernel and initramfs.
Instead, the dtb residing on the u-root-bootdisk (and used by the `u-root`
kernel) is inherited.
The shortcoming seems to lie partly in the `localboot()` function (since some
lower level functions support dtb's, see e.g. `load_linux_arm64()`) where the
`devicetree` (ARM64) directive in `grub.cfg` files is not recognized/parsed.
Moreover, at present it doesn't seem possible to avoid the inheritance of dtb,
see e.g. the section 'FDT Flattened Device Tree' in
[Embedded Linux Wiki: Device Tree Linux](https://elinux.org/Device_Tree_Linux).

- The file system where the target kernel and initramfs reside must be one of
the following four types; FAT16, FAT32, EXT4 or XFS.
(The file system type is detected by `u-root` by using magic numbers during
scan so e.g. an EXT4 file system on a partition inside a hybrid iso image is
permitted.)

- The `grub.cfg` file must reside in one of a few standard locations:
On each partition searched, the `u-root` function `grub()` used in
`localboot()` searches to a depth of 4 all subdirectories of
`boot,EFI,efi,grub,grub2` for the file `grub.cfg`.

- There may be combinations of kernels running Petitboot and target Linux image
  media (SD, USB2, USB3) which do not work, depending on the TV-box/SBC.
  In such a case, it is advisable to try running Petitboot with another kernel.

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

The `u-root-bootdisk`(s) have been tested on two Amlogic s922x TV-boxes; the
Beelink GT King Pro and the Ugoos Am6 plus.
The initramfs that implements `u-root` is generic and should work with any
other SoC but the kernel on the bootdisk that runs `u-root` might only work
with Amlogic boxes (although the kernel on the bootidsk has been compiled
with support also for Allwinner and Rockchip SoCs).
(More details can be found in the README files on the `multi-bootdisk`.)

Linux distros tested
--------------------

The `u-root-bootdisk`(s) have been tested on a large number of Linux
distributions, see e.g.
[`README_working_distros.md`](README_working_distros.md).

Authorship
----------

Nothing (almost) of what is present on these bootdisks is my original work;
I have mostly assembled and compiled (and slightly tweaked) other people's
source code, or written build scripts to do this, or copied freely available
scripts (e.g. boot scripts), and made disk images of the result.
Detailed descriptions of the sources of my material can be found in
[`README_diy-bootdisk.md`](README_diy-bootdisk.md).
In some cases, such as boot script files, the material has been used and
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
