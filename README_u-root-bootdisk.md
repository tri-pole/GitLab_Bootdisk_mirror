# u-root-bootdisk

`u-root-bootdisk` is the name of a utility disk for booting various forms of
Linux images on ARM64 single board computers (SBC) and TV-boxes with a resident
`u-boot`.
The `u-root-bootdisk` disk image can be copied (by e.g. the Linux `dd` command)
to an SD card or a USB stick and this card/stick can be used as a middle stage
in the normal `u-boot`-based booting process.
In this middle stage a boot manager based on `u-root` can be launched which
is capable of autodetecting bootable configurations and executing the boot.

In more detail it works as follows:
After the board resident `u-boot` has has finished the board initialization
stages it loads a default Linux kernel and initramfs on
`u-root-bootdisk`.
This kernel and initramfs are specially crafted to run (a subset of) the tools
from [u-root](https://github.com/u-root).
In `u-root`, the user is presented with a prompt (think BusyBox) at which the
user can e.g. enter the command "boot".
This initiates a scan for bootable grub (or syslinux) configurations on the
attached media and the results of the scan are presented in a boot menu.
When an entry is selected the `localboot()` function of `u-root` loads the new
kernel and initramfs from the final boot target Linux image, and then executes
a `kexec()` call into the target kernel-initramfs.

The boot process is also described in the README files on the bootdisks.

It should be noted that since `u-root` scans also for bootable syslinux
configurations (e.g. extlinux.conf) `u-root-bootdisk` can boot also disk
images that are set up for chainloading with u-boot.ext (simply beacuse
`u-root` bypasses u-boot.ext on the image to be booted). Therefore,
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
a faster boot process but will only work on Amlogic s922x SoCs whereas the
bootdisk using chainloading can probably be made to work also for other SoCs
(several alternative u-boot.ext are available on the chainloader bootdisk).

(Note that the term chainloading is used to describe two diffrent things here.
First, the bootdisk itself which is chainloaded by the SoC resident `u-boot`.
Second, on one of the bootdisks the binary u-boot.ext is used to chainload
the kernel and initramfs that runs `u-boot`.)

Downloads
---------

The actual bootdisk images are hosted outside of Gitlab, at the links below
(here at Gitlab I have only posted various mini guides and explanatory
material):

[u-root-bootdisk](https://1drv.ms/u/s!Aqo_UY80B5WObWK9pvbIA_gvdY4?e=1IXMqD)

[u-root-bootdisk-nc](https://1drv.ms/u/s!Aqo_UY80B5WObi-Z-XGwIq3hwsM?e=5qb4Zz)

md5sums of latest release:

`u-root-bootdisk-0v26.img.gz  55eee4b1713594476106021db07becfc`

`u-root-bootdisk-0v28.img.gz  082d7804e3a81eb214b5151f7ff1662d`

`u-root-bootdisk-nc_0v26.img.gz  6c46aeb9ef82c0f46492f4c7bd878f57`

`u-root-bootdisk-nc_0v28.img.gz  b153326f3691dcbed31a03a5a7760d80`

The most recent version of `u-root` on the `u-root-bootdisk`(s) listed above is
v0.9.0 (found on the v0.28 disks).

Caveats
-------

At present, the following three caveats exist for booting ARM64 with `u-root`:

- The device tree (dtb) blob present on the target image (as indicated in the
grub.cfg or extlinux.conf file) is not picked up and loaded along with the
target kernel and initramfs.
Instead, the dtb residing on the u-root-bootdisk (and used by the `u-root`
kernel) is inherited.
The shortcoming seems to lie in the `localboot()` function (since some lower
level functions support dtb's, see e.g. `load_linux_arm64()`) where the
`devicetree` (ARM64) directive in grub.cfg files is not recognized/parsed.

- The file system where the target kernel and initramfs reside must be one of
the following four types; FAT16, FAT32, EXT4 or XFS.
(The file system type is detected by `u-root` by using magic numbers during
scan so e.g. an EXT4 file system on a partition inside a hybrid iso image is
permitted.)

- The grub.cfg file must reside in one of a few standard locations:
On each partition searched, the `u-root` function `grub()` used in
`localboot()` searches to a depth of 4 all subdirectories of
`boot,EFI,efi,grub,grub2` for the file `grub.cfg`.

Part of the idea with the `u-root-bootdisk` was to be able to have the bootdisk
on SD and then have several different USBs with boot target Linux distros
attached during boot and then simply use the bootdisk as a boot selection tool.
This works as intended on the two platforms tested (see below) but for other
boxes some experimentation may be needed with e.g. the bootdisk on USB, with
different u-boot.ext, with target image(s) connected from boot or only after
reaching u-root prompt.
Finally, the ability to boot from external media (sometimes called "multiboot")
for the SBC or TV-box must have been enabled.
For TV-boxes this often amounts to going through a "toothpick" reset with an
appropriate Linux image attached (such as one of the bootdisks).
(Descriptions of this procedure are easy to find.)

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
