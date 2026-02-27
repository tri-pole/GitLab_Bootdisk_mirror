# Building Petitboot with docker

It is straightforward to set up a `docker` environment on a Linux x86_64 host
and employ docker containers for `binfmt` and `ubuntu` to build the `Petitboot`
initramfs using either `petitboot_mkinitrd_riscv64.bash` or
`petitboot_mkinitrd_arm64.bash`.
In the example below we build for RISCV64; the procedure is the same for ARM64.

## Prerequisites

The host must have basic `QEMU` and `docker` functionality installed, including
the packages `binfmt-support`, `qemu-user-binfmt`, `docker.io` and `docker-cli`.

## Clone the bootdisk repo

The first step in the build process is to either clone the `bootdisk` repo
```
user@host:~$ git clone --depth 1 https://gitlab.com/tripole-inc/bootdisk.git bootdisk
user@host:~$ cd bootdisk
```
or simply copy over the file `petitboot_mkinitrd_riscv64.bash` to the directory
`bootdisk` (since this is the only file needed).

## Run the docker containers

The next step is to run the two docker containers used in the build process.
If the user on the host is in the docker group then the following can be
executed as that user (otherwise execute as root).

First, run the docker container with `binfmt` for the arch we are building for,
in this example RISCV64.
```
user@host:bootdisk$ docker run --rm --privileged tonistiigi/binfmt -install riscv64
```
Then, run the docker container with `ubuntu` (Jammy) for the arch, with a bash
prompt as app
```
user@host:bootdisk$ docker run -it --rm --platform linux/riscv64 -v /home/user/bootdisk:/mnt ubuntu:jammy bash
```
and a bash root prompt for the container will appear.
The rest of the steps are done at this prompt.

## Configure the `ubuntu` docker container

Our next step is to update package database, upgrade the packages and install
build dependencies in the container
```
root@d0ffcf6555ea:~# apt update && apt upgrade -y
root@d0ffcf6555ea:~# apt install -y \
  autoconf bison build-essential cpio flex gawk gettext git gperf \
  libasprintf-dev libblkid-dev libdevmapper-dev libdw-dev libelf-dev \
  libgd-tools libgettextpo-dev libgpgme-dev liblzma-dev libncurses-dev \
  libssl-dev libtool libudev-dev pkg-config sudo tree u-boot-tools wget zstd
```

## Build the Petitboot initramfs

Finally, the initramfs for `Petitboot` for the arch in question is built.

Go to the `/mnt` directory in the container and run the build script
```
root@d0ffcf6555ea:~# cd /mnt
root@d0ffcf6555ea:/mnt# ./petitboot_mkinitrd_riscv64.bash
```

The output of the last command will appear in the `bootdisk` directory on the
host (and will have owner:group `root:root` on the host, but this can easily be
changed from within the container before exiting the container).