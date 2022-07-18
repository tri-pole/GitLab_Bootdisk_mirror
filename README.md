# bootdisk

In this repo you can find information relating to bootdisks for TV-boxes/SBCs
based on the ARM64 architecture.
With these bootdisks you can boot many ("generic") ARM64 Linux images with
UEFI+grub from major distributions such as Fedora 36, Ubuntu (e.g. Jammy),
Debian (e.g. Bullseye) and openSuse (Leap 15.4 and Tumbleweed).
A good use case for TV-boxes is to have the bootdisk installed on SD and have
several Linux distros installed on USBs to choose from.
The built in menu function of `u-root` on the bootdisk can then be used to
select boot target during boot.

General info about the bootdisk(s) `u-root-bootdisk` can be found in the file
README_u-root-bootdisk.md. The other README files contain information specific
to different install methods or distros.

There is also a script `debuntu_inst.bash` that can be used to automate the
procedure of installing Ubuntu or Debian for ARM64 to a USB or SD by using
debootstrap from e.g. a running Ubuntu Server live iso image. Alternatively,
the script can produce a compressed image file. The workaround with a script
is needed for many TV-boxes/SBSc since both the Ubuntu and Debian installers
for ARM64 currently have bugs which prevent them from working correctly on
these devices.
