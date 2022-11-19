# Change Log

Changelog for u-root-bootdisk, u-root-bootdisk-nc, petit-bootdisk and
petit-bootdisk-nc

# u-root-bootdisk:

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

# debuntu_dbstrap.bash:

## [v0.11] 22-10-10

### Changed
 - Better sources.list for Debian.

## [v0.1] 22-10-09

### Added
 - First commit.

# debuntu_inst.bash:

## [v0.12] - 22-07-18

### Added
 - Possibility to generate a compressed disk image as install target.

### Changed
 - Order of arguments for running the script.
 
## [v0.1] - 22-07-15

### Added
 - First commit.

# ubuntu_mkimg.bash:

## [v0.23] 22-11-19

### Added
 - More Ubuntu editions/releases.

## [v0.22] 22-11-08

### Added
 - Possibility to use locally provided kernel packages.

## [v0.20] 22-11-07

### Changed
 - Bumbed version to v0.20

## [v0.19] 22-11-02

### Added
 - Some more info e.g. in READMEs.
 
## [v0.18] 22-10-09

### Added
 - Now installs pkg. linux-firmware and cmd. sudo per default.

### Changed
 - Bugfix (downloaded u-boot.bins).

## [v0.17] 22-09-30

### Added
 - Can now also generate image for Kinetic (and Jammy, Focal).

## [v0.16] 22-09-24

### Changed
 - Bug fixes, code refactoring.

## [v0.15] 22-09-22

### Changed
 - Bug fixes, code refactoring.

## [v0.14] 22-09-21

### Added
 - Scripts (in /usr/local/bin) for making grub.cfg and sound setup.

### Changed
 - NetworkManager instead of ifupdown.
 - Code refactoring.

## [v0.12] 22-09-19

### Added
 - Virtualization to enable execution ("cross-scripting") also on x86_64/amd64.

## [v0.1] 22-09-18

### Added
 - First commit.

# archlnx_mkimg.bash:

## [v0.1] 22-10-16

### Added
 - First commit.
