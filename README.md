# Legion Pro 7 16IAX10H: full speaker sound on Ubuntu 26.04 and 26.10

[![build](https://github.com/o-ergin/legion-ubuntu-sound-fix/actions/workflows/build.yml/badge.svg)](https://github.com/o-ergin/legion-ubuntu-sound-fix/actions/workflows/build.yml)

On the Lenovo Legion Pro 7 16IAX10H (Intel, machine type 83F5), Ubuntu plays through only **2 of the 4
speakers** out of the box. The sound is thin, with no bass. The woofers are driven by two
**Awinic AW88399** smart amplifiers. When they don't start, only the tweeters play. The tweeters are
driven directly by the Realtek ALC287 codec.

Mainline Linux gained a driver for these amps in **7.3** (by Yakov Till and Marco Giunta). What you need
depends on your Ubuntu release:

| Ubuntu | Kernel | Why the woofers are silent | What `install.sh` does |
|---|---|---|---|
| **26.04 LTS** | 7.0 | The kernel has no driver for the amps. | Installs a **DKMS backport** of the mainline driver, plus helpers that rebuild it after kernel updates. You keep Ubuntu's kernel, and the NVIDIA DKMS driver keeps working. |
| **26.10** | 7.3 | The kernel has the driver, but **no tuning file**. The driver requests `aw88399_acf.bin`, and 26.10's `linux-firmware` (20260915) doesn't ship it. The amps fail with `request [aw88399_acf.bin] failed!`. | Installs **only the tuning file**, under the name the kernel's driver requests. No kernel code. |

The installer detects which case applies from the running kernel. On 26.04 it also installs the
26.10 file name, so **a release upgrade from 26.04 to 26.10 keeps the bass working**.
[Upgrading from 26.04](#upgrading-from-2604-to-2610) explains what to do if you installed an older
version of this repo before upgrading.

## Status (tested on one machine: 83F5, codec `17aa:3907`)

**26.04, kernel `7.0.0-43-generic`, DKMS backport.** All five checks under
[After installing](#after-installing-verify) pass:
1. The firmware loads and the component binds:
   - `0x35` is ch0 and `0x34` is ch1
   - the fixup is picked for `17aa:3907`
2. During playback, both amps read `power=ON pll_locked=yes`.
   - Voice tests play on the correct sides.
   - 150 Hz tones come from the matching woofer: left channel, left woofer; right channel, right woofer.
3. The bass follows the volume slider (by ear). The bass pin `0x17` is routed to DAC `0x02`.
4. With headphones in:
   - pins `0x14` and `0x17` are muted
   - no built-in speaker plays, woofers included
5. After S3 suspend and resume:
   - the log shows no amp errors
   - the bass is unchanged on both sides

The kernel-update handling was also tested: a mismatched kernel is skipped cleanly, and a real apt run
rebuilds a removed module.

**26.10, kernel `7.3.0-10-generic`, stock driver.**
- Without the file, both amps failed to probe (`-ENOENT`).
- With `aw88399_acf.bin` installed and the driver reloaded:
  - both amps bound, `.0` on channel 0 and `.1` on channel 1
  - a 150 Hz tone played from both woofers, by ear
- **Pending:** a cold boot with the file already in place.

**Untested:** the `17aa:3906` variant, and any kernel not named above. CI builds the backport against
every new 26.04 kernel. It also checks that every new 26.10 kernel still ships the driver and the
Legion fixup, and requests a firmware name the installer provides. Building is not the same as
listening.

## Supported configuration (the installer refuses anything else)

| | |
|---|---|
| Laptop | Lenovo Legion Pro 7 16IAX10H, DMI product `83F5` |
| Codec | Realtek ALC287, codec SSID `17aa:3907` ("Y7P for Veco speaker"). `17aa:3906` needs `--allow-untested` |
| Amps | 2× AW88399 at I2C `0x35` and `0x34`, ACPI `AWDZ8399` |
| Kernel | **26.10:** any kernel that ships `snd-hda-scodec-aw88399` (7.3+). **26.04:** Ubuntu `7.0.0-NN-generic` with a matching `linux-source-7.0.0` |
| Audio driver | legacy HDA (`snd_hda_intel`). This is the kernel's automatic choice on this platform. |

The `17aa:3906` variant ("YG speaker") uses byte-identical firmware, the same mainline quirk and the
same channel mapping, and both drivers handle it. The installer accepts it only with
`sudo ./scripts/install.sh --allow-untested`, because nobody has tested it with this package yet. If you
have a 3906, please open an issue with the diagnostics output, whether it works or not.

## Install

**Ubuntu 26.10 (kernel 7.3):**

```bash
sudo apt install curl i2c-tools
./scripts/fetch-firmware.sh            # downloads + verifies the tuning file from linux-firmware
sudo ./scripts/install.sh              # installs the file as aw88399_acf.bin (+ awinic/ names)
# turn speaker volume to ~15-20%, then reboot
```

**Ubuntu 26.04 (kernel 7.0):**

```bash
sudo apt install dkms linux-source-7.0.0 linux-headers-$(uname -r) curl i2c-tools
./scripts/fetch-firmware.sh
sudo ./scripts/install.sh              # builds and installs the DKMS backport
# turn speaker volume to ~15-20%, then reboot
```

### Upgrading from 26.04 to 26.10

- **If you installed version 2.2 or later on 26.04:** you don't need to do anything. `aw88399_acf.bin`
  is already in place, and the 7.3 kernel uses its own driver. The DKMS package declines to build for
  7.3 by design.
- **If you installed version 2.1 or earlier:** after the upgrade the bass is gone again, because the
  file the 7.3 driver requests is missing. Update the repository (`git pull`) and run
  `sudo ./scripts/install.sh` again. In 26.10 mode it installs the file, removes the unused 7.0 pieces
  (the DKMS package, the apt hook, the rebuild command and the blacklist), and tells you to reboot.

## After installing: verify

1. Run `sudo legion-aw88399-diagnostics`. It only reads and is safe.
   - **26.10:** both `i2c-AWDZ8399:00-aw88399-hda.N` devices show `driver=aw88399-hda`. The log shows
     `AW88399 Bound - SSID: 17AA3907, channel: 0` and `channel: 1`, and no `request [aw88399_acf.bin] failed!`.
   - **26.04:** the log shows:
     - `picked fixup … for codec SSID 17aa:3907`
     - `0x34: loaded firmware awinic/aw88399_acf_17aa3907.bin, channel 1`
     - `0x35: … channel 0`
     - `AW88399 Bound - SSID: 17AA3907`
2. Play a test sound at low volume: `speaker-test -c 2 -t wav -l 1`.
   - While it plays, run `sudo ./scripts/check-amps.sh`, the short register-only check. Both amps
     should show `power=ON pll_locked=yes`.
   - "Front Left" should come from the left side, including its bass.
   - To test each woofer on its own, play a 150 Hz tone on one channel. Use `-s 1` for left and
     `-s 2` for right:
     `timeout 4 speaker-test -c 2 -t sine -f 150 -s 1`
     80 Hz is mostly inaudible on laptop woofers.
   - The amps stay powered while any stream is open, even a paused browser tab. That is normal.
   - On 26.04, the kernel logs "module verification failed … tainting kernel" when Secure Boot is off.
     That is expected for an out-of-tree module whose signing key the kernel doesn't trust. It is
     harmless.
3. Move the volume slider. The bass must follow it.
4. Plug in headphones. All speakers must go silent.
5. Suspend, resume, and play again.

If something fails, the woofers stay silent and the tweeters keep working as before.

## Uninstall

```bash
sudo ./scripts/uninstall.sh && reboot
```

If a boot ever goes wrong on 26.04, add `modprobe.blacklist=snd_hda_scodec_aw88399_legion` to the kernel
command line. On 26.10 the installer adds only data files, no code.

## Kernel updates

**26.10:** nothing to rebuild. The tuning file is in `/lib/firmware/updates/` and is used by every
kernel. If a future kernel requests a new file name, the CI job reports it, and re-running
`install.sh` adds every plain name the running kernel's driver declares. If the amps ever fail to
start, the login check shows a desktop notification.

**26.04 (DKMS backport), automatic:**

Normally you don't have to do anything. `sudo apt upgrade`, or the Software Updater, installs the new
kernel together with the matching `linux-source-7.0.0`, and the driver is rebuilt for the new kernel
before you reboot.

`dkms/prepare.sh` builds only from the **exact** Ubuntu source of the target kernel. It **skips** the
build, leaving the stock drivers (tweeters only) in place, if any of these is true:
- the `linux-source-7.0.0` version doesn't match the kernel
- the patch doesn't apply with zero fuzz
- the kernel already contains AW88399 support

A skip uses DKMS's exit code 77, so **it never makes the kernel installation fail**. A plain build
failure would abort the kernel package's postinst, before the initramfs and GRUB update.

Three pieces cover the gaps:

| Piece | What it does |
|---|---|
| apt hook (`/etc/apt/apt.conf.d/99legion-aw88399`) | apt may configure the new kernel *before* the new kernel source arrives. After each apt or dpkg run, the hook builds the driver for the kernel that matches the installed source, if it is missing. It always lets apt succeed, and logs to `/var/log/legion-aw88399.log`. |
| login check (`/etc/xdg/autostart/…`) | Shows a desktop notification when the woofers should work but don't. On 7.0, the driver is missing or unbound. On 7.3+, an amp's probe failed, usually because the tuning file is missing. It is silent when everything works. |
| `sudo legion-aw88399-rebuild [kernel]` | The manual fix. It installs the exact matching `linux-source-7.0.0` and headers, with apt's usual confirmation, then builds and installs the driver. |

`linux-source-7.0.0` is marked as manually installed, so `apt autoremove` keeps it.

On a kernel that includes the driver (7.3 or later), the DKMS package declines to build by design. That
kernel's driver loads `aw88399_acf.bin`, which version 2.2 and later install on 26.04 as well.

## What gets installed

| Path | Release | What |
|---|---|---|
| `/lib/firmware/updates/aw88399_acf.bin` | both | tuning file under the name Ubuntu's 7.3 driver requests |
| `/lib/firmware/updates/awinic/aw88399_acf_17aa390{6,7}.bin` | both | the same file under mainline 7.4+'s and the backport's names (`_SUB` isn't readable from sysfs, so both) |
| `/etc/xdg/autostart/legion-aw88399-check.desktop`, `/usr/lib/legion-aw88399/login-check` | both | login notification if the woofers don't start |
| `/usr/local/sbin/legion-aw88399-diagnostics` | both | read-only diagnostics for bug reports |
| `/lib/modules/$(uname -r)/updates/dkms/snd-hda-codec-alc269.ko` | 26.04 | Ubuntu's own `alc269.c` plus mainline's Legion fixup (patch in `dkms/patches/`) |
| `…/snd-soc-aw88399-lib.ko` | 26.04 | mainline `aw88399-lib.c` (3 marked 7.0-compat lines) |
| `…/snd-hda-scodec-aw88399-legion.ko` | 26.04 | HDA side-codec glue (`dkms/hda/`) |
| `/etc/modprobe.d/legion-aw88399.conf` | 26.04 | `blacklist snd_soc_aw88399`. On 7.0 the ASoC driver would claim the device. Not needed on 7.3, which creates no plain `i2c-AWDZ8399:00` client. |
| `/etc/apt/apt.conf.d/99legion-aw88399`, `/usr/lib/legion-aw88399/apt-hook` | 26.04 | rebuild after apt runs (see above) |
| `/usr/local/sbin/legion-aw88399-rebuild` | 26.04 | manual rebuild |

`scripts/uninstall.sh` removes all of these.

## How it works

**On 26.10** the kernel's own driver does everything described below. This repo supplies only the
tuning file. The rest of this section describes the **26.04 backport**, which reproduces the same
behaviour on 7.0.

- **Realtek side:** mainline's `alc287_fixup_legion_16iax10h_aw88399`, copied verbatim. It:
  - reroutes the bass-speaker pin `0x17` from DAC `0x06`, which has **no volume control**, to DAC `0x02`, so the woofers follow the volume slider
  - fixes the headset and mic handling
  - limits the output to stereo

  It then binds the amplifier component and calls its playback hooks.
- **Amplifier side:** on PCM *prepare*, both amps are started synchronously with the Awinic
  firmware: register table, DSP config and DSP firmware. On *cleanup* and *close*, they are muted and
  powered down. On system suspend, they are stopped and flagged for a DSP firmware reload.
- **Difference from mainline:** mainline creates one I2C device per amp through
  `serial-multi-instantiate`. That needs a change to the built-in `drivers/acpi/scan.c`, which a DKMS
  module cannot make. Here, one driver binds the single ACPI client (`0x35`), creates `0x34` itself,
  and registers both amps as one HDA component. Everything else per amp matches mainline: channel
  mapping and swap, firmware name, init order, and hook actions.
  See [docs/UPSTREAM-DIFF.md](docs/UPSTREAM-DIFF.md).

For the full diagnosis, including the mistakes made and corrected along the way, see
[docs/INVESTIGATION.md](docs/INVESTIGATION.md).

## Continuous integration

[`.github/workflows/build.yml`](.github/workflows/build.yml) runs on every push and twice a week, against
both **`-updates`** (what users have now) and **`-proposed`** (kernels that haven't reached users yet):
- **26.04:** runs `prepare.sh` and builds the modules against the newest 7.0 kernel, the way DKMS does.
- **26.10:** downloads the newest kernel's modules and checks that:
  - `snd-hda-scodec-aw88399` and the Legion codec fixup are still there
  - the firmware name the driver requests is one the installer provides

If an upcoming Ubuntu kernel would break either release, the badge turns red before that kernel
reaches anyone's laptop. The workflow also re-checks that linux-firmware still
ships the expected tuning files, and runs shellcheck on the scripts.

## Reporting problems

Open an issue and include the output of `sudo legion-aw88399-diagnostics`. It only reads, and it
leaves out serial numbers and the hostname.

## Credits

- Mainline driver and Legion fixup: Yakov Till and Marco Giunta. Reviewed and applied by Takashi
  Iwai; the ASoC library was pulled by Mark Brown.
- AW88399 device code: Awinic (Weidong Wang).
- Community investigation: [nadimkobeissi/16iax10h-linux-sound-saga](https://github.com/nadimkobeissi/16iax10h-linux-sound-saga),
  [marco-giunta/legion-pro7-gen10-audio](https://github.com/marco-giunta/legion-pro7-gen10-audio),
  Lyapsus, and others.

## License

GPL-2.0-only (see `LICENSE`), the same as the kernel code it is derived from. The firmware is not
included; `scripts/fetch-firmware.sh` downloads it from linux-firmware under that project's terms.
