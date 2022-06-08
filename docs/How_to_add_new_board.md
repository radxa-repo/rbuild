# How to add new board

Enabling new board in rbuild is simple, as most jobs should have already been done before touching this repo.

You should first update `lbuild` and `ubuild` to have them generate `linux-images-<board-name>` and `u-boot-<board-name>` deb packages. Do not mismatch those packages with different boards as the script might call files under board specific folder. In case of Linux kernel the package's name should not be touched, and `linux-images-<board-name>` needs to be added to deb's `Provides` property using `SUPPORTED_BOARDS` variable in `fork.conf`.

Once you have both of them available, you can start building system image to test your kernel and U-Boot. Copy both files to `rbuild` folder (this folder will be mounted in `docker` so if those files are outside of `rbuild` folder the script won't be able to access them). Create `board-name.conf` under `configs`, with one line `SOC=system_on_chip_model` (model number in lower case). If you are adding Rockchip based device, their SoC name usually starts with `rk` and can be recognized by `common/hw-info.conf`. For non-standard name (Rockchip PX30, Amlogic based SoC), update `hw-info.conf`'s `get_soc_family` function. For entirely new vendor, you will also need to update `get_partition_type` function and review any mention of `soc_family` within the script.

Once you create the board config file (yes, it's that simple), check if the following dependencies are met:

> `multipath-tools` (for `kpartx`) </br>
> [rootless docker](https://docs.docker.com/engine/security/rootless/)

and then run the following command:
```
./rbuild -r -d -k linux-image-board-name.deb -f u-boot-board-name.deb board-name
```

`-r` means reusing rootfs generated in previous run. This saves a lot of time when testing multiple devices or different kernels. `-d` means dropping into a debug shell if any step fails. `-k` and `-f` specify the custom kernel and **f**irmware (currently U-Boot) you are going to use. This will build a CLI image by default.

You can then test your image. Once you are sure your kernel and firmware are up to sniff, create new repos in `radxa-pkg` organization to automatically generate packages for them (or update the existing one), create new releases, and update `radxa-repo/apt` to include them in the apt repo. You can then build image without `-k` and `-f` options.

Now you can update `radxa-build` organization to have the image auto generated over there.