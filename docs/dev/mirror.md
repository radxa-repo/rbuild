# Use apt mirrors to speed up build

If you have set up an apt local mirror (for example, using [`AptCacheNG`](https://wiki.debian.org/AptCacherNg)), you can edit the config file to use those mirrors to build your image.

Please be aware that the mirror will be used as image's apt repo as well, so it should be used only for local development build.

Example below uses an internal mirror, that is not accessible to the public.

```bash
$ cat ~/rbuild/.rbuild-config 
RBUILD_DISTRO_MIRROR="http://apt.vamrs.com"
RBUILD_RADXA_MIRROR="http://apt.vamrs.com/rbuild-"
```

`rbuild` will automatically complete the mirror URL based on the build configurations.

You can also define them with the command line arguments `-m|--mirror` and `-M`.
