# Build your first image

## Install dependencies

Currently due to our dependency on [`debos`](https://github.com/go-debos/debos/issues/363), we can only run `rbuild` on x86 based system.

### Debian 12 / Ubuntu 22.04

```bash
sudo apt update
sudo apt install -y git

# Podman (recommended)
sudo apt install -y podman podman-docker
sudo touch /etc/containers/nodocker
# Docker
#sudo apt install docker.io

# For Ubuntu user you can also install `debos` package for building Ubuntu image
sudo apt install -y debos
```

## Check out the code

```bash
git clone https://github.com/radxa-repo/rbuild.git
```

## Build your first image

Once the repo is cloned on your machine, you can run `rbuild` without any arguments to check the help message:

```bash
cd rbuild
./rbuild
```

Most options listed in the help messages are targetting at developers. If you only want to build a image locally, you can run `rbuild` with only the required arguments:

```bash
# Build radxa-cm3-sodimm-io image with default OS (currently Debian Bullseye) and flavor (CLI)
./bsp radxa-cm3-sodimm-io
# Build rock-5b Debian image with KDE
./bsp rock-5b kde
```

Supported products, suites, and flavors are listed at the end of the help message.
