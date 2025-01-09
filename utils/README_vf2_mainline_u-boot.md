
# Mainline u-boot and openSBI for VisionFive 2

These notes describe how to build mainline `u-boot` and `openSBI` for the
StarFive VisionFive 2 board and discusses some of the pros and cons of
using the mainline versions of these software components versus the vendor
versions.

## Introduction

Both `openSBI` and `u-boot` now support VisionFive 2 (VF2) fully in mainline
but the official u-boot [build instructions](
https://docs.u-boot.org/en/latest/board/starfive/visionfive2.html)
need to be amended with some extra steps, it seems.
It is the intention of this writeup to supply these steps, using essentially
the procedure in
[VisionFive2_Software Techical Reference Manual](https://doc-en.rvspace.org/VisionFive2/PDF/VisionFive2_SW_TRM.pdf), but amended with the extra steps.
It is quite possible howevern that the procedure we describe can be simplified,
and perhaps even contains unnecessary steps.

### Prerequisites and scope

We assume that all the commands below are run natively on `ARCH=riscv` (e.g.
QEMU or bare metal on VF2) where a proper build environment is present (e.g.
build-essential, git etc.). In a cross compile situation a cross compile
directive

```
  CROSS_COMPILE=riscv64-linux-gnu-
```

must be added to the `make` commands below.

It will be handy to have your own custom version of the `u-boot` config file,
for instance the one supplied by us (the version used in StarFive's fork of
`u-boot` is called `starfive_visionfive2_defconfig`).

The procedure here has been tested with `openSBI` v1.6 and `u-boot` v2024.10
and v2025.01.

## Preliminaries

### (P1) Set up a build dir and cd into it.

```
$ mkdir build
$ cd build
```

### (P2) For convenience, define some environment variables.

(Adapt these variables to your particular build case.)

```
$ build_path=$PWD
$ uboot_ver="v2024.10"
$ opensbi_ver="v1.6"
$ sf_tools_branch="master"
$ uboot_path=${build_path}/"u-boot-"${uboot_ver}
$ opensbi_path=${build_path}/"opensbi-"${opensbi_ver}
$ sf_tools_path=${build_path}/"StarFiveTools"
$ vf2_cfg_name="jh7110-starfive-visionfive-2"
```

### (P3) clone/install u-boot.

```
$ git clone --depth 1 -b $uboot_ver \
  https://github.com/u-boot/u-boot.git $uboot_path
```

### (P4) clone/install openSPI.

```
$ git clone --depth 1 -b $opensbi_ver \
  https://github.com/riscv-software-src/opensbi.git $opensbi_path
```

### (P5) clone/install StarFive tools.

```
$ git clone --depth 1 -b $sf_tools_branch \
  https://github.com/starfive-tech/Tools $sf_tools_path
```

### (P6) Build the StarFive tools:

```
$ cd ${sf_tools_path}/spl_tool
$ make
```

The output is the executable file

```
${sf_tools_path}/spl_tool/spl_tool
```

which will be used below.

The steps (P1)-(P6) need only be done once, if you repeat the build process
below. (If you repeat the build process you should insert a make clean
command before issuing any new make command, as good practice.)

## Build process

There seems to be an interdependence of files created by `openSBI` and files
created by `u-boot` so the build process will go back and forth between
`openSBI` and `u-boot`, starting with a build of a throw-away version of
`fw_payload.bin` which is needed in order for `u-boot` to build (after which
`openSBI` is built again).

### (B1) Build a throw-away version of `fw_payload.bin` from openSPI.

```
$ cd $opensbi_path
$ make PLATFORM=generic FW_TEXT_START=0x40000000 FW_OPTIONS=0
```

The output from this commad is, among other things, the file

`${opensbi_path}/build/platform/generic/firmware/fw_payload.bin`

which will be used below.

### (B2) Build u-boot.

#### (B2.1) Set up a defconfig:

Go to the u-boot directory

```
$ cd ${uboot_path}
```

and then copy over _your own_ version of `starfive_visionfive2_defconfig` to

```
${uboot_path}/configs/${vf2_cfg_name}_defconfig
```

Then, do

```
$ make ${vf2_cfg_name}_defconfig
```

which will set up the file 

```
${uboot_path}/.config
```

This file will be used for building u-boot in the next step. (As an
alternative, one can here use the make menuconfig command etc. to set up a
suitable configuration file.)

#### (B2.2) Build u-boot and its components:

```
$ make OPENSBI=${opensbi_path}/build/platform/generic/firmware/fw_payload.bin
```

The output from this command is, among other things, the following files:

```
${uboot_path}/u-boot.bin
${uboot_path}/spl/u-boot-spl.bin
${uboot_path}/arch/riscv/dts/${vf2_cfg_name}.dtb
```

### (B3) Create the SPL using the previously generated `u-boot-spl.bin`

```
$ cd ${sf_tools_path}/spl_tool
$ ./spl_tool -c -f ${uboot_path}/spl/u-boot-spl.bin
```

The output from this commmand is the file

```
${uboot_path}/spl/u-boot-spl.bin.normal.out
```

which is the first of the two files that make up the firmware.

### (B4) Make the final version of `fw_payload.bin`

```
$ cd $opensbi_path
$ make PLATFORM=generic FW_PAYLOAD_PATH=${uboot_path}/u-boot.bin \
  FW_FDT_PATH=${uboot_path}/arch/riscv/dts/${vf2_cfg_name}.dtb \
  FW_TEXT_START=0x40000000
```

One of the files that is generated by this command is

```
${opensbi_path}/build/platform/generic/firmware/fw_payload.bin
```

which will be used in the next step.

### (B5) Create `visionfive2_fw_payload.img`

Go to the `uboot_its` dir and copy over the `fw_payload.bin` file created
previously.

```
$ cd ${sf_tools_path}/uboot_its
$ cp ${opensbi_path}/build/platform/generic/firmware/fw_payload.bin .
```

Use the template file `visionfive2-uboot-fit-image.its` in the current dir to
create the `visionfive2_fw_payload.img` file from `fw_payload.bin`:

```
${uboot_path}/tools/mkimage -f visionfive2-uboot-fit-image.its \
  -A riscv -O u-boot -T firmware visionfive2_fw_payload.img
```

The output is the file

```
${sf_tools_path}/uboot_its/visionfive2_fw_payload.img
```

which is the second and last of the two firmware files created by the build
procedure.

## Result of the build procedure

Now we have 

```
${uboot_path}/spl/u-boot-spl.bin.normal.out
${sf_tools_path}/uboot_its/visionfive2_fw_payload.img
```

and these two files can be copied to flash or SD using the methods described
in [VisionFive 2 Quick Start Guide](https://doc-en.rvspace.org/VisionFive2/PDF/VisionFive2_QSG.pdf),
Sec. 3.8.1 (Updating SPL and U-Boot of Flash).

## Remarks

* It seems that the 6.1.y kernels will not boot/run with newer mainline
  `u-boot` on VF2, but these kernels work with StarFive's `u-boot` (with a code
  base from 2021). We have built and tried all four combinations of `u-boot` and
  `openSBI` as follows:

  `u-boot`: mainline v2024.10 and StarFive's (branch JH7110_VisionFive2_devel, tag: JH7110_VF2_6.6_v5.13.1)

  `openSBI`: mainline v1.6 and StarFive's (branch master, tag: VF2_v3.8.2)

  The 6.1.y kernels will only boot with StarFive's fork of `u-boot`. (The
  other three combinations of `u-boot` and `openSBI` can boot all tested kernels
  from 6.6.y and 6.12.y.)

* To build using StarFive's fork of `u-boot`, use the name

```
  $ vf2_cfg_name="starfive_visionfive2"
```


## References

The above procedure has been put together based (mostly) on the information in
these sources

[VisionFive 2 Software Technical Reference Manual](https://doc-en.rvspace.org/VisionFive2/PDF/VisionFive2_SW_TRM.pdf)

[`u-boot` VisionFive 2](https://docs.u-boot.org/en/latest/board/starfive/visionfive2.html)

[`openSBI` Github, v1.6](https://github.com/riscv-software-src/opensbi/tree/v1.6)

[`u-boot` Github, v2024.10](https://github.com/u-boot/u-boot/tree/v2024.10)

