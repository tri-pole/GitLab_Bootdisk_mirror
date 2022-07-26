# petit-bootdisk

`petit-bootdisk` is the name of a utility disk for booting various forms of
Linux images on ARM64 single board computers (SBC) and TV boxes with a resident
`u-boot`.
Booting is done via chainloading of another bootloader, Petitboot, which is
located on `petit-bootdisk` and acts as a middle stage in the booting process.
When booting a SBC/TV box with a `petit-bootdisk` attached the boot process
pauses at the Petitboot boot menu where a list of bootable devices is
displayed.
After selection of a boot menu entry, the new boot configuration (kernel and
initramfs) is loaded into memory and booting proceeds with the new
configuration (utilizing a `kexec()` call).
(The process is analogous to that of `u-root`, see
README_u-root-bootdisk.md)

Petitboot is capable of reading and parsing a range of different boot
configuration files, such as grub setups, syslinux and Petitboot's own
[native format.](https://lists.ozlabs.org/pipermail/petitboot/2022-January/001516.html)

Variants
--------

The `petit-bootdisk` exists in two variants; one with the chainloader
u-boot.ext and one without the chainloader (which boots using resident
`u-boot` together with boot scripts on the `petit-bootdisk`).
The latter bootdisk has a name ending in `-nc` ("no chainload") and enable
a faster boot process but will only work on Amlogic s922x SoCs whereas the
bootdisk using chainloading can probably be made to work also for other SoCs
(several alternative u-boot.ext available on the chainloader bootdisk).

Downloads
---------

[petit-bootdisk](https://1drv.ms/u/s!Aqo_UY80B5WOdTjyhTFQhoebEwU?e=PwkQHO)

[petit-bootdisk-nc](https://1drv.ms/u/s!Aqo_UY80B5WOerTOjvn7KxQjPcU?e=8NvWFO)

md5sums of latest release:

`7fe94271d3c27802170872c1431a2605  petit-bootisk-0v15.img.gz`

`153b2872af39b92535d04d1d02612b72  uInitrd-petitboot-0v15`

(The file uInitrd-petitboot-0v15 is intended as a plug-in replacement of a
file on one of the u-root-bootdisks, cf. the README file in the download
directory for uInitrd-petitboot-0v15.)

Caveats
-------

At present, the following two caveats exist for booting ARM64 with
`petit-bootdisk`:

- The device tree (dtb) blob present on the target image (as indicated in the
grub.cfg or extlinux.conf file) is not picked up and loaded along with the
target kernel and initramfs.
Instead, the dtb residing on the `petit-bootdisk` (and used by the kernel
running Petitboot) is inherited.
This seems to be a design decision and some reasons therefore are hinted at
[here.](https://lists.ozlabs.org/pipermail/petitboot/2022-January/001516.html)

- Under certain circumstances the Petitboot loader disables (via direct edits
to the device tree in the /sys or /proc file systems) the network interface
if a correct response to a broadcast message is not received.
This has been observed on a Beelink GT King pro but not on a Ugoos AM6 plus.
It is possible that a workaround is to edit the relevant nodes in the dtb file
as read-only, but we haven't tried that yet.
(The build of Petitboot that we use has bee configured only to boot from
USB and DISK.)

Platforms tested
----------------

The u-root-bootdisks have been tested on two Amlogic s922x TV boxes; the
Beelink GT King Pro and the Ugoos Am6 plus.
The initramfs that implements Petitboot is generic and should work with any
other SoC but the kernel on the bootdisk that runs Petitboot might only work
with Amlogic boxes (although the kernel on the bootidsk has been compiled
with support also for Allwinner and Rockchip SoCs).
(More details can be found in the README files on the bootdisk.)

Linux distros tested
--------------------

The u-root-bootdisks have been tested with Fedora 36 (Gnome, KDE), openSuse
Leap 15.4 (KDE), Armbian generic ARM64 images (XFCE) and with the Ubuntu and
Debian images built according to the instructions in adjacent README files.

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
