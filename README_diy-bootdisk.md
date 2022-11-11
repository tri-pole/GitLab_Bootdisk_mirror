# dyi-bootdisk

## Background

  The bootdisks were developed for devices based on the Amlogic s922x SoC
  but there is nothing on the disks that is critically dependent on this SoC.
  In order to facilitate do-it-yourself versions of these bootdisks, and to
  encourage porting/adapting to other TV-boxes/SBCs, we give here a breakdown
  of the structure of the disks and instructions for how to reproduce them.

## Scope

  The bootdisks `u-root-bootdisk` and `petit-bootdisk` are based on the same
  basic setup and are straightforward to produce.
  In fact, since the core application of the bootdisks (`u-root` or
  `Petitboot`) is run from an initramfs (which is universal) it should be
  possible to adapt the bootdisks to any TV-box/SBC that is booted via `u-boot`
  from SD/USB, as long as a proper kernel, dtb and chainloader (if applicable)
  are available.
  (The roles of resident/vendor `u-boot` and the optional chainloader are
  further explained below.)

  We have chosen, for convenience, to provide compiled binary versions of the
  components on the bootdisks.
  However, all the binaries needed to produce the disks, including the
  chainloader (if applicable), can be compiled from sources available at Github
  or other public git repos (see below and the README files on the disks).
  Thus, it should be easy to customize, enhance and adapt the bootdisks to
  various needs based on the information provided here.
  
  The procedure outlined here has been used to produce bootdisks for booting
  from SD on Beelink GT King pro and Ugoos Am6 plus.

## Outline

  Most of what follows cover the steps in the procedure of creating a bootdisk
  and what parts may need to be adpated and how this can be done.
  At the very end we also make some remarks relating to the use of `u-boot`.
  This material is not necessary for building a bootdisk but may provide an
  better understanding of what options/approaches are available for booting.

## Prerequisites

- Materials: The simplest is to start with either `u-root-bootdisk` or
  `petit-bootdisk` (for a chainloaded bootdisk), or `u-root-bootdisk-nc` or
  `petit-bootdisk-nc` (for a non chainloaded bootdisk).
  The files most likely to need customization for other TV-boxes/SBCs are the
  the kernel, the dtb file and the chainloader (if applicable).
  The requirements for the kernel are straightforward; it must be able to
  recognize and read the block devices and file systems, including (perhaps)
  btrfs and iso, and to have the kexec functionality enabled (kexec crash
  kernel functionality is not required).
  However, any combination of kernel, dtb (and chainloader) that works to boot
  the box otherwise will also work for the bootdisk.

- Skillz: A bit of command line experience, but not much beyond knowing how
  to burn/flash an image using the Linux `dd` command and using `fdisk` to
  set up a MBR partition table on an SD/USB.
  Being able to format and mount the disk is also necessary, of course.

## Steps in the procedure

  A bootdisk can be created by setting up the right files and then transfer
  them over to a SD/USB but for simplicity we shall here assume that the
  bootdisk is created directly on the target SD/USB.

  ### Prepare the disk (SD/USB)

  It is possible to use one and the same (simple) disk geometry both for a
  chainloading disk and for a non chainloading disk.
  The following single-partition geometry can be used (512B sectors):

  Sectors 0-4095: MBR (sector 0) and gap (sector 1-4095).

  Sectors 4096-S: Partition 1, partition type 'c' in fdisk, formatted with vfat.

  The reason why we recommend a 2M gap is that the gap can be good to have if
  we later decide to install a "hidden" (`u-boot`) bootloader.
  Such a bootloader is not required for normal use of the bootdisks but is
  useful if a bootdisk is later converted into a rescue disk, see below.

  The value of S in the line above above is mostly dependent on how many
  kernels are needed (for experimentation); a value of S which corresponds
  to 100M is typically enough for a basic install (with a couple of kernels).
  (The bootable flag for the single partition above should be left unset.)

  From now on we will assume that a disk has been prepared according to the
  outline above and that it has device descriptor `/dev/mydev`

  #### Bootloader

  The bootloader that loads the kernel and the initramfs (containing
  `Petitboot/u-root`) on the bootdisk can be either the board resident/vendor
  version of `u-boot`, in case of a non chainloaded disk, or a chainloader in
  the form of a binary file on the bootdisk.

  In case of a chainloaded disk, the bootloader binary required is a version
  of `u-boot.bin` which is renamed to `u-boot.ext` and is placed in the root
  directory on the disk (see below).
  The version of `u-boot.bin` that is suitable as `u-boot.ext` depends on the
  SoC but luckily there are many precompiled variants freely available.
  A good selection of candidates can be found on the images produced by
  [Ophub](https://github.com/ophub/amlogic-s9xxx-armbian) and some of them
  can also be found on the chainloaded bootdisks.
  (Ophub refers to the binaries used for chainloading as "overload"
  bootloaders, to distinguish them from the ones to be used as "hidden"
  bootloaders (see below) which he refers to simply as "bootloaders".
  More info about booting with `u-boot` can be found at the end of this
  document.)

  - *Only for chainloaded disk*
  
  The `u-boot.ext` file must be placed in the root directory of the disk.
  
  ### Set up the necessary files

  Assuming that `/dev/mydev` is mounted at `/mnt/mydisk`, a minimal bootdisk
  file tree under `/mnt/mydisk` could look like this for a chainloaded disk

```
  ├── aml_autoscript
  ├── aml_autoscript.zip
  ├── dtbs
  │   └── amlogic
  │       └── meson-g12b-gtking-pro.dtb
  ├── extlinux
  │   └── extlinux.conf
  ├── initramfs.cpio.gz
  ├── s905_autoscript
  ├── u-boot.ext
  └── vmlinuz
```

and for a non chainloaded (`-nc`) disk it could look like this

```
  ├── aml_autoscript
  ├── aml_autoscript.zip
  ├── dtbs
  │   └── amlogic
  │       └── meson-g12b-gtking-pro.dtb
  ├── uEnv.ini
  ├── uInitrd
  └── uImage
```

  ### Details of the files

  In this section we discuss details of the files needed to boot the kernel
  and initramfs that run either `Petitboot` or `u-root`.

  #### Script files

  The files `aml_autoscript` and `s905_autoscript` are the two main script
  files that control the boot sequence of `u-boot` (i.e. how resident/vendor
  `u-boot` scan devices for bootable configurations).
  We use slightly different versions of these file on the chainloaded and non
  chainloaded bootdisks, however.
  For the non chainloaded (`-nc`) disks we use scripts from
  [Manjaro ARM](https://wiki.manjaro.org/index.php/Manjaro-ARM) (see the README
  files on the bootdisk) and for the chainloaded disks we use scripts from
  [D. Fauth's Github repo](https://github.com/FauthD/amlogic-u-boot-scripts)
  (see also the script `armbian-install` in
  [Ophub's repo](https://github.com/ophub/amlogic-s9xxx-armbian)).
  These files are basically text files but with Amlogic signatures in the
  headers.
  The header equipped files are produced with the `mkimage` command (often
  found in the `u-boot-tools` package).

  In `aml_autoscript` it is defined in _what order_ various devices should be
  searched by `u-boot` for bootable configurations (as described by e.g.
  `s905_autoscript`).
  In `s905_autoscript` it is defined _how_ booting should be done with
  `u-boot`.

  The file `aml_autoscript` is strictly only needed when "multiboot" is being
  enabled on a TV-box through the "toothpick procedure".
  (This is when the contents of `aml_autoscript` is read, parsed and stored
  internally on the TV-box during a "user reset" or "update", cf. the code
  inside `aml_autoscript` and
  [D. Fauth's Github repo](https://github.com/FauthD/amlogic-u-boot-scripts)).

  The zero-length file `aml_autoscript.zip` is just a placeholder file.
  (My understanding is that the presence of this file is required on some
  TV-boxes to trigger the board resident/vendor `u-boot` to read and parse
  `aml_autoscript` when enabling "multiboot".)

  The script file `s905_autoscript` is always needed (it is referenced by
  `aml_autoscript`).

  In the versions of `s905_autoscript` that we employ, the code is written so
  that resident/vendor `u-boot` tries to load and execute `u-boot.ext` (from
  SD and USB) and if this fails (e.g. since there is no `u-boot.ext`, like on
  a non chainloaded disk) then `u-boot` proceeds with ordinary (i.e. non
  chainloaded) boot. 

  - *Only for non chainloaded disk*

  The `uEnv.ini` file is a small text file (referenced in `s905_autoscript`)
  where the dtb file and the kernel command line are specified.
  It can for instance look like this (the `console` parameter varies between
  SoCs)

```
dtb_name=/dtbs/amlogic/meson-g12b-gtking-pro.dtb
bootargs=console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 net.ifnames=0 loglevel=1 nr_cpus=1 vga=773
```

  The kernel command line argument `nr_cpus=1` is sometimes needed to force
  the kernel on the bootdisk to use only one CPU during the subsequent kexec
  call.
  (Without the single-CPU restriction during kexec there may errors in the
  dmesg log of the kexec booted kernel on the target image.
  The single-CPU restriction only applies up to and during kexec; the kernel
  booted on the target image has access to all CPUs.)

  - *Only for chainloaded disk*

  On a chainloaded disk the kernel, initramfs and dtb is defined in the text
  file `extlinux.conf`.
  A simplistic version of the file `extlinux.conf` can look like this

```
  LINUX=/vmlinuz
  INITRD=/initramfs.cpio.gz
  FDT=/dtbs/amlogic/meson-g12b-gtking-pro.dtb
  APPEND=console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 net.ifnames=0 loglevel=1 nr_cpus=1 vga=773
```
 
  #### Kernel

  The kernel file `uImage` (non chainloaded disk) or `vmlinuz` (chainloaded
  disk) is placed at the top level of the bootdisk, as indicated above.
  The `uImage` file is just a `u-boot` tagged version of a `vmlinuz` file
  which is made using the `mkimage` command like so
  
  `$ mkimage -n "uImage" -A arm64 -O linux -T kernel -C none -a 0x1080000 -e 0x1080000 -d vmlinuz uImage`
  
  (The load address `-a` and entry point `-e` parameters here are for
  [Amlogic SoCs](https://linux-meson.com/howto.html), for other SoCs they may
  need to be adjusted.
  See also the documentation for [booting the ARM64 kernel](https://www.kernel.org/doc/html/latest/arm64/booting.html).)
  Note also that in the ARM community, despite the name, the `vmlinuz` kernel
  images are often not compressed, and hence the use of `-C none` above.
  A simple application of the `file` command can give more info about a given
  `vmlinuz` file.)

  On e.g. `u-root-bootdisk` there are several kernels to choose from which
  should work with Amlogic, Allwinner or Rockchip SoCs (see the `config-` files
  on e.g. `u-root-bootdisk`).
  These kernels are compiled using [unifreq's](https://github.com/unifreq)
  version of the Linux kernel source by employing
  [Ophub's](https://github.com/ophub/amlogic-s9xxx-armbian) build framework.
  A few extra options have been enabled over the default kernel config such
  as kexec and support for btrfs and iso file systems, see the `config-` files
  on the bootdisks.

  #### dtb file

  The dtb file is typically placed at `dtbs/boardmaker/boardfile.dtb`.
  (A selection of dtb files to start with is provided on e.g.
  `u-root-bootdisk`.)

  #### initramfs

  For a chainloaded disk, the initramfs file that contains either `u-root` or
  `Petitboot` is contained in a file with a name like `initramfs.cpio.gz` (as
  in the listing above).
  For the non chainloaded disk, the gzipped cpio archive containing the
  initramfs has been converted to `u-boot` format by adding a small header to
  the file.
  The resulting file is called `uInitrd` (as in the listing above).
  This conversion operation has been done using the `mkimage` command
  (details are given below).
  
  Next we outline the contents of the initramfs and how to edit/adapt the
  initramfs, and where to find sources and how to recreate the initramfs.

  ##### Packing and unpacking the initramfs

  The file `initramfs.cpio.gz` can be straightforwardly unpacked like so
  
  `$ mkdir tmp ; cd tmp ; gunzip -c ../initramfs.cpio.gz | cpio -vi`
  
  and after some editing/adaptations it can be packed up again like so

  `find . | cpio -H newc -o | gzip -c > ../initramfs-new.cpio.gz`

  The header in the file `uInitrd` can be stripped off like so
  
  `dd if=uInitrd of=initrd.cpio.gz bs=64 skip=1`
  
  where the result `initrd.cpio.gz` can be further unpacked like above.

  To add an Amlogic header to `initrd.cpio.gz` do
  
  `mkimage -n 'my bootdisk' -A arm64 -O linux -T ramdisk -C gzip -d initrd.cpio.gz uInitrd`
  
  and the result will appear in `uInitrd`.
  
  ##### Doing customizations of the initramfs

  __u-root:__ The initramfs containing `u-root` can be recreated and adapted by
  downloading and compiling the `u-root` code from
  [u-root's Github repo](https://github.com/u-root/u-root).
  (We have cross compiled `u-root` using the instructions posted there.)
  Our version contains all the packages in the `u-root `collections `core` and
  `boot`. It has been compiled from a `u-root` release (tag) as indicated in
  the initramfs name, the current version is v0.10.0.
  
  __Petitboot:__ The initramfs for `Petitboot` has been compiled and assembled
  by following, largely, the instructions posted at
  [Raptor Engineering](https://www.raptorengineering.com/content/kb/1.html)
  (see also the comments in the README file on the bootdisk).
  For recreation and adaption of this package the sources below must be
  collected.
  
  The Petitboot build was based on sources from
  [Petitboot's Github repo](https://github.com/open-power/petitboot)
  but it was done with a few tweaks (see the README file on the bootdisk,
  where also more Petitboot links can be found).
  It was based on release (tag) v1.13.

  The Petitboot initramfs also contains a build of the (full) `ip` command from
  [iproute2](https://github.com/shemminger/iproute2), the `udevadm` daemon
  from [systemd](https://github.com/systemd/systemd), the package
  [kexec](https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git),
  the package [busybox](https://github.com/mirror/busybox) (minus the `ip`
  command) and some of the commands from
  [e2fsprogs](http://e2fsprogs.sourceforge.net).

  (Note: For some of these packages it can be convenient to use
  [buildroot](https://buildroot.org/)
  for handling of dependencies and building.)

  A few script files have been added to the Petitboot initramfs as well, most
  notably a hack to produce a `shutdown` command and a fake `dmidecode` command.
  In the `init` script/file a few additions/changes have been made in order to
  enable a smooth boot up and turning off of network connections etc.
  It is easy to introduce further customizations like this.

  ## Some notes relating to `u-boot`

  The following is not needed to set up a bootdisk but might help understand
  some of the choices made in the development of the bootdisks.

  #### Adding a ("hidden") bootloader

  The code in the boot ROM on Amlogic SoCs looks for bootloaders on all
  bootable devices, according to a
  [predefined search order](https://u-boot.readthedocs.io/en/latest/board/amlogic/boot-flow.html),
  (not to be confused with `u-boot`'s programmable boot order, as defined e.g.
  in `aml_autoscript`) and boots the first working bootloader it finds.
  This means that even if the resident/vendor (on eMMC) version of `u-boot` is
  non functional (for some reason) the code in the boot ROM will scan e.g. SD
  for a bootloader and if there is one, it will be used.
  Thus, it is easy to set up a "rescue" bootdisk by adding a "hidden" `u-boot`
  bootloader to the gap on a bootdisk which will then do the same job as the
  resident/vendor `u-boot` would otherwise do so that the bootdisk will always
  boot.

  It is easy to add a u-boot bootloader to an SD, provided there is at least a
  2M gap before the first partition.
  The version of `u-boot.bin` that should then be used is "the bigger one"
  (about 1.5M, typically) with all the
  [FIP blobs](https://github.com/LibreELEC/amlogic-boot-fip)
  added, which is used for
  ["cold booting"](https://github.com/ARM-software/arm-trusted-firmware/blob/master/docs/design/firmware-design.rst).
  (The smaller `u-boot.bin`, about 800k, is typically used for chainloading
  in the form of `u-boot.ext`, which is a form of "warm booting".)
  Instructions on how to copy the bootloader onto the SD can be found in many
  places.
  The operation is typically done in two passes with the `dd` command; first
  the bootloader signature/bootstrap code in the first part of sector 0 (MBR)
  and then the body of the bootloader code in sector 1 and onward in the gap
  before first partition.

  #### Install to eMMC

  It is straightforward to install the contents of either `petit-bootdisk-nc`
  or `u-root-bootdisk-nc` to a vfat partition on eMMC.
  With such an installation, the TV-box/SBC has a boot manager that can
  handle booting of Linux from eMMC and also from removable media SD and USB.
  The only thing that needs to be changed, compared to an installation on
  SD/USB, is that a bootscript `emmc_autoscript` has to be addded (and
  renaming `u-boot.ext` to `u-boot.emmc`, if applicable).
  (A version of the script `emmc_autoscript` is outlined in the file
  `ubuntu_mking.bash` for generating Opbuntu images and a copy of the script
  appears on the images generated.)

  This concept has been tested and verified on Ugoos Am6 plus, both with
  resident/vendor `u-boot` and mainline (GTK pro) `u-boot` on eMMC.

  A note on eMMC and booting: The eMMC chips used in TV-boxes come pre
  partitioned according to the (JEDEC) standard mobile eMMC partition scheme;
  one large user partition (e.g. 8G, 16G, 32G), one
  [replay protected memory block (rpmb)](https://en.wikipedia.org/wiki/Replay_Protected_Memory_Block)
  partition of 4M and two 4M partitions labeled boot0 and boot1.
  The latter two partitions hold copies of the resident/vendor bootloader
  (`u-boot`) which is also installed in the first 4M on the main partition.
  At least on Amlogic, as long as one of these three partitions holds a working
  bootloader, the box can be booted, cf. the
  [Amlogic boot flow](https://u-boot.readthedocs.io/en/latest/board/amlogic/boot-flow.html)
  alluded to above.
