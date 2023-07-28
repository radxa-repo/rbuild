# General architecture

`rbuild` is the final stage of our image-building pipeline. However, before it can be triggered, many subcomponents and tasks have to be completed and released first.

## Submit code changes

The following repositories contain the source code, so the related commits should be pushed in the repo first before the planned release:

* [Kernel](https://github.com/radxa/kernel/)
* [U-Boot](https://github.com/radxa/u-boot/)
* [Overlays](https://github.com/radxa/overlays/)
* and any repositories that contain `Makefile` under [radxa-pkg](https://github.com/radxa-pkg)

## Release Debian packages

For packages under [radxa-pkg](https://github.com/radxa-pkg), once changes are made, please run `make dch` command to create a new changelog entry.

Edit `debian/changlog` accordingly, then change `UNRELEASED` to `stable`. You should then create a commit containing only this change, with the commit title `Release x.y.z`.

It is recommended to run `make deb` after you commit your changelog edit, so the package can be tested by [`lintian`](https://lintian.debian.org/) for common pitfalls. We treat warning as error, so please fix them, instead of suppressing them.

GitHub Workflows will then detect this new version, and create a new GitHub Release with the build artifacts. You can manually trigger the workflow [from the website](https://github.com/radxa-pkg/rsetup/actions/workflows/release.yml) or within project folder using following command:

```bash
make release
```

---

Kernel and U-Boot's package repo under `radxa-pkg` needs to be reworked to follow the above release method. Currently the workflow will create a new release if [`VERSION`](https://github.com/radxa-pkg/linux-rockchip/commit/9dab83617d08c125745135250f60c09e863b0909) file is updated. You can also manually trigger the workflow as above.

Before releasing the Kernel package, [`overlay.sh`](https://github.com/radxa-repo/bsp/blob/main/linux/.common/overlays.sh#L2) needs to be updated to pointing at the latest `overlays` commit. This is to pin `overlays` version with `bsp` version.

## Update apt repos

While testing repos will sync daily with the latest package releases, the production repos require manual updating, so unverified software will slip past testing. At least that's the plan. Currently, production repos also pull the latest packages.

There are 2 workflows to update the apt repo. `update.yml` will fetch any new packages, and update the index files. There is no downtime during the update, so this should be preferred for updating small packages.

The other workflow `reset.yml` will first clear the branch history, before pulling packages. This is because the normal `update.yml` won't delete old packages, and the naive approach is not suitable since some systems require an older version of the package (which should be added explicitly). This should be the one to use if there is a new kernel or U-Boot package.

Below is an bash example to trigger apt repo update:

```bash
set -euo pipefail
for i in buster bullseye focal jammy
do
    gh workflow run --repo radxa-repo/$i update.yml
done
```

Depending on which workflow you use, you will see 1 or 2 completed `pages build and deployment` runs in Actions history, which indicates the apt repo has been updated.

## Trigger image build

Once apt repo is updated. We can trigger RC image build. This is also done using workflows:

```bash
set -euo pipefail
for i in rock-3c radxa-cm3-sodimm-io
do
    gh workflow run --repo radxa-build/$i build.yml
done
```

By default, the release will be marked as `pre-release`. Once it passes the internal testing, it can be promoted as the latest official release.
