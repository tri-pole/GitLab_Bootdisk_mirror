# Changelog

This is the changelog for the codes in the `Bootdisk` repository.
It covers all tools/codes for building Linux images and and the script
`petitboot_mkinitrd.bash` for building the initramfs for `Petitboot`.

__Bootdisks:__ We no longer provide tracked releases of complete bootdisks
with `Petitboot` or `u-root`. (The old changelog is at the end of this file.)
These bootdisks have been superseded by `multi-bootdisk` which is discussed
`README_petit-bootdisk.md` and `README_u-root-bootdisk.md` (where also a
download location is provided).

__ARM64 Linux images:__ The scripts and README files for creation of Linux
images for ARM64 are now obsoleted and moved to the
[`attic area`](attic/Creating_Linux_images_ARM64).

# debuntu_dbstrap_riscv64.bash

## [v0.13] 24-12-10

### Changed
 - Use PARTUUID in extlinux.conf and grub.cfg
 - Various fixes and improvements.

## [v0.12] 24-12-06

### Added
 - Automatic update of extlinux.conf

### Changed
 - Boot partition now mounted directly under /boot
 - Refactoring, partial rewrite and many small fixes.

## [v0.1] 24-11-30

### Added
 - First commit.

# petitboot_mkinitrd.bash:

## [v0.13] 24-11-20

### Added
 - Support for RISCV64.

## [v0.11] 23-10-12

### Added
 - Option to build smaller initrd.

## [v0.1] 23-10-08

### Added
 - First commit.

# arm64_kbuild.bash:

## [v0.13] 24-06-02

### Added
 - Allow for kernel with 2 digit version number.

### Changed
 - Updated paths to rootfs.

## [v0.12] 23-11-12

### Changed
 - Bump version.

## [v0.11] 23-08-27

### Changed
 - Bump version.

## [v0.1] 23-03-20

### Added
 - First commit.

# Discontinued:

# u-root-bootdisk:

## [v0.33] - 23-03-14

### Changed
 - Updated u-root to v0.11.0

## [v0.32] - 22-10-22

### Changed
 - Updated u-root to v0.10.0

## [v0.30] - 22-10-12

### Added
 - Autostart of boot menu.

### Changed
 - Raplaced 5.17 kernel with 5.4 kernel.

## [v0.28] - 22-08-29

### Added
 - New initramfs initramfs-cb-v0.9.0.cpio.gz
 - New u-boot.bin files (in dir u-boot-3pole).

### Changed
 - dtbs are now from Manjaro (kernel 5.19.1-2-MANJARO-ARM).
 - Updated README

## [v0.26] - 22-07-09

### Changed
 - README, aml_autoscript, s905_autoscript

### Removed
 - Three u-boot.ext files.

# u-root-bootdisk-nc:

## [v0.35] - 23-03-14

### Changed
 - Updated u-root to v0.11.0

## [v0.34] - 22-11-04

### Added
 - Alternative (optional) bootscripts.

## [v0.33] - 22-10-30

### Changed
 - New boot scripts and changed to uImage.

## [v0.32] - 22-10-22

### Changed
 - Updated u-root to v0.10.0

## [v0.30] - 22-10-12

### Added
 - Autostart of boot menu (after 3s delay from kernel boot).

## [v0.28-2] - 22-09-14

### Changed
 - The disk contents is moved over to a tarball (since no special disk is
   required, only a single FAT partition large enough to hold the files).

## [v0.28] - 22-08-29

### Changed
 - New initramfs built from initramfs-cb-v0.9.0.cpio.gz
 - New bootloader (built from u-boot-amlogic-220809 w/ GT King pro defconfig).
 - dtbs are now from Manjaro (kernel 5.19.1-2-MANJARO-ARM).
 - Reverted to kernel vmlinuz-5.4.209-ophub-kexec-fs+

## [v0.26] - 22-07-09

### Changed
 - README, aml_autoscript, s905_autoscript, boot.scr

### Removed
 - One misplaced bmp file.

# petit-bootdisk:

## [v0.23] - 22-09-27

### Added
 - Some e2fstools (badblocks,dumpe2fs,e2fsck,mke2fs,resize2fs,tune2fs).

### Changed
 - The disk contents is moved over to a tarball.

## [v0.22-1] - 22-09-30

### Changed
 - Rewrite of README file.

## [v0.22] - 22-08-29

### Added
 - Search also for boot configuration in "/EFI/BOOT/grub.cfg"
 - Search also for boot configurations on media type OPTICAL.
 - Some more u-boot.bin

### Changed
 - Cosmetics in the Petitboot UI

## [v0.2] - 22-07-31

### Added
 - Possibility to disable network access (and netbooting).

## [v0.15] - 22-07-26
 - First upload.

# petit-bootdisk-nc:

## [v0.26] - 22-11-04

### Added
 - Alternative (optional) bootscripts.

## [v0.25] - 22-10-30

### Changed
 - New boot scripts and changed to uImage.

## [v0.23] - 22-09-27

### Added
 - Some e2fstools (badblocks,dumpe2fs,e2fsck,mke2fs,resize2fs,tune2fs).

## [v0.22-2] - 22-09-14

### Changed
 - The disk contents is moved over to a tarball (since no special disk is
   required, only a single FAT partition large enough to hold the files).

## [v0.22] - 22-08-30

 - First commit of full bootdisk, same features as petit-bootdisk v0.28
 - Same bootloader as u-root-bootdisk-nc v0.28

## [v0.2] - 22-07-31

### Added
 - Possibility to disable network access (and netbooting).

## [v0.15] - 22-07-26
 - First upload (of initramfs only).
