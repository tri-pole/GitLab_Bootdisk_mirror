# Change Log

Changelog for u-root-bootdisk, u-root-bootdisk-nc, petit-bootdisk and
petit-bootdisk-nc

# u-root-bootdisk:

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

# petit-bootdisk-nc

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

# debuntu_inst.bash:

## [v0.12] - 22-07-18

### Added
 - Possibility to generate a compressed disk image as install target.

### Changed
 - Order of arguments for running the script.
 
## [v0.1] - 22-07-15

### Added
 - First commit.
