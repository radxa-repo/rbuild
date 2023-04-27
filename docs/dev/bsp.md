# Use locally built kernel and firmware

It is very common during the bring-up stage that the kernel and the firmware are evolving rapidly. This makes fetching those packages from apt repo very cumbersome. `rbuild` tailors to this use case, and allow the use of locally built kernel and firmware Deb package.

One thing we specifically do not allow is to install arbitrary packages with command arguments. The reason is that this makes tracking the image's origin more difficult. Consider the options listed here as exceptions.

Proper way for adding product specific package should be either update yaml templates, or via [`radxa-profiles`](https://github.com/radxa-pkg/radxa-profiles) package.

## `-c|--custom` flag

Consider this: you build `linux-latest` and `u-boot-latest` packages with `bsp` and want to use them for your `rbuild` image. As long as `bsp` and `rbuild` are located under the same parent folder, you can use `-c` flag to consume both packages at once:

```bash
./rbuild -c latest radxa-zero
```

When we say "under the same parent folder", we mean something like `/home/user/bsp` and `/home/user/rbuild`, where both are under the same `/home/user` folder. `-c` flag will search `bsp` repo with the same directory level. However, if you copied them to `rbuild` folder, it will also be searched.

`-c` flag's argument is the same `bsp` profile name, so in the above example, we are able to use one flag to match both kernel and firmware packages. However, `-c` flag will not complain if there is no matching package, so you don't have to build both the kernel *and* firmware in order to use this flag.

You can even specify `-c` flag multiple times, if your kernel and firmware are using different profiles. For example, many Rockchip products uses `linux-rockchip` and `u-boot-latest`. You can simply run the following command for those products:

```bash
./rbuild -c rockchip -c latest rock-4c-plus
```

However, there is an issue. What if we have both `linux-rockchip` and `linux-latest` packages built in `bsp`? Currently, the second `-c` flag will override the previous choice, so you end up with both `linux-latest` and `u-boot-latest` for image above.

If this is not intended, you can either delete unused packages from your `bsp` repo, or using the below flags to manually specify a package.

## `-k|--kernel` and `-f|--firmware` flags

Under the hood, `-c` flag calls the functionalilty of `-k` and `-f` flages. They take a path to a build Deb packages, so there is no second guessing.

Unlike `-c`, those flages will throw out error if the specified package does not exist, which is to be expected from a lower level feature.
