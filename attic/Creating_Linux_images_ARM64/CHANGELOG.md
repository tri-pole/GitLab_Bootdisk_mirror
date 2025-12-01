# Changelog

This is the changelog for the codes in the `Bootdisk` repository relating
to creation of Linux image for ARM64.
It covers all tools/codes for building Linux images and and the script
`petitboot_mkinitrd.bash` for building the initramfs for `Petitboot`.

# debuntu_dbstrap.bash:

## [v0.14] 25-12-01

### Changed
 - Adaptions for Debian Trixie

## [v0.13] 23-06-12

### Changed
 - Names of wired network interfaces and non-free repos.

## [v0.12] 22-11-22

### Changed
 - More available editions/releases.
 - Fixed sources.list for multiple eds./rels.

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

## [v0.26] 23-09-22

### Added
 - devicetree statement in grub.cfg

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

## [v0.14] 23-03-09
 - Possibility to use also Manjaro native kernel.

## [v0.13] 23-03-01

### Added
 - Possibility to generate Manjaro ARM images.

## [v0.1] 22-10-16

### Added
 - First commit.

# devuan_dbstrap.bash:

## [v0.1] 23-07-16

### Added
 - First commit.

# Discontinued:

# tridora_mkimg.bash:

## [v0.1] 23-06-25

### Added
 - First commit.
