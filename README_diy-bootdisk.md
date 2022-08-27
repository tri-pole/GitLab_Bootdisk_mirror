# dyi-bootdisk

## Background

  The bootdisks were developed for devices based on the Amlogic s922x SoC
  (e.g. Beelink GT King pro and Ugoos Am6 plus) but there is nothing on the
  disks that is critically dependent on this SoC.
  In order to facilitate do-it-yourself versions of these bootdisks, and to
  encourage porting/adapting to other TV-boxes/SBCs, we give here a breakdown
  of the structure of the disks and instructions for how to reproduce them.

## Scope

  The bootdisks `u-root-bootdisk` and `petit-bootdisk` are based on the same
  basic setup and are straightforward to produce.
  In fact, since the core application of the bootdisks (`u-root` or
  `Petitboot`) is run from an initramfs (which is universal) it should be
  possible to adapt the bootdisks to any TV-box/SBC that is booted via `u-boot`
  from SD/USB, as long as a proper kernel, dtb and `u-boot` bootloader are
  available.

  We have chosen, for convenience, to provide compiled binary versions of the
  components on the bootdisks but all the binaries needed to produce the disks,
  including `u-boot.bin`, can be compiled from sources available at Github
  or other public git repos (see below and the README files on the disks).
  Thus, it should be easy to customize, enhance and adapt the bootdisks to
  various needs based on the information provided here.
  
  The procedure outlined here has been used to produce bootdisks for booting
  from SD on Beelink GT King pro and Ugoos Am6 plus.

## Prerequisites

- Materials: The simplest is to start with either `u-root-bootdisk` (if the
  goal is to produce a chainloaded version, which is a good start) or
  `u-root-bootdisk-nc` (if the goal is a non chainloaded version).
  The files most likely to need customization for other TV-boxes/SBCs are the
  bootloader `u-boot`, the dtb file and the kernel.
  The requirements for the kernel are straightforward; it must be able to
  recognize and read the block devices and file systems, including (perhaps)
  btrfs and iso, and to have the kexec functionality enabled (kexec crash
  kernel functionality is not required).
  The boot loader (i.e. a file `u-boot.ext` for chainloading, installed on the
  first partition, or a binary `u-boot.bin`, installed to in MBR and in the
  gap before the first partition) is often the most critical part, together
  with the dtb file.
  However, any combination of dtb plus bootloader (at least for the
  chainloading case) that works to boot the box otherwise will also work for
  the bootdisk.
  
- Skillz: A bit of command line experience, but not much beyond knowing how
  to burn/flash an image using the Linux `dd` command and using `fdisk` to
  set up a MBR partition table on an SD/USB. (Being able to format and mount
  the disk is also necessary.)

## Steps in the procedure

  The setup is basically a two step procedure; prepare the disk (SD/USB) and
  copy the files.

  ### Prepare the disk (SD/USB)

  It is possible to use one and the same disk geometry both for a chainloading
  disk and for a non-chainloading disk.

  The following geometry can be used (512b sectors):

  Sectors 0-2047: MBR and gap (all standard `u-boot.bin` fit in a 1M gap,
  see below).

  Sectors 2048-S: Partition 1, type 'c' in fdisk, formatted with vfat.

  The value of S in the line above above is mostly dependent on how many
  kernels are needed (e.g. for experimentation); a value of S which
  corresponds to 100M (about 206848) is typically enough for a basic install
  (with a couple of kernels).

  For a *chainloaded disk* leave the "bootable" flag *unset* for Partition 1
  and for a *non chainloaded disk* the "bootable" flag on Partition 1 should
  be *set*.

  From now on we will assume that a disk has been prepared according to the
  outline above and that it has device descriptor `/dev/mydev`

  #### Bootloader

  The bootloader can be either a chainloader in the form of a binary file
  `u-boot.ext` placed in the root directory on the disk (see below) or a
  binary `u-boot.bin` installed into the MBR and the "gap" leading up to the
  first partition (see below).
  In both cases the binary required depends on the SoC but luckily there are
  many precompiled binaries freely available.
  A good selection of candidates can be found on the images produced by
  [ophub](https://github.com/ophub/amlogic-s9xxx-armbian) and some of them
  can also be found on the non chainloaded bootdisks.

  - *Only for chainloaded disk*
  
  The `u-boot.ext` file must be placed in the root directory of the disk.

  - *Only for non chainloaded disk*
  
  Install bootloader (here `u-boot.bin`) to SD/USB:

  `dd if=u-boot.bin of=/dev/mydev bs=1 count=444 conv=fsync,notrunc`
  
  `dd if=u-boot.bin of=/dev/mydev bs=512 skip=1 seek=1 conv=fsync,notrunc`
  
  ### Set up the necessary files

  Assuming that `/dev/mydev` is mounted at at `/mnt/mydisk`, a minimal
  bootdisk file tree under `/mnt/mydisk` could look like this for a
  chainloaded disk

```
  ├── aml_autoscript
  ├── aml_autoscript.zip
  ├── boot.scr
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
  ├── boot.scr
  ├── dtbs
  │   └── amlogic
  │       └── meson-g12b-gtking-pro.dtb
  ├── s905_autoscript
  ├── uEnv.txt
  ├── uInitrd
  └── zImage
```

  ### Details of the files

  #### Script files

  The three files `aml_autoscript, boot.scr, s905_autoscript` can be copied
  either from `u-root-bootdisk` (i.e. chainloader version) or downloaded
  directly from
  [D. Fauth's Github repo](https://github.com/FauthD/amlogic-u-boot-scripts).
  (These files are basically text files but with Amlogic signatures in the
  headers, produced by the `mkimage` command from the `u-boot-tools` package.
  According to the description on
  [D. Fauth's Github repo](https://github.com/FauthD/amlogic-u-boot-scripts)
  the file `aml_autoscript` is strictly not needed on a TV-box which has
  multiboot already enabled but the accompanying `s905_autoscript` is
  needed.)

  The zero-length file `aml_autoscript.zip` is just a placeholder file.
  (Per my understanding, the presence of `aml_autoscript.zip` is what
  triggers the board resident `u-boot` to update its (boot) environment
  variables (as part of a "recovery procedure") when enabling multi-boot
  using the "toothpick" method, at least on some boxes.
  Thus, the script file setup on the bootdisk should be sufficient to use when
  enabling multiboot on a TV-box for the first time.)

  - *Only for non chainloaded disk*

  The `uEnv.txt` file is a small text file with e.g. the following contents

```
  LINUX=/zImage
  INITRD=/uInitrd
  FDT=/dtbs/amlogic/meson-g12b-gtking-pro.dtb
  APPEND=console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 net.ifnames=0 nr_cpus=1
```

  The kernel command line argument `nr_cpus=1` is sometimes needed to force
  the kernel to use only one CPU during the kexec call (which otherwise may
  lead to errors in the dmesg log of the kexec booted kernel.)

  - *Only for chainloaded disk*

  A simplistic version of the file `extlinux.conf` (for an Amlogic SoC) can
  look like this (the `console` parameter varies between SoCs)
  
```
  LINUX=/vmlinuz
  INITRD=/initramfs.cpio.gz
  FDT=/dtbs/amlogic/meson-g12b-gtking-pro.dtb
  APPEND=console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 net.ifnames=0 nr_cpus=1
```
 
  For the kernel command line argument `nr_cpus=1`, see above.

  #### Kernel

  A good place for the `vmlinuz` file (chanloaded disk) or `zImage` (non
  chainloaded disk) is at the root of the disk, as indicated above.
  (The kernel file `zImage` on the non chainloaded disk is just a renamed
  version of a `vmlinuz` file from a chainloaded disk.)
  On `u-root-bootdisk` there are several kernels to choose from which should
  work with Amlogic, Allwinner or Rockchip SoCs (see the `config-` files on
  `u-root-bootdisk`).
  These kernels are compiled using [unifreq's](https://github.com/unifreq)
  version of the Linux kernel source by employing
  [ophub's](https://github.com/ophub/amlogic-s9xxx-armbian) build framework.
  A few extra options have been enabled over the default kernel config such
  as kexec and support for btrfs and iso filesystems, see the `config-` files
  on the bootdisks.

  #### dtb file

  The dtb file is typically placed at `dtbs/boardmaker/boardfile.dtb`.
  (A selection of dtb files to start with is provided on `u-root-bootdisk`.)

  #### initramfs

  For a chainloaded disk, the initramfs file that contains either `u-root` or
  `Petitboot` is contained in a file with a name like `initramfs.cpio.gz` (as
  in the listing above).
  For the non chainloaded disk, the gzipped cpio archive containing the
  initramfs has moreover been converted to Amlogic format by adding a small
  header to the file and the resulting file is called `uInitrd` (as in the
  listing above).
  This conversion operation has been done using the `mkimage` command
  typically found in a package called `u-boot-tools` on many Linux distos
  (see below).
  
  Next we outline the contents of the initramfs and how to edit/adapt the
  initramfs, and where find sources and how to recreate the initramfs.

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

  The initramfs containing `u-root` can be recreated and adapted by
  downloading and compiling the `u-root` code from
  [u-root's Github repo](https://github.com/u-root/u-root).
  (We have cross compiled `u-root` using the instructions posted there.)
  Our version contains all the packages in the `u-root `collections `core` and
  `boot`. It has been compiled from a `u-root` release (tag) as indicated in
  the initramfs name, the current version is v0.8.1.
  
  The initramfs for `Petitboot` has been compiled and assembled according by
  following, largely, the instructions posted at
  [Raptor Engineering](https://www.raptorengineering.com/content/kb/1.html)
  (see also the comments in the README file on the bootdisk).
  For recreation and adaption of this package the sources below must be
  collected.
  
  The Petitboot build was based on sources from
  [Petitboot's Github repo](https://github.com/open-power/petitboot)
  but it was done with a few tweaks (see the README file on the bootdisk,
  where also more Petitboot links can be found).
  It was based on release (tag) v1.13.

  The initramfs also contains a build of the (full) `ip` command from
  [iproute2](https://github.com/shemminger/iproute2), the `udevadm` daemon
  from [systemd](https://github.com/systemd/systemd), the package
  [kexec](https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git),
  and the package [busybox](https://github.com/mirror/busybox) (minus the `ip`
  command).

  (Note: For some of these packages it can be convenient to use
  [buildroot](https://buildroot.org/)
  for handling of dependencies and building.)

  A few script files have been added to the initramfs as well, most notably a
  hack to produce a `shutdown` command and a fake `dmidecode` command.
  In the `init` script/file a few additions/changes have been made in order to
  enable a smooth boot up and turning off of network connections etc.
  It is easy to introduce further customizations like this.
