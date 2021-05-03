# The TDD project

## A framework for test driven Linux software development

The TDD framework is intended to be used by developers to automate common
development tasks.  The framework uses shell scripts to automate tasks and
Jenkins pipeline jobs that run the scripts with specified parameters and/or on
defined triggers.

To ease deployment Docker container images for the various framework components
are published to [Docker Hub](https://hub.docker.com/u/glevand/), and systemd
unit files are provided for those components that can be managed as systemd
services.

The framework supports running tests on both remote physical machines and QEMU
virtual machines.  For the ARM64 and Powerpc64 target architectures both native
and x86-64 hosted cross-compilation is supported.

## Linux Benchmark Testing

At its highest level of automation the framework can, with a single command,
rebuild the Linux kernel from source, build any user specified test frameworks,
generate a minimal OS root filesystem suitable for PXE network booting, deploy
the kernel and root file system images to a PXE boot server, reboot the target
machine to the newly built OS images, run the user specified tests, and collect
and archive the test results.

Currently supported test frameworks are:

* [http-wrk](https://github.com/wg/wrk)
* [ilp32](https://github.com/glevand/ilp32--builder)
* [Linux Kernel Selftests](https://www.kernel.org/doc/Documentation/kselftest.txt)
* [lmbench](https://github.com/intel/lmbench.git)
* [Linux Test Project](https://github.com/linux-test-project/ltp)
* [Phoronix](https://github.com/phoronix-test-suite/phoronix-test-suite)
* [UnixBench](https://github.com/kdlucas/byte-unixbench)

### Linux Benchmark Test Flow:

![Job Flow](images/kernel-test-flow.png)

## Linux Distribution Installer Testing

The framework can also automatically test the installation of Linux
distributions.  The framework can download the distribution installer images
from a release server, perform an unattended OS installation on the target
machine, reboot the target machine to the newly installed OS, run any user
specified tests, and collect and archive the test results.

Currently supported distro installers are:

* Fedora
* OpenSUSE
* SUSE Linux Enterprise (SLE)

### Linux Distribution Installer Test Flow:

![Job Flow](images/distro-test-flow.png)

## Jenkins Support

The TDD Jenkins support is an optional feature.  It's primary use is to provide
a history of build and test results that can be used to monitor and investigate
regression bugs.

Pre-built Docker container images setup with the TDD Jenkins server are
available on [Docker Hub](https://hub.docker.com/u/glevand/).  TDD Jenkins
server container images can also be built from provided
[Dockerfiles](https://github.com/glevand/tdd--docker/tree/master/jenkins).

For setup see the TDD Jenkins service
[README](https://github.com/glevand/tdd--docker/blob/master/jenkins/README.md)
and the [Container and Service Setup](#container-and-service-setup) section of
this document.

## tftpd Service

The tdd-tftpd service is used in conjunction with a tdd-ipxe image installed
on remote target machines to provide an automated boot mechanism of remote
target machines controlled via Intelligent Platform Management Interface (IPMI)
commands.

For setup see the TDD tftpd service
[README](https://github.com/glevand/tdd--docker/blob/master/tftpd/README.md).

## ipxe Support

Remote target machines have a custom [ipxe bootloader](https://ipxe.org) image
installed. This custom image knows where the tdd-tftpd server is located and
what files from the server are to be booted on that system.  The target
machine's UEFI is then configured to run this custom ipxe bootloader image on
boot.

For setup see the TDD ipxe
[README](https://github.com/glevand/tdd--ipxe/blob/master/README.md).

Use commands like these to build and install:

```sh
cd src
make V=1 CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 EMBED=tdd-boot-script -j $(getconf _NPROCESSORS_ONLN || echo 1) bin-arm64-efi/snp.efi
scp bin-arm64-efi/snp.efi root@${remote}:/boot/efi/EFI/ipxe-tdd.efi
ssh ${tftpd_server} mkdir -p /var/tftproot/${remote}/
```

## Relay Service

Once a remote target machine has booted it needs to let the master know it is
ready to receive commands, and if the remote machine was configured via DHCP it
must provide its IP address to the master.  The tdd-relay server is at a known
network location and acts as a message relay server from the remote target
machine to the master.  If there is a firewall between the master and any remote
machines the relay service must accessible from outside the firewall.

For setup see the TDD relay service
[README](https://github.com/glevand/tdd--docker/blob/master/relay/README.md).

## Build Host Setup

### Host System binfmt support

QEMU user mode emulation is used when cross building root filesystems.  QEMU
user mode binfmt support needs to be setup on the build host.

#### Debian based systems

For Debian based systems the following packages will install the needed binfmt
support:

```sh
sudo apt install binfmt-support qemu-user-static
sudo systemctl restart systemd-binfmt.service
```
#### Fedora based systems

For Fedora based systems the following packages will install the needed binfmt
support:

```sh
sudo dnf install qemu-user qemu-user-binfmt
sudo systemctl restart systemd-binfmt.service
```
#### Other systemd based systems

```sh
echo ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/usr/bin/qemu-aarch64-static:' | sudo tee /etc/binfmt.d/qemu-aarch64.conf > /dev/null
sudo systemctl restart systemd-binfmt.service
```

#### To test binfmt installation:

```sh
$ ls /proc/sys/fs/binfmt_misc
qemu-aarch64  register  status
```

### Container and Service Setup

The
[docker-build-all.sh](https://github.com/glevand/tdd--docker/blob/master/docker-build-all.sh)
script will bulid all the TDD containers and can also install and enable the
systemd services of those containers that have them.  Individual containers and
services can be build and/or setup with the container's build script,
[build-jenkins.sh](https://github.com/glevand/tdd--docker/blob/master/jenkins/build-jenkins.sh)
for example.

## Trouble-shooting

Seen: `Got permission denied while trying to connect to the Docker daemon socket`

Seen: `/var/run/docker.sock: permission denied`

Solution: Add current user to docker group.

***

Seen: `chroot: failed to run command ‘/bin/bash’: Exec format error`

Solution: Install
[host binfmt support](https://github.com/glevand/tdd-project#host-system-binfmt-support).
