# bootdisk

This repo contains information relating to bootdisks for TV-boxes/SBCs based
on the ARM64 architecture.
With these bootdisks you can e.g. boot many ("generic") ARM64 Linux images with
UEFI+grub from major distributions such as Fedora 36, Ubuntu (e.g. Jammy),
Debian (e.g. Bullseye) and openSuse (Leap 15.4 and Tumbleweed).
A good use case for TV-boxes is to have the bootdisk installed on SD and have
several Linux distros installed on USBs to choose from.

All the bootdisks employ a chainloading mechanism based on the Linux
`kexec()` system call and the bootdisks come in two variants; one pair of
disks based on the `u-root` boot loader and another pair based on the
`Petitboot` boot loader. The disks are named after the chainloader.

General info about the bootdisks `u-root-bootdisk` and `petit-bootdisk` can
can be found in the README files with associated names.
The other README files contain information specific to different install
methods or distros.
Instructions for recreating/adapting the bootdisks can be found in the file
README_diy-bootdisk.md

There is also a script `debuntu_inst.bash` that can be used to automate the
procedure of installing Ubuntu or Debian for ARM64 to a USB or SD by using
debootstrap from e.g. a running Ubuntu Server live iso image. Alternatively,
the script can produce a compressed image file. The workaround with a script
is needed for many TV-boxes/SBSc since both the Ubuntu and Debian installers
for ARM64 currently have bugs which prevent them from working correctly on
these devices.
A working Ubuntu desktop image for a TV-box can also easily be obtained by
a simple conversion procedure starting with a Raspberry Pi image, see the
associated README file.
