# u-root-bootdisk

`u-root-bootdisk` is the collective name for a couple of utility disks for
booting generic ARM64 Linux images (a.k.a. UEFI or generic images) on ARM64
single board computers (SBC) and TV boxes with a resident `u-boot`.
The `u-root-bootdisk` disk images can be copied (by e.g. the Linux `dd`
command) to an SD card or a USB stick and this card/stick is used in a middle
stage in the booting process.
This middle stage is invoked after the first few stages of board initialization
has been done (by a board resident version of `u-boot`) and is responsible for
loading and booting the kernel and initramfs of the target ARM64 Linux image
(typically residing on another USB).
The middle stage utilizes a certain ARM64 Linux kernel present on the bootdisk
which is loaded (by SoC resident `u-boot` which reads boot scripts on the
bootdisk or chainloaded by u-boot.ext on the bootdisk) and executed along with
a specially crafted initramfs.
This special initramfs implements a subset of the tools from
[u-root](https://github.com/u-root/)
which provide the mechanism to continue the booting process.
When the middle stage kernel and initramfs is loaded and running (i.e.
`u-root` is working) it presents the user with a prompt (think busybox) at
which the user can enter e.g. the command "boot".
This action initiates a scan for bootable grub (or syslinux) configurations on
the attached media and the discovered bootable configurations are then
(typically after a couple of seconds) presented in a boot menu.
Once a menu entry has been selected by the user and its execution is started,
the `localboot()` function of `u-root` loads the new kernel and initramfs from
the target ARM64 Linux image, and then executes a `kexec()` call into the new
kernel-initramfs.
From this point on, the normal boot process proceeds for the target ARM64
Linux image.

In summary, when booting a SBC/TV box with a u-root-bootdisk attached, the
boot process will pause at the `u-root` prompt where the user can issue the
"boot" command.
At the boot menu then appearing the user can select one of the bootable
configurations presented and this configuration is booted by `u-root`.

(The boot process is also described in the README files on the bootdisks.)

Variants
--------

The `u-root-bootdisk` exist in two variants; one with the chainloader
u-boot.ext and one without the chainloader (which boots using resident `u-boot`
together with boot scripts on the `u-root-bootdisk`).
The latter bootdisk has a name ending in `-nc` ("no chainload") and enable
a faster boot process but will only work on Amlogic s922x SoCs whereas the
bootdisk using chainloading can probably be made to work also for other SoCs
(several alternative u-boot.ext available on the chainloader bootdisk).

Downloads
---------

The actual bootdisk images are hosted outside of Gitlab, at the links below
(here at Gitlab I have only posted various mini guides and explanatory
material):

[u-root-bootdisk](https://1drv.ms/u/s!Aqo_UY80B5WObWK9pvbIA_gvdY4?e=1IXMqD)

[u-root-bootdisk-nc](https://1drv.ms/u/s!Aqo_UY80B5WObi-Z-XGwIq3hwsM?e=5qb4Zz)

md5sums of latest release:

`u-root-bootdisk-0v25.img.gz  33fe43cb484bf71df239a80ee8785947`

`u-root-bootdisk-0v26.img.gz  55eee4b1713594476106021db07becfc`

`u-root-bootdisk-nc_0v25.img.gz  eaa86cde9d8bf24f3c39ec93e0758382`

`u-root-bootdisk-nc_0v26.img.gz  6c46aeb9ef82c0f46492f4c7bd878f57`

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

- The grub.cfg file must reside in one of a few standard locations (see
  the `u-root` function `grub()` used in `localboot()`).

Part of the idea with the `u-root-bootdisk` was to be able to have the bootdisk
on SD and then have several different USBs with boot target Linux distros
attached during boot and then simply use the bootdisk as a boot selection tool.
This works as intended on the two platforms tested (see below) but for other
boxes some experimentation may be needed with e.g. the bootdisk on USB, with
different u-boot.ext, with target image(s) connected from boot or only after
reaching u-root prompt.

Platforms tested
----------------

The u-root-bootdisks have been tested on two Amlogic s922x TV boxes; the
Beelink GT King Pro and the Ugoos Am6 plus.
The initramfs that implements (parts of) `u-root` is generic and should work
with any other SoC but the kernel on the bootdisk that runs `u-root` might
only work with Amlogic boxes (although most of the `u-root` kernels on the
bootdisks are compiled with support also for Allwinner and Rockchip SoCs).
(More details can be found in the README files on the bootdisks.)

Linux distros tested
--------------------

The u-root-bootdisks have been tested with Fedora 36 (Gnome, KDE), openSuse
Leap 15.4 (KDE) and with Armbian generic ARM64 images (XFCE).

Some live images of these distros and others do not work because of the caveats
listed above but the installer images typically work as intended.
(One must then remember to create a rootfs partition of type EXT4 to be able
to boot into the newly installed system.)
In other cases, live images work (e.g. Ubuntu server and Ubuntu desktop for
recent releases) but the install-to-disk process on these live images
malfunctions. (This typically happensa at the stage where an initramfs is
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
