# Using a bootdisk to boot a Linux installer disk

A good use case for the bootdisks is booting of an installer for another
Linux distro. (As mentioned in the [`README.md`](README.md) file, there is a
greater chance that this will work as a way to install a UEFI ARM64 Linux
distro than using a live image, at least according to our experience.)
As an example, we outline here how to make a small installer disk for openSuse
(Tumbleweed or Leap 15.4).

The install disk is very simple and contains only a small FAT32 partition with
a few files on it; an installer kernel and initrd, a `grub.cfg` file (and for
future compatibility a dtb file; it is not used currently by the bootloaders
on the bootdisks).

Scope
-----

The notes here pertain to openSuse but can be adapted to other distros as well.
(However, note that your mileage will vary with other installers: For instance,
the Debian installer will (apparently) boot but the HDMI display output will
not work, at least not on my Ugoos Am6 plus, so console access will have to be
set up some other way.)

Outline of the disk
-------------------

The file tree structure of the small boot partition (e.g. 200M) on the install
disk is as follows

/boot/linux
/boot/initrd
/boot/grub/grub.cfg
/boot/dtbfile.dtb

where linux and initrd is the kernel and initrd files for the installer, and
dtbfile.dtb is a dtb file matching your box.

For openSuse, the files linux and initrd are taken from here
[download.opensuse.org](https://download.opensuse.org/ports/aarch64/factory/repo/oss/boot/aarch64)

and the `grub.cfg` file can look like this

```
menuentry "openSuse Netinst (Tumbleweed)" {

devicetree /boot/dtbfile.dtb
linux /boot/linux install=http://download.opensuse.org/ports/aarch64/factory/repo/oss
initrd /boot/initrd

}

menuentry "openSuse Netinst (Leap 15.4)" {

devicetree /boot/dtbfile.dtb
linux /boot/linux install=http://download.opensuse.org/ports/aarch64/distribution/leap/15.4/repo/oss
initrd /boot/initrd

}
```

Notes for openSuse install
--------------------------

The following has been tried on a Ugoos AM6 plus with u-root-bootdisk-0v25
to install openSuse Tumbleweed server and KDE plasma (see also notes at the
end about network setup):

- Boot the disk (openSuse Netinst).
Be patient! (It can take a couple of mins for the installer to fully load.)

- You will be presented with a screen where it says:
"To use the selected repository a matching boot image is needed. Download it
and restart?"

Choose "yes" here: The image will be downloaded into memory, a new kernel and
initrd will be extracted and a kexec jump to the new kernel+init will be
performed (I think). (Be patient also here.).

- After a while, a couple of mins or so, you will be presented with the newly
(re-)booted installer. It is a standard (but nice) graphical installer.

- Choose language and keyboard layout.

- You can choose to activate and use online repositories (other than those in
the downloaded, and rebooted into, image). I chose "yes", but note this: There
may be only a marginal benefit with this (since the just downloaded and
rebooted installer image is recent) and a potential (time) risk: If the
openSuse servers are busy, choosing online repos might delay the installation
since it may temporarily stall several times (but auto resume until finished).

- You will then be asked to choose "System role" (desktop type, server etc.)

- Now you come to "Suggested Partitioning" (this is important).
At the bottom of the page choose "Guided setup".

You will be presented with a screen where you can tick mark all disks and
partitions that will be considered for the rest of the install.
Make sure that there is only one tick mark; at the USB from which you have
already booted. (I used the remaining part of this USB as install target.)

- On the next screen you will be presented with the USB that you just chose
and asked how to proceed with existing Linux partitions on it. I chose
"Do not modify".

- Next, you will be asked if you want to use LVM (logical volume management).
I did not choose this (I ticked nothing).

- Now you come to a screen labeled "File System Options".
Here, choose ext4 for the root partition and let the installer propose a swap
partition (i.e leave this option ticked).

- After this, you will be shown a summary labeled "Suggested Partitioning".
If you don't like something here, go back and redo. Otherwise, click "Next".

- You will now choose clock and time zone.

- Next you will create local user(s).

- The next installer screen is "Installation setup".
Here are a couple of things to note: Unselect "Secure boot" and unselect
"update nvram". Choose whether you want the firewall enabled and if you want
the ssh service enabled. Also, choose your network configuration.
After these choices are made, it is time to hit the "Install" button.

- Installation will take a while but the progress indicators are good.

- Near the end of the installation (about 93%) you will likely encounter an
error message bout the installer being unable to install the EFI directory.
This is harmless for us since we don't use EFI (but uroot+grub) to boot the
finished install. Just hit "Ok" to continue.

- The installer will then finish and reboot automatically. Enjoy.

- Postscript: After the install, the first installer partition (FAT32) is
no longer needed and can be discarded/wiped or reused for something else.

- Note: If you encounter problems with the automatic network detection or
 DHCP setup you can force the installer to ask for static IP settings by
 adding to the kernel command line (in `grub.cfg`) the following
 
` netsetup=hostip,netmask,gateway,nameserver`

More information about installer kernel arguments and the install process can
be found at [doc.opensuse.org](https://doc.opensuse.org/documentation/leap/startup/single-html/book-startup/#ch)
and more information about network install is available at
[openSuse Wiki](https://en.opensuse.org/SDB:Network_installation#Media-free_network_installation).
