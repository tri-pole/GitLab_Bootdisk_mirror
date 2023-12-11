# Linux images and QEMU

The [QEMU](https://www.qemu.org) emulator suite can be used in several
ways to aid in the creation of Linux ARM64 images for TV-boxes/SBCs.
One important application is to directly create bootable ARM64 Linux
images on SD/USB (or image file) by running an ARM64 Linux installer
in QEMU on a host of a differerent architecture, such as x86_64.
An advantage with this method is that the possible problems involved
with running scripts on the host (incl. resolving dependencies) are
avoided.
Instead, the native installer for the ARM64 Linux distribution in
question can be run unmodified in QEMU on the host to provide a
prestine install directly on the SD/USB (or image file).
The result will typically be a UEFI Linux image that can be booted e.g.
with Petitboot/u-root (e.g. using a bootdisk).

### Installer in QEMU

The method we describe here is very a bare-bones way to run the text
based version of an installer, e.g. Debian, in a terminal window on
the host.
Thus, a certain familiarity with "classical" Linux installers is
helpful.

#### Prerequisites

The prerequisites on the host are small; a working QEMU system install
(the package qemu-system on Ubuntu), the package containing
qemu-system-aarch64 (the package qemu-system-arm) and the package
containing UEFI for QEMU aarch64 (qemu-efi-aarch64).

We describe first the method to install to SD/USB and the modifications
needed to install to image file are given in the remarks section below.

It is recommended to wipe clean the install medium SD/USB prior to
install (e.g. using `dd` and `/dev/zero`) so that the installer is not
affected by any remnants of previous activity on the medium.

#### Install

Assuming that we want to install Debian testing (using the iso file for
the installer) onto a (clean) USB stick appearing as `/dev/sdX` on the
host, the command to run (at least on Linux x86_64) is the following:

```
  sudo qemu-system-aarch64 -machine virt -m 1024 -cpu cortex-a57 -smp 2 \
  -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
  -drive file=debian-testing-arm64-netinst.iso,index=0,media=cdrom \
  -drive file=/dev/sdX,format=raw,media=disk \
  -nographic -no-reboot
```

This will start QEMU in a terminal window where the Debian installer
will automatically start.
A virtual network card will automatically be created in QEMU and the
SD/USB stick will appear as a "virtual disk".
The terminal window on the host appears to the installer as a serial
console (e.g. `ttyAMA0`).

The QEMU session running in the terminal window can be controlled by
entering commands in the terminal; e.g. use Ctrl-a,h (or Ctrl-a,Ctrl-h)
for help on QEMU commands and Ctrl-a,x or (Ctrl-a,Ctrl-x) to shut down
QEMU.
(If you have aborted QEMU you may need to issue the command `reset`
inside the host terminal window to get it back to default settings.)

The installation procedure is the same as for an ordinary install onto
disk. There will be only one disk visible/accessible inside QEMU; the
SD/USB. Use standard partitioning, i.e. no LVM.

When the installation is finished the installer will try to reboot into
the installed image but this is prevented by the `-no-reboot` switch on
the QEMU command line above.

The command line parameters for QEMU memory size (`-m`) and number of
cores (`-smp`) may have to be adapted for other installer images.
Also, the CPU architecture (`-cpu`) used during install may need to be
changed depending on the install target.

#### Post install

The installation can be tested in QEMU on the host by running the
install command above but modified by removing the line containing the
reference to the Debian installer iso file (as a cdrom disk).
Since the QEMU terminal window environment is then text-only the Linux
image will come up in text mode (in a serial console mode).

During the install the package quemu-guest-agent may be installed
(since the installer detects the QEMU environment) and this package
can be removed when the image is run natively on a TV-box/SBC.

### Remarks

The method described here has been tested with the iso installer images
for Debian Testing (Trixie), Devuan (Daedalus), Ubuntu Server (22.04.3)
and Fedora Server (39) but should be applicable to many other
distributions.

#### Emulation environment

The values of the memory and cores parameters needed in the QEMU
command line above can vary between distributions; for Debian/Devuan
the values `-m 512`, `-smp 2` work just fine but for Ubuntu the values
`-m 1024`, `-smp 4` seems to be needed.
For Fedora, even more memory (e.g. `-m 2048`) may be needed.

#### Install to image file

It is easy to adapt the installation procedure above to the case of
installing to an image file, which can later be flashed/burned to an SD/USB.
To do this, locate the line above in the `qemu-system-aarch64` command
where `/dev/sdX` is specified and replace `/dev/sdX` in that line with
`/dev/loopX` where `/dev/loopX` is a loop device for an (empty) image file.

An empty image file can be created e.g. with the command

```
  dd if=/dev/zero of=imgfile.img bs=1M count=6000 status=progress
```

which will create an image file named `imgfile.img` of size 6G.
The image file can then be associated with loop device with the command

```
  sudo losetup -fP --show imgfile.img
```

which will set up a loop device and assign a number to it, e.g.
`/dev/loop2`. (So in this case `/dev/loopX` in the modified
`-drive` line above would be `/dev/loop2`.)

After the install the image file installation can be tested by booting
it analogously as for the SD/USB install; by removng the `cdrom`
line from the `qemu-system-aarch64` command line.

Finally, when the loop device is not needed any longer (i.e. when
the image file is not to be read into or booted) it can be removed
by issuing the command

```
  sudo losetup -d /dev/loopX
```

where `/dev/loopX` is replaced for the loop device name actually
used (e.g. `/dev/loop2`).

#### Graphical install

It is of course also possible to run QEMU with graphics and then use
the graphical installers that are available for the various distros.
However, the conditions for running different types of graphical
displays with QEMU is very (host) platform dependent and therefore we
have not discussed that here.

If a graphical installation procedure is really needed the best option
is probably to use libvirt and virt-manager, and set up a virtual
machine with disk passthrough for the install target SD/USB,
analogously as for QEMU described here.
