# Ubuntu image for TV-box/SBC from Raspberry Pi image

## Background

Installing Ubuntu desktop by using rootfs (or debootstrapping) is described in
adjacent README files (and in a script) and the reasons for using this approach
are outlined there too. However, for a TV-box (or SBC) the simplest method to
obtain a working (grub bootable) image (on SD/USB) of Ubuntu desktop for ARM64
is to start with the official Ubuntu image for the Raspberry Pi and convert it.
The conversion process essentially amounts to replacing the kernel and this can
be done when running another ARM64 image on the TV-box. The result of the
conversion is an image that can be booted with `u-root-bootdisk` or
`petit-bootdisk`.

## Scope

By following the steps here you will be able to convert a standard Ubuntu
desktop image (e.g. Jammy) for Raspberry Pi into one that is bootable with grub
instead of with the installed u-boot files.
The crucial step in the conversion is to install new kernel that can boot on a
TV-box but also to remove the package flash kernel which will otherwise
interfere with the new kernel.
Once these two tasks are accomplished, the image will become a fully functional
generic ARM64 generic desktop image, without the need for further installation
of packages or adaption (except removal of some remnants of the raspi image).
Since we only replace the kernel on the image the risk of ending up with a non
bootable image are also drastically reduced:
As long as kernel, initramfs and grub.cfg files are in place and functional,
the image will boot.

## Prerequisites

We assume that the user already has a running ARM64 Linux image on the host
machine (e.g. Ubunto Server command line environment or Fedora desktop) and has
downloaded and burned/flashed to SD/USB a recent Ubuntu desktop image for
Raspberry Pi (e.g. `ubuntu-22.04-preinstalled-desktop-arm64+raspi.img.xz` from
[cdimage.ubuntu.com](http://cdimage.ubuntu.com/)).
We further assume that the directory `/mnt` is empty on the host machine and
can be used as mount point for the Raspberry Pi image.

## Steps for conversion

- On the host machine, insert the Raspberry Pi desktop SD/USB and determine
  the device descriptors for its two partitions (i.e. determine what X below
  is, e.g. using `lsblk`)
  
  `/dev/sdX1` labeled "system-boot" (contains u-boot files; will be obsolete)
  `/dev/sdX2` labeled "writable"    (contains the root file system)

- Make sure that these two partitions are not auto-mounted, for instance by
  some desktop auto-mount daemon/service. (The two partitions should be
  visible in a file manager file system overview pane (i.e. not ejected) but
  not *mounted*.) (In a command line environment this can be determined by
  watching the output of the command `lsblk` and then pissbly apply `umount`.)

- Become root on the host machine:

  `$ sudo su`

- Mount (manually) the partition labeled "writable" (`/dev/sdX2`) on `/mnt`:

  `# mount /dev/sdX2 /mnt`

- Enter a chroot jail on /mnt:

  `# chroot /mnt`

- Make sure that domain name resolution works from inside the jail:

  `# rm /etc/resolv.conf`

  `# echo "nameserver 8.8.8.8 >/etc/resolv.conf"`

- Update the package list in the jail:

  `# apt update`

- Remove the flash-kernel package (and all of its configuration files):

  `# apt purge flash-kernel`

- Install the new kernel:

  `# apt install linux-image-generic`
  
  (There may be warnings, or even errors, but they are not critical.
   We are in a chroot jail and outside file systems etc. are not visible.)

- Remove the Raspberry Pi kernel:

  `# apt purge linux-image-raspi`
  
  (Again, there may be warnings but they are not critical.)

- Create up a temporary grub file (mostly for first boot with new kernel):
  Make a grub.cfg file at `/boot/grub/grub.cfg` (as seen from inside the jail;
  from outside, this location would be `/mnt/boot/grub/grub.cfg`).
  The grub.cfg file should have one single menu entry like so:
  
```menuentry "Ubuntu Jammy (kernel 5.15.0-43)" {
  
    linux /boot/vmlinuz-5.15.0-43-generic root=LABEL=writable 
 
    initrd /boot/initrd.img-5.15.0-43-generic
 
  }
```

- Check that the names of kernel and initramfs in grub.cfg actually match
  what you have in `/boot` in chroot jail (i.e. in `/mnt/boot` from outside).
  (Check that the kernel file vmlinuz-\*-generic and initramfs file
  initrd-\*-generic really exist in `/boot` (`/mnt/boot`).)

- Remove the temporary resolver file and restore the symlink:

  `# rm /etc/resolv.conf`

  `# ln -s /var/run/systemd/resolve/resolv.conf /etc/resolv.conf`

- Exit the chroot jail:

  `# exit`

- Unmount the partition labeled "writable":

  `# umount /mnt`

- Reboot into the new Ubuntu Jammy and continue any customization from there.
  A lot of packages will be upgraded during initial setup and the initramfs
  will then be rebuilt several times. This will also trigger grub updates and
  from this point onward grub should be able to automagically create correct
  (advanced) grub files in `/boot/grub/grub.cfg` Finally, it can be good to
  search for any installed remaining "raspi" packages and purge these with apt.
