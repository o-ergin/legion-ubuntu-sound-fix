---
name: Bug report
about: The woofers are silent, the sound is wrong, or the build or install fails
labels: bug
---

**What happens.** Describe the problem: thin sound, no bass, one side only, crackling, fails after
a kernel update, install error, and so on.

**What you expected.**

**Steps to reproduce.**

**Diagnostics.** Run the following and paste the full output below. The script only reads; it changes
nothing, and it leaves out serial numbers and the hostname.

```
sudo legion-aw88399-diagnostics
```

If the package isn't installed yet, run `sudo ./scripts/diagnostics.sh` from the repository instead.

<details><summary>diagnostics output</summary>

```
PASTE HERE
```

</details>

**If the build failed**, also paste the last 40 lines of `/var/lib/dkms/legion-aw88399/*/build/make.log`.
