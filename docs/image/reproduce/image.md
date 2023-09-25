# Reproduce released image

While we recommend everyone keep their system up-to-date, sometimes, the customer develops their solution on one of our previously released images. Since they have validated the use case on that specific release, they want to reproduce images based on that specific release.

In this article we will show you how to reproduce [`rock-3c_debian_bullseye_xfce_b27.img.xz`](https://github.com/radxa-build/rock-3c/releases/tag/20230321-0636) as an example. Please also have `git` and [`gh`](https://cli.github.com/) installed on your system.

## Get build time information from released image

Every released `rbuild` images contains 2 files describing their build time environment. They are `/etc/radxa_image_fingerprint` for the build system, and `/etc/radxa_apt_snapshot` for the then-available packages on Radxa official APT repo.

### Check the content from a running system

```bash
radxa@rock-3c:~$ cat /etc/radxa_image_fingerprint
RBUILD_BUILD_DATE='Tue, 21 Mar 2023 07:06:37 +0000'
RBUILD_REVISION='6d211a5998fdfc9f58fe7b9a2f507ec8c28199a2'
RBUILD_COMMAND='./rbuild --timestamp=b27 --compress --native-build --shrink --root-override rock-3c bullseye xfce'
RBUILD_KERNEL='linux-image-4.19.193-1-rk356x'
RBUILD_KERNEL_VERSION='4.19.193-1-41024583a'
RBUILD_UBOOT='u-boot-rk356x'
RBUILD_UBOOT_VERSION='2017.09-1-15c53b0'
radxa@rock-3c:~$ cat /etc/radxa_apt_snapshot 
{
  "libreelec-alsa-utils": "10.0.2-1",
  "radxa-otgutils": "0.2.1",
  "rsetup": "0.3.13",
  ...
}
```

### Check the content from a disk image

You can use following commands to check the system info without a running device:

```bash
sudo apt update
sudo apt install multipath-tools
sudo kpartx -a system.img
# Check with `lsblk` to find the last loop device partition
# In this example we assume it is loop0p3
sudo mount /dev/mapper/loop0p3 /mnt
cat /mnt/etc/radxa_image_fingerprint
sudo umount /mnt
sudo kpartx -d system.img
```

## Create a custom apt repo

As shown in `RBUILD_COMMAND` above, our image is based on Debian Bullseye. We will have to create a custom apt repo for `rbuild` based on `radxa_apt_snapshot`, since the official Radxa apt repo is likely to have newer packages.

In this article we will only fork the existing Radxa apt repo. If you want to create a apt repo from scrach, please check [Create apt repo from scratch](apt.md).

First, make sure we have logged in with `gh`:

```bash
[excalibur@yuntian reproduce]$ gh auth status
github.com
  ✓ Logged in to github.com as RadxaYuntian (/home/excalibur/.config/gh/hosts.yml)
  ...
```

If the account is incorrect, we can use `gh auth logout; gh auth login` to authenticate with the desired account.

We can now create a fork of the apt repo. Recall we need one targetting `bullseye`:

```bash
RELEASE=bullseye
GITHUB_NAMESPACE=your_account_or_orginazation
gh repo fork radxa-repo/$RELEASE --default-branch-only <<< "n"
gh repo clone $GITHUB_NAMESPACE/$RELEASE
cd $RELEASE
nano pkgs.lock # paste the content of /etc/radxa_apt_snapshot
git add pkgs.lock
git commit -m "Add pkgs.lock"
```

We now need to create a custom apt signing key. Proper key management is beyond the scope of this article, so we will create 

```bash
GPG_KEY_EMAIL=testing@repo.com
sed -i "s/dev@radxa.com/$GPG_KEY_EMAIL/" .freight.conf
git add .freight.conf
git commit -m "Update signing key"
# Below key is for testing only, please follow Debian keyring policy for production usage
gpg --batch --quick-gen-key --passphrase "" $GPG_KEY_EMAIL
gpg --armor --export-secret-keys $GPG_KEY_EMAIL | gh secret set --repo $GITHUB_NAMESPACE/$RELEASE GPG_KEY
```

We can finally start populating our apt repo:

```bash
git switch -c gh-pages
git push --all
gh repo set-default $GITHUB_NAMESPACE/$RELEASE
gh workflow disable static.yml
gh workflow run update.yml
```

We can check the workflow status with `gh run list`. After a while, we should see 2 successful runs for `pages-build-deployment` workflow:

```bash
[excalibur@yuntian bullseye]$ gh workflow view pages-build-deployment
pages-build-deployment - pages-build-deployment
ID: 52533629

Total runs 2
Recent runs
✓  pages build and deployment  pages-build-deployment  gh-pages  dynamic  4538811569
✓  pages build and deployment  pages-build-deployment  gh-pages  dynamic  4538785650

To see more runs for this workflow, try: gh run list --workflow pages-build-deployment
To see the YAML for this workflow, try: gh workflow view pages-build-deployment --yaml
```

The first run is created when we pushed `gh-pages` branch (which also enabled workflow on forked repo). The second run is triggered after packages has been fetched, and it is this one that makes our apt repo functioning.

## Prepare `rbuild` for reproducing released image

Recall `rbuild` commit ID was saved in `/etc/radxa_image_fingerprint`, we will checkout at this exact commit:

```bash
RBUILD_REVISION='6d211a5998fdfc9f58fe7b9a2f507ec8c28199a2'
cd .. # leave bullseye repo
gh repo clone radxa-repo/rbuild
cd rbuild
git switch --detach $RBUILD_REVISION
```

We also need to edit `common/scripts/add_radxa_repo.yaml` to switch the default repo URL and fetch keyring from apt repo:

```bash
[excalibur@yuntian rbuild]$ git diff common/scripts/add_radxa_repo.yaml
diff --git a/common/scripts/add_radxa_repo.yaml b/common/scripts/add_radxa_repo.yaml
index 448857c..f25a10a 100644
--- a/common/scripts/add_radxa_repo.yaml
+++ b/common/scripts/add_radxa_repo.yaml
@@ -1,4 +1,4 @@
-{{- $radxa_mirror := "https://radxa-repo.github.io/" -}}
+{{- $radxa_mirror := "https://radxayuntian.github.io/" -}}
 
 {{- $origin := .origin -}}
 {{- $suite := .suite -}}
@@ -6,7 +6,7 @@
 {{- $priority := or .priority "" -}}
 {{- $area := "main" -}}
 
-{{- $managed_keyring := "true" -}}
+{{- $managed_keyring := "false" -}}
 {{- $managed_keyring_repo := "radxa-pkg/radxa-archive-keyring" -}}
 
 {{- $architecture := .architecture -}}
```

If the checked-out `rbuild` does not contain `managed_keyring` option, we need to include the following patch before making changes:

```bash
git reset --hard $RBUILD_REVISION
git am --abort
curl -L https://github.com/radxa-repo/rbuild/commit/2a861f6fbc2c1d081d5d83aabfc99bda4abd38d3.patch | git am
```

We can then use `RBUILD_COMMAND` as a reference to reproduce the image. The exact command listed in `/etc/radxa_image_fingerprint` was meant to be run on GitHub's Ubuntu runner as root.
