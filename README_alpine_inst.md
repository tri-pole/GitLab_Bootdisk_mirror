# Alpine-install

## Background

  Alpine Linux is a very lightweight, simple and potentially more secure Linux
  distro which is ideal for installation on small single board computers like
  TV-boxes for use in applications such as low load servers.

  Currently the kernel shipped with standard Alpine linux for ARM64
  (`linux-lts`) does not have enough support for Amlogic/meson to boot and work
  properly on e.g. an Amlogic TV-box.
  These notes describe how to install Alpine Linux for ARM on a USB with a
  custom kernel such as `koop-3pole` with Amlogic/meson support so that Alpine
  Linux can boot and run also on an Amlogoc SoC based device.

## Scope

  The route to installation described here is based on the QEMU install method
  outlined in [`README_QEMU_inst.md`](README_QEMU_inst.md) and therefore
  requires some familiarity with running QEMU on e.g. an x86_64 host.
  The Alpine image installed in QEMU will be an UEFI image and can, after
  transfer to e.g. an USB, be booted with any of the bootdisks `petit-bootdisk`
  or `u-root-bootdisk`.
  The USB image can also be adapted to booting with resident/vendor u-boot by
  repurposing the EFI partition (by installing a kernel, initramfs, boot
  scripts and possibly a chainloader `u-boot.ext`), see e.g.
  [`README_diy-bootdisk.md`](README_diy-bootdisk.md)
  In the example below we use a `koop-3pole` kernel to provide the necessary
  Amlogic support but another good alternative is Ophub's kernels (which employ
  the same simple tarball packaging).

## Outline

  We describe first how to install Alpine on a disk image (or directly to
  SD/USB) which will give a standard UEFI image with the default Alpine
  kernel installed (`linux-lts`).
  After this, we discuss how to install a kernel with Amlogic/meson support
  and set up the required `grub.cfg` file with the necessary adaptions to get
  the kernel to work properly and avoid some quirks in the Alpine init process.

## Install Alpine
 
  The install process can be summarized as follows:

  - Get the iso installer file/image for the "standard" flavor of Alpine Linux
    for ARM64 (aarch64).

  - Do a normal installation using the QEMU method into a image (typically an
    image file mounted via a loop device), see
	[`README_QEMU_inst.md`](README_QEMU_inst.md).
    The installation will create a three-partition setup; one EFI partition,
    one swap partition and one rootfs partition (ext4). You will be asked to
    set up (just) a root account but it can be good to setup a user account
    also (e.g. at first boot) for remote login via ssh (enabled by default).

  - Verify that the installed Alpine image is working properly by booting it in
    QEMU (with the installed default Alpine kernel `linux-lts`) and check that
	networking works etc. (again, see
	[`README_QEMU_inst.md`](README_QEMU_inst.md)).

  - Get a recent `koop-3pole` kernel (6.6.y or above) from
    [here](https://mega.nz/folder/qY8RXIDQ#0ZTPEXzlmEk4S3Z_UYdbCQ).
    In the following we will assume that the kernel `6.6.16-koop-3pole` is
    used.

  - With the Alpine Linux standard image up and running in QEMU, install into
    this image the `koop-3pole` kernel package. (To get the `koop-3pole` into
    the Alpine image, either copy it onto the image file using a loop device
    mount when the Alpine image is not running or use e.g. ssh from the Alpine
    image running in QEMU to get the `koop-3pole` tarball from outside.)
    Installing the `koop-3pole` kernel package in Alpine amounts only to
    un-tarring a tarball, with some sub-tarballs; see the READMEs in the
    download location for `koop-3pole` kernels. The sub-tarball with boot
    files contains several versions of kernel, initramfs etc. but only the
    `vmlinuz` kernel file is needed (and of course the modules tree).

  - In the Alpine image running in QEMU, make a new initramfs for the
    `koop-3pole` kernel like so:

    `# mkinitfs 6.6.16-koop-3pole`

    The result will be a file called `initramfs-3pole` and it can be good to
    rename it to `initramfs-6.6.16-koop-3pole`

  - Make a backup copy of `/boot/grub/grub.cfg` and then create a new version
    of this file with a boot entry for the `koop-3pole` kernel.
    A simple version of such a boot entry can look like so:

```
menuentry 'Alpine Linux v3.19, with Linux 6.6.16-koop-3pole' {

        linux   /boot/vmlinuz-6.6.16-koop-3pole root=UUID=4f9f9f1b-859c-463a-b6cf-3f912eba88b6 ro  rootfstytpe=ext4 console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 noautodetect
        initrd  /boot/initramfs-6.6.16-koop-3pole

}
```

  - Kernel command line options: The `noautodetect` option is passed to the init
    process and it disables the script `/init.d/hwdrivers` which will otherwise
    bork (i.e. a workaround).
    The `ro` option (not necessary) is taken from the original Alpine `grub.cfg`
    since the Alpine boot process is designed to first mount the rootfs
    read-only.

  - Edit `/etc/inittab` to reflect the correct terminal(s); comment out the
    ttyAMA0 line and add one line for ttyAML0:

    `# ttyAMA0::respawn:/sbin/getty -L 0 ttyAMA0 vt100`
    `ttyAML0::respawn:/sbin/getty -L 0 ttyAML0 vt100`

  - Add an entry for ttyAML0 in `/etc/securetty`.

  - Shut down the Alpine image running in QEMU and then burn (e.g. using dd)
    the image to a USB stick (unless the QEMU image uses the USB directly as
    disk). (It is advisable to use e.g. `gdisk` and make sure that the second
    GPT table is placed at the end of the physical space of the USB disk.
    A simple way to do this is to enter `gdisk` with the USB as target and
    then just issue a "write" command; `gdisk` will then (possibly) ask you if
    you want to fix the incorrectly positioned second GPT table.)

  - The USB image should now be bootable on your TV-box using a bootdisk and
    by chosing the boot entry for Alpine Linux with the `koop-3pole` kernel at
    the bootdisk boot menu prompt.
