# Set some arguments as default on

You can create `.rbuild-config` file under the project folder, which will be sourced by the shell before `rbuild` processes the command line arguments. This is a convenient place to override the default behavior of `rbuild` to better suit to a development workflow.

Below is an example used in our work environment:

```bash
CONTAINER_BACKEND="podman"                          # podman allows multiple users
                                                    # to run rbuild on the same build server
REPO_PREFIX="-test"                                 # Build against the latest code
RBUILD_DISTRO_MIRROR="http://apt.vamrs.com"         # Use internal apt mirror
RBUILD_RADXA_MIRROR="http://apt.vamrs.com/rbuild-"  # Use internal apt mirror
```
