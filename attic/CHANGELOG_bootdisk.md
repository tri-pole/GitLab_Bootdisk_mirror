# Old changelog for bootdisks (discontinued)

This is the old changelog for the complete (now discontinued) bootdisks for
ARM64 with `Petitboot` or `u-root`. These bootdisks were superseded by
`multi-bootdisk` which is discussed in `README_petit-bootdisk.md` and
`README_u-root-bootdisk.md`. (No changelog was kept for `multi-bootdisk`.)

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
