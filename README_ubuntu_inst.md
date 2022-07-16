# Ubuntu install

## Background

The Ubuntu installer for ARM64 (on the Ubuntu Server image and the other live
images) currently has a bug which prevents a clean install on some systems, for
instance on some arm SBCs/TV-boxes (which otherwise can run the Ubuntu images).
This bug is related to the package flash-kernel and the creation of the
initramfs, and manifests itself by the installation aborting near the end
which leaves the installed image in a non bootable state.
(A simple search for `"flash-kernel install bug"` will provide more info.)

The present writeup describes a workaround to this bug and shows how to do a
clean install of Ubuntu Server ARM64 to e.g. a USB stick, which can then be
booted for instance with `u-root-bootdisk` (or any other boot mechanism that
relies only on a grub.cfg file).
Our method relies on the Ubuntu installer iso but uses the iso image only to
get up to a running state of the installer from which a Ubuntu rootfs from
[Ubuntu Base](https://wiki.ubuntu.com/Base) can be straightforwardly installed.

## Scope

These notes use Ubuntu Server as an example but the method should work to
install (perhaps with minor modifications) any other Ubuntu ARM64 flavor,
provided a rootfs tarball is available.
An Ubuntu server image can moreover easily be upgraded to a desktop image
using e.g. via `apt` (e.g. `apt install ubuntu-desktop`).
The method has been tested on a Ugoos AM6 plus (Amlogic s922x SoC).

## Prerequisites

We assume that the user has available the Ubuntu Server installer iso for
ARM64 copied (e.g. with the Linux `dd` command) to a USB stick. (A good
source for such images is [cdimage.ubuntu.com](http://cdimage.ubuntu.com/).)

It is also good to have the install target USB stick formatted in advance:

Here, we are going to assume that the install target USB stick is 32GB (28.7G
usable) and we let the Ubuntu system occupy the entire stick. (With
`u-root-bootdisk` as boot mechanism, it is convenient to have `u-root-bootdisk`
on a SD and then attach to the USB ports, or a USB hub, the various Linux
images to be booted.)

Our partition layout for the install target USB is the following (with
partitions created by e.g. `fdisk` for MBR or `gdisk` for GPT, and file system
created with e.g. `mkfs.ext4` and `mkswap`):

```
/dev/sdX:

Partition 1 (/dev/sdX1): ext4 (MBR partition type 83), 600M  (for /boot)
Partition 2 (/dev/sdX2): swap (MBR partition type 82), 2G    (for swap part.)
Partition 3 (/dev/sdX3): ext4 (MBR partition type 83), 26.1G (for /)
```

The UUIDs of these partitions will be used later below so it is assumed that
the UUIDs have been listed (using e.g. the command `blkid`) and recorded.

For brevity, we are going use the following shorthand labels (in the obvious
notation) for the UUIDs of the three partitions:

```
uuid-partition1

uuid-partition2

uuid-partition3
```

## Steps for installation

The installation proceeds in seven steps, and require some typing (or
copy-pasting), but is inherently straightforward.

### (1) Start the installer

- Boot the Ubuntu Server installer iso image.

- Go through the first few steps of the installation; set installation
  language, set keyboard, set type of install, set up network and select
  Ubuntu archive mirror.
  Stop when you reach the partitioning (Guided storage configuration) screen.

- Switch to a virtual terminal, e.g. vt2 (by issuing `Alt-F2`).

- Give the command `$ sudo su` to become root user.

Necessary only if you use ssh remote login (see below) for the rest of the
install:

- Set the root password for the installer image by issuing the command
  `# passwd`

### (2) Optional: Enable ssh login from remote machine

In order to facilitate copying of long strings of characters (such as
commands and disk UUIDs) it is convenient to do the rest of the install
from a remote machine.
For this we need to enable ssh login on the machine running the Ubuntu Server
installer image:

- Edit the file `/etc/ssh/sshd_config` and enable the following

```
  PermitRootLogin yes
  PasswordAuthentication yes
```

- Check that the edit was clean by doing `# ssh -t` (no news is good news).

- Restart the ssh server with `# systemctl restart ssh`

- The IP of the installer system network interface `eth0` (for ssh login from
  remote machine with `ssh root@IP`) can be seen e.g. by doing `# ip a`

### (3) Installation of rootfs

From now on we assume that you have a root prompt on the Ubuntu Server
installer machine, either locally or via remote ssh login.

All operations from now on are done at this root prompt.

Download and extract the rootfs, and mount the root partition and boot
partition (under `/mnt` and `/mnt/boot` on the installer machine,
respectively):

- `# cd /tmp`

- `# wget https://cdimage.ubuntu.com/ubuntu-base/jammy/daily/current/jammy-base-arm64.tar.gz`

- `# mount /dev/sdX3 /mnt`

- `# cd /mnt`

- `# tar -xf /tmp/jammy-base-arm64.tar.gz`

- `# mount /dev/sdX1 /mnt/boot`

(Variations on a theme: The rootfs can also be put in place by using
`debootstrap`; see the README file for Debian installation.)

### (4) Set up some configuration files

We must prevent the flash-kernel package from being installed:

- Open an editor (e.g. nano) and create a file
  `/mnt/etc/apt/preferences.d/no-flash-kernel` with the following contents

```
Package: flash-kernel
Pin: release *
Pin-Priority: -1
```

Prepare for network setup:

- Edit the file `/mnt/etc/resolv.conf` to taste, e.g. like so

```
nameserver 192.168.0.1
nameserver 8.8.8.8
```

Create a basic network interface setup file

- `# mkdir /mnt/etc/network`

and create a file `/mnt/etc/network/interfaces` with the following contents:

```
allow-hotplug eth0
auto eth0
iface eth0 inet dhcp
```

Set up an fstab file for the target image:

- Edit the file `/mnt/etc/fstab` to read

```
UUID=uuid-partition3  /      ext4  errors=remount-ro  0  1
UUID=uuid-partition1  /boot  ext4  defaults  0  2
UUID=uuid-partition2  none   swap  sw  0  0
```

### (5) Enter the chroot jail and install the kernel

Now it is time to enter into the chroot jail in which some further install
commands are executed:

- `# for f in /sys /proc /dev ; do mount --rbind $f /mnt/$f ; done ; chroot /mnt`

- `# apt update && apt install linux-{headers,image}-generic`
  (this will also install a lot of grub-* components but not flash-kernel).

Install some more packages:

- `# apt install man-db apt-utils sudo nano ifupdown ssh`

Create an ordinary user (e.g. memyselfandi) and add this user to the `adm` and
`sudo` groups:

- `# adduser memyselfandi`

- `# usermod -a -G adm,sudo memyselfandi`

If you want to have the root user enabled on the target image then also do:

- `# passwd`

### (6) Exit the chroot jail and set up a grub.cfg file

Exit the chroot jail:

 - `# exit`

Setup a basic grub configuration:

- Create a file `/mnt/boot/grub/grub.cfg` with the following contents (recall
how `uuid-partition3` was defined above):

```
menuentry "Ubuntu 5.15.0-41" {

# devicetree /meson-g12b-ugoos-am6.dtb
linux /vmlinuz-5.15.0-41-generic root=UUID=uuid-partition3
initrd /initrd.img-5.15.0-41-generic

}
```

Note: The actual numbers of the kernel and initrd might be different on your
install (check what they are in `/mnt/boot`).

### (7) Reboot

It is time to finish the install and reboot:

- `# shutdown -r now`

The so installed Ubuntu Server image should now be bootable with the grub boot
entry label `Ubuntu 5.15.0-41` created above and after booting it you should
arrive at a text console prompt from which you can login as e.g. user
memyselfandi.

### Post install

The install set obtained by a default Ubuntu debootstrap is rather small and
therefore the first thing you might want to on a first login is to run the
command `unminimize`.
This will expand the set of installed packages to a more reasonable set for
general use.

To set a new hostname (permanently) do this

`$ sudo hostnamectl set-hostname myhostname`

To install a desktop environment one can use `aptitude`

`$ sudo apt install aptitude`

and then from Tasks -> End user in `aptitude` menu select the appropriate task.

Alternatively, the various desktop environments can be installed directly with
`apt`, for instance `apt install ubuntu-desktop` (for Gnome) or
`apt install mate-desktop` (for MATE).

Note: The grub file that was set up in step (6) above only works for the kernel
installed in step (5) and if the kernel name is different (e.g. because of a
later kernel upgrade) the grub file needs to be adjusted accordingly.
Also, we have not set up a dtb file in grub.cfg (only a placeholder) since
when booting with `u-root-bootdisk` the dtb used by `u-root` is inherited.
In general, however, a dtb must be present on the install target disk and
specified in grub.cfg.

