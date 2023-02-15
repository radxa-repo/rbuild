# rbuild - Radxa Image Builder

[![Build](https://github.com/radxa-repo/rbuild/actions/workflows/build.yaml/badge.svg?branch=main)](https://github.com/radxa-repo/rbuild/actions/workflows/build.yaml)

`rbuild` is our latest system image generator, which will replace our existing system build tool [`debos-radxa`](https://github.com/radxa/debos-radxa) soon.
While both tools uses [`debos`](https://github.com/go-debos/debos) underneath, `rbuild` aims to fix many issues that was in `debos-radxa`:
* Unable to generate custom image with different options due to hardcoded config files
* Many duplicated/similar files in board support packages
* Uses in-repo packages instead from an online APT repo
* Confusing per-board package selection

## Usage

### Local 

Please run the following command to check all available options:
```
git clone --depth 1 https://github.com/radxa-repo/rbuild.git
rbuild/rbuild
```

You can then build the image with supported options. The resulting image will be stored in your current directory.

### Running in GitHub Action

Please check out our [GitHub workflows](https://github.com/radxa-repo/rbuild/tree/main/.github/workflows).

## Default image configuration

* Default user and password are all `radxa`
* Default user is in `sudo` group
* SSH is disabled by default to prevent unauthorized access. Host key will be generated at first boot.
* First boot will expand the system partition to fill the storage media

Please check out the [first boot configuration script](https://github.com/radxa-repo/rbuild/tree/main/common/overlays/common/config/before.txt).

## Documentation
Please visit [Radxa Documentation](https://radxa-doc.github.io/).