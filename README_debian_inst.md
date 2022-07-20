# Debian install

## Background

The Debian installer for ARM64 (e.g. on the netinst iso) currently does not
produce console output to HDMI on certain SBC/TV-boxes, such as the Ugoos
Am6 plus (Amlogic s922x). (The installer can be booted, and cleanly shutdown
by issuing `Ctrl-Al-Del`, but there is no visible output, on any of the virtual
terminals.)

The present writeup describes a workaround to this problem and shows how to do
an install of a base system of Debian 11 for ARM64 on e.g. a USB stick, which
can then booted for instance with `u-root-bootdisk` (or any other boot
mechanism that relies only on a grub.cfg file).
Our method is a (slight) variant of the method we have devised for installing
Ubuntu (cf. the associated README) and uses the Debian tool
[debootstrap](https://www.debian.org/releases/stable/arm64/apds03.en.html)
to install the rootfs.
(This tool is available in the repositories for the Ubuntu Server installation
image.)

## Scope

By following these notes you will be able to install and get up and running
a base Debian 11 system, without graphics.
However, it is a simple matter to add a graphics environment to the
installation by using e.g. `aptitude` (see below).
The method has been tested on a Ugoos AM6 plus.

The install method here should more generally be applicable to many Debian
like Linux distributions. One such example is Devuan, for which we have
explicitly outlined the differences in installation steps at the end of this
document.

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
  remote machine with `ssh root@IP`) can be seen e.g. by doing `# ip a`.

### (3) Installation of rootfs

From now on we assume that you have a root prompt on the Ubuntu Server
installer machine, either locally or via remote ssh login.

All operations from now on are done at this root prompt.

Install `debootstrap` and mount the root partition and boot partition
(under `/mnt` and `/mnt/boot` on the installer machine, respectively):

- `# apt install debootstrap`

- `# mount /dev/sdX3 /mnt`

- `# debootstrap --arch arm64 bullseye /mnt http://ftp.us.debian.org/debian`

- `# mount /dev/sdX1 /mnt/boot`

### (4) Set up some configuration files

Edit the file `/mnt/etc/network/interfaces` to read e.g. like this:

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

Add the security updates to the apt sources:

- Add the line
  `deb http://security.debian.org/ bullseye-security main`
  to /mnt/etc/apt/sources.list

### (5) Enter the chroot jail and install the kernel

Now it is time to enter into the chroot jail in which some further install
commands are executed:

- `# for f in /sys /proc /dev ; do mount --rbind $f /mnt/$f ; done ; chroot /mnt`

- `# apt update && apt install linux-{headers,image}-arm64`

- `# apt install locales`

- `# apt install console-setup`

- `# apt install ntp sudo`

Add an ordinary user (e.g. memyselfandi) and add this user to the `adm` and
`sudo` groups:

`# adduser memyselfandi`

`# usermod -a -G adm,sudo memyselfandi`

If you want to have the root user enabled on the target image then also do:

- `# passwd`

### (6) Exit the chroot jail and set up a grub.cfg file

Exit the chroot jail:

- `# exit`

If you are running this install from a continuously running host (i.e. not
Ubuntu Server iso) then the following two steps may be useful:

- `# mount --make-rprivate /mnt`
- `# for f in /sys /proc /dev ; do umount -R /mnt/$f ; done`

Setup a basic grub configuration:

- Create a file `/mnt/boot/grub/grub.cfg` with the following contents (recall
how `uuid-partition3` was defined above)

```
menuentry "Debian 5.10.0-16" {

# devicetree /meson-g12b-ugoos-am6.dtb
linux /vmlinuz-5.10.0-16-arm64 root=UUID=uuid-partition3
initrd /initrd.img-5.10.0-16-arm64

}
```

Note: The actual numbers of the kernel and initrd might be different on your
install (check what they are in `/mnt/boot`).

### (7) Reboot

It is time to finish the install and reboot:

- `# shutdown -r now`

The so installed Debian image should now be bootable with the grub boot entry
label `Debian 5.10.0-16` created above and after booting it you should arrive
at a text console prompt from which you can login as e.g. user memyselfandi.

### Post install 

To set a new hostname, simply do

`$ sudo echo myhostname > /etc/hostname`

To install a desktop environment one can use `aptitude`

`$ sudo apt install aptitude`

and then from Tasks -> End user in `aptitude` menu select the appropriate task.

If grub is not installed by default, this is easily fixed by running e.g.

`$ sudo apt install grub-common`

Then you grub.cfg will be updated each time the kernel configuration(s) change.

To get sound working it is necessary on many TV-boxes to run (as user) the
script `g12_sound.sh` which can be found e.g.
[here.](https://gitlab.manjaro.org/manjaro-arm/packages/community/oc4-post-install/-/blob/master/g12_sound.sh)

Note: The grub file that was set up in step (6) above only works for the kernel
installed in step (5) and if the kernel name is different (e.g. because of a
later kernel upgrade) the grub file needs to be adjusted accordingly.
Also, we have not set up a dtb file in grub.cfg (only a placeholder) since
when booting with `u-root-bootdisk` the dtb used by `u-root` is inherited.
In general, however, a dtb must be present on the install target disk and
specified in grub.cfg.

## Devuan install

The installation procedure for Devuan is virtually identical to that of Debian,
with the following small modifications, at three of the steps above.

(1) The step `apt install debootstrap` above is replaced by the following four
items:

- `# wget https://pkgmaster.devuan.org/devuan/pool/main/d/devuan-keyring/devuan-keyring_2017.10.03_all.deb`
- `# wget https://pkgmaster.devuan.org/devuan/pool/main/d/debootstrap/debootstrap_1.0.114+devuan5_all.deb`
- `# dpkg -i devuan-keyring_2017.10.03_all.deb`
- `# dpkg -i debootstrap_1.0.114+devuan5_all.deb`

(2) In the step above where
  `deb http://security.debian.org/ bullseye-security main`
  is added to /mnt/etc/apt/sources.list the repo should be replaced by
  `deb http://deb.devuan.org/merged chimaera-security main`

  For access to newer kernels (e.g. to get sound working) you might want to
  add also the unstable repo like so
  `deb http://deb.devuan.org/merged unstable main`

(3) Finally, you also have to edit the entries in the grub.cfg file according
to what you have in /boot on the install target disk (mounted as /mnt/boot).
