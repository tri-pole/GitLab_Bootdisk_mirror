# dyi-bootdisk

## Background

  The bootdisks were developed for devices based on the Amlogic s922x SoC
  but there is nothing on the disks that is critically dependent on this SoC.
  In order to facilitate do-it-yourself versions of these bootdisks, and to
  encourage porting/adapting to other TV-boxes/SBCs, we give here a breakdown
  of the structure of the disks and instructions for how to reproduce them.

## Scope

  The bootdisks `petit-bootdisk` and `u-root-bootdisk` are based on the same
  basic setup and are straightforward to produce.
  In fact, since the core application of the bootdisks (`Petitboot` or
  `u-root`) is run from an initramfs (which is universal) it should be
  possible to adapt the bootdisks to any TV-box/SBC that is booted via `u-boot`
  from SD/USB, as long as a proper kernel, dtb and chainloader (if applicable)
  are available.
  The boot process might be slightly different for other SoC brands than
  Amlogic, however (see comments below).
  It should also be noted that the boot process described and used here is
  adapted to older versions of resident/vendor `u-boot` which were the most
  common on TV-boxes produced up to recently.

  We have chosen, for convenience, to provide compiled binary versions of the
  components on the bootdisks.
  However, all the binaries needed to produce the disks (including the optional
  chainloader) can be compiled from sources available at Github or other public
  git repos (see below and the README files on the disks).
  For `Petitboot` there is also the script
  [`petitboot_mkinitrd.bash`](petitboot_mkinitrd.bash) which can be used to
  build the initramfs.
  Thus, it should be easy to customize, enhance and adapt the bootdisks to
  various needs based on the information provided here.

  The procedure outlined here has been used to produce bootdisks for booting
  from SD on Beelink GT King pro and Ugoos Am6 plus.

## Outline

  Most of what follows cover the steps in the procedure of creating a bootdisk,
  what parts may need to be adapted and how this can be done.
  At the very end we also make some remarks relating to the functioning and
  use of `u-boot`.
  The latter material is not necessary for building a bootdisk but may provide
  an better understanding of what options/approaches are available for booting.

## Prerequisites

- Materials: The simplest way is probably to start with an existing
  `petit-bootdisk` or `u-root-bootdisk`, set up for booting either directly
  via boot scripts or via a chainloader `u-boot.ext`.
  The files most likely to need customization for other TV-boxes/SBCs are the
  the kernel, the dtb file and the chainloader (if applicable).
  The requirements for the kernel on a bootdisk are straightforward; it must
  be able to recognize and read the block devices and file systems, including
  (perhaps) btrfs and iso9660, and to have the kexec functionality enabled
  (kexec crash kernel functionality is not required).
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

  The value of S in the second "Sectors" line above above is mostly dependent
  on how many kernels are needed (for experimentation); a value of S which
  corresponds to 150-200M is typically enough for a basic install (with a
  couple of kernels).
  (The bootable flag for the single partition above should be left unset.)

  From now on we will assume that a disk has been prepared according to the
  outline above and that it has device descriptor `/dev/mydev`

  #### Bootloader

  The bootloader that loads the kernel and the initramfs (containing
  `Petitboot/u-root`) on the bootdisk can be either the board resident/vendor
  version of `u-boot`, in case of a disk set up for direct booting via scripts,
  or a chainloader in the form of a binary file on the bootdisk for a disk
  using the chainloading method of booting.

  In case of a chainloaded disk, the bootloader binary required is a version
  of `u-boot.bin` which is renamed to `u-boot.ext` and is placed in the root
  directory on the disk (see below).
  The version of `u-boot.bin` that is suitable as `u-boot.ext` depends on the
  SoC but luckily there are many precompiled variants freely available.
  A good selection of candidates can be found on the images produced by
  [Ophub](https://github.com/ophub/amlogic-s9xxx-armbian) and some of them
  can also be found on the bootdisks (for Amlogic s922x SOC, see
  also [here](https://mega.nz/folder/bIdjwI6B#mojtTtZPufsHD9v7gTkjdQ)).
  (Ophub refers to the binaries used for chainloading as "overload"
  bootloaders, to distinguish them from the ones to be used as "hidden"
  bootloaders (see below) which he refers to simply as "bootloaders".
  More info about `u-boot` can be found further down in this document.)
  Note, however, that some of the older versions of `u-boot.bin` may not be
  able to boot newer kernels.

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

and for a direct booted (non chainloaded) disk it could look like this

```
  ├── aml_autoscript
  ├── aml_autoscript.zip
  ├── dtbs
  │   └── amlogic
  │       └── meson-g12b-gtking-pro.dtb
  ├── s905_autoscript
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
  `u-boot` scan devices for bootable configurations), for Amlogic devices.
  We use slightly different versions of these file on the chainloaded and non
  chainloaded (direct booted) bootdisks, however.
  For the non chainloaded disks we use scripts from
  [Manjaro ARM](https://wiki.manjaro.org/index.php/Manjaro-ARM) (see the README
  files on the bootdisk) and for the chainloaded disks we use scripts from
  [D. Fauth's Github repo](https://github.com/FauthD/amlogic-u-boot-scripts)
  (see also the script `armbian-install` in
  [Ophub's repo](https://github.com/ophub/amlogic-s9xxx-armbian)).
  These files are basically text files but with a binary header added with an
  Amlogic signature.
  The header equipped files are produced with the `mkimage` command (often
  found in the `u-boot-tools` package).

  In `aml_autoscript` it is (mostly) defined in _what order_ various devices
  should be searched by `u-boot` for boot scripts and bootable configurations
  (as described by e.g.   `s905_autoscript`).
  In `s905_autoscript` it is (mostly) defined _how_ booting should be done with
  `u-boot`.
  (The division of tasks between the two scripts is not complete, however.)

  The file `aml_autoscript` is strictly only needed when "multiboot" is being
  enabled on a TV-box through the "toothpick procedure".
  (This is when the contents of `aml_autoscript` is read, parsed and stored
  internally on the TV-box during a "user reset" or "update".)

  The zero-length file `aml_autoscript.zip` is just a placeholder file.
  (My understanding is that the presence of this file is required on some
  TV-boxes to trigger the board resident/vendor boot recovery code to read and
  parse `aml_autoscript` when enabling "multiboot".)

  The script file `s905_autoscript` is always needed (it is referenced by
  `aml_autoscript`).

  In the versions of `s905_autoscript` that we employ, the code is written so
  that resident/vendor `u-boot` tries to load and execute `u-boot.ext` (from
  SD and USB) and if this fails (e.g. since there is no `u-boot.ext`, like on
  a non chainloaded disk) then `u-boot` proceeds with ordinary (i.e. non
  chainloaded) boot. 

  An excellent (as in "guru level") exposition of the boot flow of `u-boot` on
  Amlogic devices can be found on
  [7Ji's blog](https://7ji.github.io/embedded/2022/11/11/amlogic-booting.html)
  where also more details about the script files discussed above are given (see
  also [here](https://github.com/FauthD/amlogic-u-boot-scripts)).
  (It can also be helpful to study the default `u-boot` boot procedure as it is
  defined without boot scripts in the `u-boot` source code file
  `include/config_distro_bootcmd.h`.)
  For other SoC brands than Amlogic the boot order of `u-boot` is defined in
  other ways than described above but the basic working of `u-boot` and the
  usage of the boot configuration files (e.g. `extlinux.conf`, see below) is
  similar.

  It should be noted that the script files described here are (as with much of
  the material in these README files) mostly applicable to the older versions
  of `u-boot` typically found in TV-boxes.
  Newer versions of `u-boot` use
  [`u-boot` Standard Boot](https://u-boot.readthedocs.io/en/latest/develop/bootstd.html)
  where `distro boot` is typically the main boot method and `extlinux.conf` is
  the main boot configration file.
  This is what is used when a (recent) `u-boot.ext` is chainloaded after the
  vendor/resident `u-boot`.

  - *Only for non chainloaded disk*

  In the case of booting via (only) boot scripts, i.e. the non chainloaded
  case, the kernel command line parameters and the dtb file are specified in a
  small text file called `uEnv.ini` (which is referenced in `s905_autoscript`).
  The `uEnv.ini` file can for instance look like this (the `console` parameter
  varies between SoCs)

```
dtb_name=/dtbs/amlogic/meson-g12b-gtking-pro.dtb
bootargs=console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 net.ifnames=0 loglevel=1 nr_cpus=1 vga=773
```

  The kernel command line argument `nr_cpus=1` is needed on some SoCs to force
  the kernel on the bootdisk to use only one CPU during the subsequent kexec
  call.
  (Without the single-CPU restriction during kexec there may errors in the
  dmesg log of the kexec booted kernel on the target image.
  The single-CPU restriction only applies up to and during kexec; the kernel
  booted on the target image has access to all CPUs.)

  - *Only for chainloaded disk*

  On a chainloaded disk the kernel, initramfs and dtb is defined in the text
  file `extlinux.conf`.
  A simplistic version of the file `extlinux.conf` can look like this (file
  names and kernel command line arguments may vary)

```
  LINUX=/vmlinuz
  INITRD=/initramfs.cpio.gz
  FDT=/dtbs/amlogic/meson-g12b-gtking-pro.dtb
  APPEND=console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 net.ifnames=0 loglevel=1 nr_cpus=1 vga=773
```

  For newer versions of `u-boot` the main configuration file is `extlinux.conf`
  and a proper set up of this file is (typically) sufficient for booting (i.e
  no need for a chainloader), provided it resides on a device searched by
  `u-boot`.
  Moreover, these newer versions of `u-boot` can typically handle a variety of
  formats for the kernel and initramfs, in particular files without the
  `u-boot` tag/header.
  However, the `u-boot` installed (as resident/vendor `u-boot`) on most
  TV-boxes produced up to recently are based on a rather old codebase for
  `u-boot` which doesn't support booting via `extlinux.conf`; hence the
  option to use a chainloader on the bootdisk.

  #### Kernel

  The kernel file `uImage` (non chainloaded disk) or `vmlinuz` (chainloaded
  disk) is placed at the top level of the bootdisk, as indicated above.
  The `uImage` file is just a `u-boot` tagged version of a `vmlinuz` file
  which is made using the `mkimage` command like so
  
  `$ mkimage -n "uImage" -A arm64 -O linux -T kernel -C none -a 0x1080000 -e 0x1080000 -d vmlinuz uImage`
  
  (The load address `-a` and entry point `-e` parameters here are recommended
  for [Amlogic SoCs](https://linux-meson.com/howto.html), for other SoCs they
  may need to be adjusted.
  See also the documentation for [booting the ARM64 kernel](https://www.kernel.org/doc/html/latest/arm64/booting.html).)
  Note also that in the ARM community, despite the name, the `vmlinuz` kernel
  images are often not compressed (i.e. they are of type plain `Image`), and
  hence the use of `-C none` above.
  A simple application of the `file` command can give more info about a given
  `vmlinuz` file.)

  On e.g. `petit-bootdisk` there are several kernels to choose from which
  should work with Amlogic, Allwinner or Rockchip SoCs (see the `config-*`
  files on e.g. `petit-bootdisk`).
  On newer/recent versions of the bootdisks the kernels are from our own kernel
  builds, such as the `koop-3pole` line of kernels (cf. [README.md](README.md)).
  A few extra options have been enabled over the default kernel config such as
  kexec and support for btrfs and iso file systems, see the `config-` files on
  the bootdisks.

  #### dtb file

  The dtb file is typically placed at `dtbs/boardmaker/boardfile.dtb`.
  (A selection of dtb files to start with is provided on e.g.
  `petit-bootdisk`.)

  #### initramfs

  For a chainloaded disk, the initramfs file that contains either `Petitboot`
  or `u-root` is contained in a file with a name like `initramfs.cpio.gz` (as
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

  To add an `u-boot` header to `initrd.cpio.gz` do
  
  `mkimage -n 'my bootdisk' -A arm64 -O linux -T ramdisk -C gzip -d initrd.cpio.gz uInitrd`
  
  and the result will appear in `uInitrd`.
  
  ##### Doing customizations of the initramfs

  __Petitboot:__ The initramfs for `Petitboot` has been compiled and assembled
  by following, largely, the instructions posted at
  [Raptor Engineering](https://www.raptorengineering.com/content/kb/1.html)
  (see also the comments in the README file on the bootdisk).
  For recreation and adaption of this package the sources below must be
  collected.
  It is also possible to use the script
  [`petitboot_mkinitrd.bash`](petitboot_mkinitrd.bash) to build the initramfs.

  The Petitboot build was based on sources from
  [Petitboot's Github repo](https://github.com/open-power/petitboot)
  but it was done with a few tweaks (see the README file on the bootdisk,
  where also more Petitboot links can be found).
  It was based on release (tag) indicated in the file name.

  The Petitboot initramfs also contains a build of the (full) `ip` command from
  [iproute2](https://github.com/shemminger/iproute2), the `udevd` and
  `udevadm` programs from [eudev](https://github.com/eudev-project/eudev), the
  package [kexec](https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git),
  the package [busybox](https://github.com/mirror/busybox) (minus the `ip`
  command) and some of the commands from
  [e2fsprogs](http://e2fsprogs.sourceforge.net).

  For tips on how to configure and compile some these packages, see the code
  in [`petitboot_mkinitrd.bash`](petitboot_mkinitrd.bash).
  An alternative for handling of dependencies and building can be to use
  [buildroot](https://buildroot.org/).

  __u-root:__ The initramfs containing `u-root` can be recreated and adapted by
  downloading and compiling the `u-root` code from
  [u-root's Github repo](https://github.com/u-root/u-root).
  (We have cross compiled `u-root` for ARM64 on x86_64 using the instructions
  posted in this repo.)
  Our version of the `u-root` initramfs contains all the packages in the
  `u-root` package collections `core` and `boot`.
  The initramfs has been compiled from a `u-root` source release (tag) as
  indicated in the initramfs name.

  __Tweaks:__ A few script files have been added to the Petitboot initramfs,
  most notably a hack to produce a `shutdown` command and a fake `dmidecode`
  command.
  In the `init` script/file a few additions/changes have been made in order to
  enable a smooth boot up and turning off of network connections etc.
  Similarly, in `u-root`, a small delay followed by autostart of the `boot`
  command has been introduced through the `uinitcmd` mechanism (cf. `u-root`
  docs.).
  It is easy to introduce further customizations like this.

  ## Adding `Petitboot` or `u-root` to an existing Linux system

  ### Install to SD

  An existing Linux image on SD with a vfat (e.g. efi) boot partition can
  easily be modified to host `Petitboot`.
  For the chainloading case, all that is needed then is to add a `u-boot.ext`
  chainloader, some boot script files (at least `s905_autoscript`), a kernel
  to boot the initramfs with `Petitboot`, and a properly configured
  `extlinux.conf` file.
  The kernel/initramfs pair that corresponds to `Petitboot` should be the
  default entry.
  Since the SD normally is the first device to be searched by vendor/resident
  `u-boot` the kernel/initramfs pair with `Petitboot` will then be loaded and
  booted by the chainloader `u-boot.ext`.
  From `Petitboot` it is possible to load and execute (at least) all kernels
  on the rootfs on SD.

  This concept has been tested as working on Ugoos AM6 plus with a recent
  `u-boot.ext` compiled for Beelink GTK pro together with a recent `Petitboot`
  initramfs (e.g. initramfs-petitboot-0v25.cpio.gz) and a recent `koop-3pole`
  kernel.
  (The Linux image used was Fedora 38 minimal.)
  The procedure is easy to adapt for the non chainloaded case (i.e. when not
  using `u-boot.ext`, only boot scripts).
  It may or may not work on USB (or it may only work on USB); this depends on
  the combination of box and kernel.

  ### Install to eMMC

  It is straightforward to install `Petitboot` or `u-root`, using a non
  chainloaded or chainloaded setup, to a vfat partition on eMMC.
  With such an installation, the TV-box/SBC has a general boot manager that can
  handle booting of Linux from eMMC and also from removable media SD and USB.
  The only thing that needs to be changed, compared to an installation on
  SD/USB, is that a bootscript `emmc_autoscript` has to be addded.
  (A version of the script `emmc_autoscript` is outlined in the file
  `ubuntu_mking.bash` for generating Opbuntu/Tribuntu images and a copy of the
  script appears on the images generated.)
  (In the case of booting via a chainloader then the chainloader binary
  `u-boot.ext` must be renamed to `u-boot.emmc`.)

  With either `Petitboot` or `u-boot` on eMMC you can boot an installation
  image of a Linux distribution on SD/USB and install to available space on
  eMMC or you can just transfer (e.g. using the `rsync` command) the contents
  of the rootfs of a working Linux image on SD/USB (e.g. made with the scripts
  we provide).
  In the latter case, the only adaptations likely needed after transfer to
  eMMC of the rootfs are updating the UUID of the rootfs in `/etc/fstab` and
  `grub.cfg`.
  Possibly the file `/etc/initramfs-tools/conf.d/resume` needs as well.
  (To be sure you can search for files under `/etc` that contain the string
  "UUID".)

  Note that Amlogic boxes typically come with a proprietary partitioning
  scheme on eMMC and this scheme must be left intact for the vendor/resident
  u-boot to work properly.
  Mainline `u-boot`, on the other hand, can in general be fitted into a
  standard 4M gap before the first partition, see below and the `u-boot`
  documentation (e.g. the Amlogic
  [specific](https://docs.u-boot.org/en/latest/board/amlogic/index.html#boot-documentation) documentation).
  For more info on the Amlogic partitioning scheme, see e.g. the documentation
  for [7ji's `Ampart` partitioning tool](https://github.com/7Ji/ampart).

  The concept with such a general boot manager installed on eMMC has been
  tested and verified on Ugoos AM6 plus with `Petitboot` on eMMC, both with
  resident/vendor `u-boot` and mainline (GTK pro) `u-boot` installed on eMMC,
  and with the rootfs contents of several different Linux images copied over
  to separate partitions eMMC.

  If you already have a Linux installation on eMMC you can of course also adapt
  that, as outlined above, to host also `Petitboot` or `u-root` as (secondary)
  bootloader/manager.

  ### Building a FIT image

  Since both the kernel and the initramfs, and most likely also the dtb used to
  start either `Petitboot` or `u-root` will remain the same for long periods of
  time it can sometimes be convenient to pack all three into a single
  [Flattened Image Tree (FIT)](https://u-boot.readthedocs.io/en/latest/usage/fit/source_file_format.html)
  format file.
  A FIT image can be read and loaded by newer `u-boot` (incl. recent
  chainloader `u-boot.ext`) provided support for FIT images is enabled in the
  compile config.
  It is moreover easy to create a FIT image using an image tree source file
  (.its).
  Examples of image tree source files are given in the `u-boot` documentation
  and also in many other places, e.g.
  [here](https://www.gibbard.me/linux_fit_images/) (make sure that the arch
  tag in the .its file is set to the correct value e.g. arm64).
  The command used to create the FIT image is then

  `mkimage -f image.its image.itb`

  where `image.its` is the image tree source file and `image.itb` is the
  resulting FIT image.
  The FIT image can then be referenced in `extlinux.conf` via e.g. a
  `KERNEL /image.itb` option and an `APPEND` option specifying the kernel
  command line parameters to be used for the kernel inside `image.itb`.

   The FIT image can of course also be booted with the `bootm` command in
   `u-boot`. (An example of an implementation using this boot method can be
   found in the mini `petit-bootdisk` at the download location given in
   [README_petit-bootdisk.md](README_petit-bootdisk.md).)

  ## Some notes relating to `u-boot`

  The following is not needed to set up a bootdisk but might help understand
  and utilize better the booting process on e.g. TV-boxes.

  #### Adding a ("hidden") bootloader

  The code in the boot ROM on Amlogic SoCs looks for bootloaders on all
  bootable devices, according to a
  [predefined search order](https://u-boot.readthedocs.io/en/latest/board/amlogic/boot-flow.html)
  (not to be confused with `u-boot`'s programmable boot order, as defined e.g.
  in `aml_autoscript` and `s905_autoscript`), and boots the first working
  bootloader it finds.
  This means that even if the resident/vendor (on eMMC) version of `u-boot` is
  non functional (for some reason) the code in the boot ROM will scan e.g. SD
  for a bootloader and if there is one, it will be used.
  Thus, it is easy to set up a "rescue" bootdisk by adding a "hidden" `u-boot`
  bootloader to the gap on a bootdisk which will then do the same job as the
  resident/vendor `u-boot` would otherwise do so that the bootdisk will always
  boot.
  (If a hidden bootloader exists on e.g. SD and the resident/vendor u-boot is
  indeed functional, the resident/vendor u-boot will proceed to execute also
  the code in the hidden bootloader.)

  It is easy to add a u-boot bootloader to an SD, provided there is at least a
  2M gap before the first partition (some builds of `u-boot` require up to 4M,
  or even larger).
  The version of `u-boot.bin` that should then be used is one of "the bigger
  ones" (about 1.5M, typically, for mainline `u-boot`) with all the
  [FIP blobs](https://github.com/LibreELEC/amlogic-boot-fip)
  added, which is used for
  ["cold booting"](https://github.com/ARM-software/arm-trusted-firmware/blob/master/docs/design/firmware-design.rst).
  The versions intended for installation on SD usually have a name of the type
  `u-boot.bin.sd*` and these include also boot/signature code in block 0 (MBR).
  (The smaller versions of `u-boot.bin`, about 800k, are typically used for
  chainloading in the form of `u-boot.ext`, which could be considered as a
  form of "warm booting".)
  Instructions on how to copy the bootloader onto an SD can be found in many
  places.
  The operation is typically done in two passes with the `dd` command; first
  the bootloader signature/bootstrap code in the first part of sector 0 (MBR)
  and then the body of the bootloader code in sector 1 and onward in the gap
  before first partition (cf. e.g.
  [`u-boot` for w400](https://docs.u-boot.org/en/latest/board/amlogic/w400.html).)

  #### A note on eMMC and booting

  The eMMC chips used in TV-boxes come pre partitioned according to the
  (JEDEC) standard mobile eMMC partition scheme; one large user partition
  (e.g. 8G, 16G, 32G), one
  [replay protected memory block (rpmb)](https://en.wikipedia.org/wiki/Replay_Protected_Memory_Block)
  partition of 4M and two 4M partitions labeled boot0 and boot1.
  The latter two partitions hold copies of the resident/vendor bootloader
  (`u-boot`) which is also installed in the first 4M on the main partition.
  At least on Amlogic, as long as one of these three partitions holds a working
  bootloader, the box can be booted, cf. the
  [Amlogic boot flow](https://u-boot.readthedocs.io/en/latest/board/amlogic/boot-flow.html)
  alluded to above.
