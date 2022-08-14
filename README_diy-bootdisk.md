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
  Thus, it should be easy to customize and adapt the bootdisks to various
  needs.

## Prerequisites

- Materials: The simplest is to start with either `u-root-bootdisk` (if the
  goal is to produce a chainloaded version, which is a good start) or
  `u-root-bootdisk-c` (if the goal is a non chainloaded version).
  The files most likely to need customization for other TV-boxes/SBCs are the
  bootloader `u-boot`, the dtb file and the kernel.
  The requirements for the kernel are straightforward; it must be able to
  recognize and read the block devices and file systems, including (perhaps)
  btrfs and iso, and to have the kexec functionality enabled (kexec crash
  kernel functionality is not required.)
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

- Prepare the disk (SD/USB):

  It is possible to use one and the same disk geometry both for a chainloading
  disk and for a non-chainloading disk.

  The following geometry can be used (512b sectors):

  Sectors 0-2047: MBR and gap (all standard `u-boot.bin` fit in a 1M gap).

  Sectors 2048-S: Partition 1, type 'c' in fdisk, formatted with vfat.

  The value of S in the line above above is mostly dependent on how many
  kernels are needed (e.g. for experimentation); a value of S which
  corresponds to 100M (about 206848) is typically enough for a basic install
  (with a couple of kernels).

  From now on we will assume that a disk has been prepared according to the
  outline above and that it has device descriptor `/dev/mydev`

  For a *chainloaded disk* leave the "bootable" flag *unset* for Partition 1
  and for a *non chainloaded disk* the "bootable" flag on Partition 1 should
  be *set*.
 
  = *Only for non chainloaded disk* =
  
  Install bootloader (here `u-boot.bin`) to SD/USB:

  `dd if=u-boot.bin of=/dev/mydev bs=1 count=444 conv=fsync,notrunc`
  
  `dd if=u-boot.bin of=/dev/mydev bs=512 skip=1 seek=1 conv=fsync,notrunc`
  
- Set up the necessary files:

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

  Details of the files:

  == Script files ==

  The three files `aml_autoscript, boot.scr, s905_autoscript` can be copied
  either from `u-root-bootdisk` (i.e. chainloader version) or downloaded
  directly from [](https://github.com/FauthD/amlogic-u-boot-scripts)
  (These files are basically text files but with Amlogic signatures in the
  headers, produced by the `mkimage` command from the `u-boot-tools` package.)

  The zero-length file `aml_autoscript.zip` is just a placeholder file.
  (I think the presence of this file is what triggers the board resident
  `u-boot` to update its (boot) environment variables (as part of a "recovery
  procedure") when enabling multi-boot using the "toothpick" method.)

  = *Only for non chainloaded disk* =

  The `uEnv.txt` file is a short text file with e.g. the following contents

```
  LINUX=/zImage
  INITRD=/uInitrd
  FDT=/dtb/amlogic/meson-g12b-gtking-pro.dtb
  APPEND=console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 net.ifnames=0 nr_cpus=1
```

  The kernel command line argument `nr_cpus=1` is sometimes needed to force
  the kernel to use only one CPU during the kexec call (which otherwise may
  lead to errors in the dmesg log of the kexec booted kernel.)

  =*Only for chainloaded disk*=

  A simplistic version of the file `extlinux.conf` (for an Amlogic SoC) can
  look like this (the `console` parameter varies between SoCs)
  
```
  LINUX=/vmlinuz
  INITRD=/initramfs.cpio.gz
  FDT=/dtbs/amlogic/meson-g12b-gtking-pro.dtb
  APPEND=console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 net.ifnames=0 nr_cpus=1
```
 
  For the kernel command line argument `nr_cpus=1`, see above.

  == Kernel ==

  A good place for the `vmlinuz` file (chanloaded disk) or `zImage` (non
  chainloaded disk) is at the root of the disk.
  On `u-root-bootdisk` there are several kernels to choose from which should
  work with Amlogic, Allwinner or Rockchip SoCs (see `config-` files on
  `u-root-bootdisk`).

  == dtb file ==

  The dtb file is typically placed at `dtbs/boardmaker/boardfile.dtb`.
  (A selection of dtb files to start with is provided on `u-root-bootdisk`.)

  =*Only for chainloaded disk*=
  
  The `u-boot.ext` must be placed in the root directory of the disk.

  The above is all that is needed for a basic version of a bootdisk.
