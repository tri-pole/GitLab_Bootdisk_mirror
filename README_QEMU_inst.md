# Linux images and QEMU

The [QEMU](https://www.qemu.org) emulator suite can be used in several
ways to aid in the creation of Linux ARM64 images for TV-boxes/SBCs.
One important application is to directly create bootable ARM64 Linux
images on SD/USB by running an ARM64 Linux installer in QEMU on a host
of a differerent architecture, such as x86_64.
An advantage with this method is that the possible problems involved
with running scripts on the host (incl. resolving dependencies) are
avoided.
Instead, the native installer for the ARM64 Linux distribution in
question can be run unmodified in QEMU on the host to provide a
prestine install directly on the SD/USB.
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

It is recommended to wipe clean the install medium (SD/USB) prior to
install (e.g. using dd and /dev/zero) so that the installer is not
affected by any remnants of previous activity on the medium.

#### Install

Assuming that we want to install Debian testing (using the iso file for
the installer) onto a (clean) USB stick appearing as /dev/sdX on the
host, the command to run (at least on Linux x86_64) is the following:

```
  sudo qemu-system-aarch64 -machine virt -m 512 -cpu cortex-a57 -smp 2 \
  -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
  -drive file=debian-testing-arm64-netinst.iso,index=0,media=cdrom \
  -drive file=/dev/sdX,format=raw,media=disk \
  -nographic -no-reboot
```

This will start QEMU in a terminal window where the Debian installer
will automatically start.
(A virtual network card will automatically be created in QEMU and the
SD/USB stick will appear as a "virtual disk".)
The QEMU session can be controlled by entering commands in the terminal
window; e.g. use Ctrl-a,Ctrl-h for help on QEMU commands and
Ctrl-a,Ctrl-x to shut down QEMU.

The installation procedure is the sama as for an ordinary install onto
disk (and there will be only one disk visible/accessible inside QEMU;
the SD/USB.)
When the installation is finished the installer will try to reboot into
the installed image but this is prevented by the -no-reboot switch on
the QEMU command line above.

The command line parameters for QEMU memory size (-m) and number of
cores (-smp) may have to be adapted for other installer images.
Also, the CPU architecture (-cpu) usded during install may need to be
changed depending on the install target.

#### Post install

The installation can be tested in QEMU on the host by running the
install command above but modified by removing the line containing the
reference to the Debian installer iso file (as a cdrom disk).
Since the QEMU terminal window environment is then text-only the Linux
image will come up in text mode.

During the install the package quemu-guest-agent is installed (since
the installer detects the QEMU environment) and this package can be
removed when the image is run natively on a TV-box/SBC.
