# Changelog

This is the changelog for the main codes in the `Bootdisk` repository.
It covers the scripts `petitboot_mkinitrd_{aarch,riscv}64.bash` for
building the initramfs for `Petitboot` as well as the scripts
`{arm,riscv}64_kbuild.bash` for building Linux kernels and the scripts
`debuntu_dbstrap_{aarch,riscv}64.bash` building Linux images.
(Some small helper scripts are not documented here; see inside the scripts.)
The author is Tripole unless otherwise noted.

# petitboot_mkinitrd_aarch64.bash

## [v0.21] 26-11-12

### Changed (Qwen3.8, some assistance by Tripole)
 - Reference rewrite to improve code quality:
 - Eliminated silent failures (missing files, failed downloads/patches, etc.).
 - Per-step exit code checks.
 - Global safety net w/ `set -Eeuo pipefail` + `shopt -s nullglob`
   and ERR trap (line number) with EXIT trap.
 - Clearer time stamping of results/dirs., no dir. collision.
 - Fixed autoupdate call bug (kexec-tools).
 - ARCH normalized parity with the riscv64 version (i.e. only necessary
   ARCH differences).

## [v0.19] 26-10-14

### Changed
 - Fixed bugs in invocation of remote (telnet) mode.
 - Fixed Petitboot compilation errors with newer ncurses (added patch set).
 - Style and comment cleanup.

## [v0.17] 26-02-10

### Changed
 - Rewrite of kexec wrapper.

## [v0.16] 26-01-11

### Added
 - Remote (telnet) mode.

## [v0.15] 25-12-30

### Added
 - Handling of compressed kernels.

## [v0.14] 24-12-18

### Removed
 - Support for RISCV64
   (moved to separate file; petitboot_mkinitrd_riscv64.bash).

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

# petitboot_mkinitrd_riscv64.bash

## [v0.17] 26-11-12

### Changed (Qwen3.8, some assistance by Tripole)
 - Reference rewrite to improve code quality:
 - Eliminated silent failures (missing files, failed downloads/patches, etc.).
 - Per-step exit code checks.
 - Global safety net w/ `set -Eeuo pipefail` + `shopt -s nullglob`
   and ERR trap (line number) with EXIT trap.
 - Clearer time stamping of results/dirs., no dir. collision.
 - Fixed autoupdate call bug (kexec-tools).
 - ARCH normalized parity with the aarch64 version (i.e. only necessary
   ARCH differences).

## [v0.15] 26-10-12

### Changed
 - Fixed bugs in invocation of remote (telnet) mode.
 - Fixed Petitboot compilation errors with newer ncurses (added patch set).
 - Style and comment cleanup.

## [v0.13] 26-02-10

### Changed
 - Rewrite of kexec wrapper.

## [v0.12] 26-01-11

### Added
 - Remote (telnet) mode.

## [v0.11] 26-01-01

### Added
 - Handling of compressed kernels.

## [v0.1] 24-12-18

### Added
 - First commit.

# arm64_kbuild.bash

## [v0.15] 26-10-19

### Added
 - More robust error handling.

### Changed
 - Restructured code into functions.
 - Fixed several bugs relating to (possible) silent failures.
 - Improved prerequisite checking and parameter handling.

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

# riscv64_kbuild.bash

## [v0.15] 26-10-20

### Added
 - More robust error handling.

### Changed
 - Restructured code into functions.
 - Fixed several bugs relating to (possible) silent failures.
 - Improved prerequisite checking and parameters handling.
 - Mostly aligned with arm64_kbuild.bash

## [v0.1] 24-11-19

### Added
 - First version.

# debuntu_dbstrap_aarch64.bash

## [v0.18] 26-10-31

### Added
 - Option to build Devuan.

## [v0.17] 26-10-30

### Changed
 - Restructured code into functions.
 - Bug fixes.
 - Improved error handling
.
## [v0.15] 25-12-08

### Changed
 - Reorg, cleanup, bugfixes.

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

# debuntu_dbstrap_riscv64.bash

## [v0.18]

### Changed
 - Restructured code into functions.
 - Bug fixes.
 - Improved error handling.

### Added
 - Switch (conditional) to nspawn so that tee (of script stdout/stderr) works.

## [v0.16] 26-02-10

### Added
 - Support for Devuan.

## [v0.15] 25-12-12

### Changed
 - Refactoring, rewrite, many small fixes and improvements.

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
