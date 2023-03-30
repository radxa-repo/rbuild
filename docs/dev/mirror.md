# Use apt mirrors to speed up build

If you have set up an apt local mirror (for example, using [`AptCacheNG`](https://wiki.debian.org/AptCacherNg)), you can edit the following line to use that mirror to build your image.

Please be aware that the mirror will be used as image's apt repo as well, so it should be used only for local development build.

Example below uses an internal mirror, that is not accessible to the public.

```patch
diff --git a/common/intermediate.yaml b/common/intermediate.yaml
index ec6ab2d..d7c3662 100644
--- a/common/intermediate.yaml
+++ b/common/intermediate.yaml
@@ -2,9 +2,9 @@
 {{- $suite := .suite -}}
 {{- $repo_prefix := .repo_prefix -}}
 
-{{- $debian_mirror := "https://deb.debian.org" -}}
+{{- $debian_mirror := "http://apt.vamrs.com" -}}
 {{- $debian_area := "main contrib non-free" -}}
-{{- $ubuntu_mirror := "http://ports.ubuntu.com" -}}
+{{- $ubuntu_mirror := "http://apt.vamrs.com" -}}
 {{- $ubuntu_area := "main restricted universe multiverse" -}}
 
 {{- $architecture := .architecture -}}
diff --git a/common/scripts/add_radxa_repo.yaml b/common/scripts/add_radxa_repo.yaml
index 83b73f9..f0f4064 100644
--- a/common/scripts/add_radxa_repo.yaml
+++ b/common/scripts/add_radxa_repo.yaml
@@ -1,4 +1,4 @@
-{{- $radxa_mirror := "https://radxa-repo.github.io/" -}}
+{{- $radxa_mirror := "http://apt.vamrs.com/rbuild-" -}}
 
 {{- $origin := .origin -}}
 {{- $suite := .suite -}}
```