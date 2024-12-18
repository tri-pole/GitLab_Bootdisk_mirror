# Changelog

This is the changelog for the codes in the `Bootdisk` repository.
It covers the tools/codes for building Linux images and and the scripts
`petitboot_mkinitrd_aarch64.bash` and `petitboot_mkinitrd_riscv64.bash` for
building the initramfs for `Petitboot`.

For changelogs of older material, see the `attic` area of the repo.

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

# petitboot_mkinitrd_riscv64.bash

## [0v.1] 24-12-18

### Added
 - First commit.

# petitboot_mkinitrd_aarch64.bash (renamed, was petitboot_mkinitrd.bash):

## [v0.14] 24-12-18

### Removed
 - Support for RISCV64 (moved to separate file).

### Changed
 - Renamed
 - Various small code updates.

## [v0.13] 24-11-20

### Added
 - Support for RISCV64.

## [v0.11] 23-10-12

### Added
 - Option to build smaller initrd.

## [v0.1] 23-10-08

### Added
 - First commit.

# riscv64_kbuild.bash:

## [v0.1] 24-11-19

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
