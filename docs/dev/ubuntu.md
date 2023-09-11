# About Ubuntu

## Current status

While Ubuntu is a build target for `rbuild`, it is not officially supported by Radxa for use on our products. The reason is multifold:

1. Starting from Ubuntu 21.10, all of its packages are [compressed with Zstd](https://www.phoronix.com/news/Ubuntu-21.10-Zstd-Debs). We are currently using [the official Debos docker image](https://hub.docker.com/r/godebos/debos), which is based on Debian, and does not support Zstd compressed package. Attempts to create an Ubuntu based docker image are [getting](https://github.com/go-debos/debos/issues/9) [nowhere](https://github.com/go-debos/debos/issues/314), so currently one has to both use Ubuntu as the build host and disable the container build for `rbuild` to work, which greatly limits the developer's choice of OS and build reproducibility.

2. Rockchip only provides Debian SDK, and for some dependencies the package names and/or versions are different between Debian and Ubuntu, meaning they cannot be installed as-is. This cannot be simply fixed by changing the control file pointing to a different package, as packaged binaries are hardcoded to some specific version of dynamic libraries, and there might be incompatible ABI changes between the two OS. Recompilation and repackaging are required to properly fix this issue, but they can be time-consuming, and sometimes the necessary code for those is not available.

For those reasons, Radxa has historically only provided the Ubuntu CLI image with no vendor hardware enablement packages. With the release of `rbuild`, we now dropped Ubuntu CLI as an officially supported system entirely, and recommend our users to use Debian CLI instead. The only exception is that some users want to run ROS on our products, which requires Ubuntu.

## Build Ubuntu

To build Ubuntu, there are additional requirements beyond what was listed in [Build your first image](first_image.md):

1. The host should run Ubuntu.
2. The host Ubuntu version should be greater or equal to the version you plan to build.
3. You should install `debos` on your system: `sudo apt-get update && sudo apt-get install -y debos`.
4. Replace any `./rbuild` command with `sudo ./rbuild --native-build` like what we did in our [GitHub Action](https://github.com/radxa-repo/rbuild/blob/main/action.yaml#L78) (which runs on Ubuntu runner).