# Legion Pro 7 16IAX10H: full speaker sound on Ubuntu 7.0 kernels (AW88399 DKMS backport)

[![build](https://github.com/o-ergin/legion-pro7-16iax10h-aw88399-dkms/actions/workflows/build.yml/badge.svg)](https://github.com/o-ergin/legion-pro7-16iax10h-aw88399-dkms/actions/workflows/build.yml)

On the Lenovo Legion Pro 7 16IAX10H (Intel, machine type 83F5), Linux only plays through **2 of the 4
speakers**. The sound is thin, with no bass. The woofers are driven by two **Awinic AW88399** smart
amplifiers. Linux 7.0 never powers those amplifiers up, so only the tweeters play. The tweeters are
driven directly by the Realtek ALC287 codec.

Mainline Linux gained support for this laptop in **7.3** (driver by Yakov Till and Marco Giunta). This
repository backports that mainline code to **Ubuntu's 7.0.0-NN-generic kernels** as a DKMS package, so
you don't have to replace the kernel. That matters on this laptop: its displays run on the NVIDIA GPU,
which needs the NVIDIA DKMS driver to keep working.

> **Status:** Tested on one machine: Legion Pro 7 16IAX10H (83F5), codec SSID `17aa:3907`, Ubuntu
> kernel `7.0.0-43-generic`, PipeWire 1.6, legacy HDA. All five checks under
> [After installing](#after-installing-verify) pass:
>
> 1. The firmware loads and the component binds:
>    - `0x35` is ch0 and `0x34` is ch1
>    - the fixup is picked for `17aa:3907`
> 2. During playback, both amps read `power=ON pll_locked=yes`.
>    - Voice tests play on the correct sides.
>    - 150 Hz tones come from the matching woofer: left channel, left woofer; right channel, right woofer.
> 3. The bass follows the volume slider, confirmed by listening.
>    - The bass pin `0x17` is routed to DAC `0x02`, the DAC behind the slider.
> 4. With headphones plugged in:
>    - pins `0x14` and `0x17` are muted
>    - no sound comes from any built-in speaker, woofers included
> 5. After S3 suspend and resume:
>    - the log shows no amp errors
>    - the amps restart on the next playback, and the bass is unchanged on both sides
>
> The driver code is unchanged in 2.1. Version 2.1 adds the kernel-update handling, and that was
> tested on the same machine: a mismatched kernel is skipped cleanly, and a real apt run rebuilds a
> removed module. The `17aa:3906` variant is untested. CI builds every new Ubuntu 7.0 kernel, but
> building is not the same as listening.

## Supported configuration (the installer refuses anything else)

| | |
|---|---|
| Laptop | Lenovo Legion Pro 7 16IAX10H, DMI product `83F5` |
| Codec | Realtek ALC287, codec SSID `17aa:3907` ("Y7P for Veco speaker"). `17aa:3906` needs `--allow-untested` |
| Amps | 2× AW88399 at I2C `0x35` and `0x34`, ACPI `AWDZ8399` |
| Kernel | Ubuntu `7.0.0-NN-generic` with a matching `linux-source-7.0.0` |
| Audio driver | legacy HDA (`snd_hda_intel`). This is the kernel's automatic choice on this platform. |

The `17aa:3906` variant ("YG speaker") uses byte-identical firmware, the same mainline quirk and the
same channel mapping. The driver and patch handle it already. The installer accepts it only with
`sudo ./scripts/install.sh --allow-untested`, because nobody has tested it with this package yet. If you
have a 3906, please open an issue with the diagnostics output, whether it works or not.

## Install

```bash
sudo apt install dkms linux-source-7.0.0 linux-headers-$(uname -r) curl i2c-tools
./scripts/fetch-firmware.sh            # downloads + verifies the tuning file from linux-firmware
sudo ./scripts/install.sh
# turn speaker volume to ~15-20%, then reboot
```

## After installing: verify

1. Run `sudo legion-aw88399-diagnostics`. It only reads and is safe. The kernel log section should show:
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
   - The kernel logs "module verification failed … tainting kernel" when Secure Boot is off.
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

If a boot ever goes wrong, add `modprobe.blacklist=snd_hda_scodec_aw88399_legion` to the kernel command line.

## Kernel updates (automatic)

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
| login check (`/etc/xdg/autostart/…`) | If you boot a 7.0 kernel without the driver, a desktop notification says so. It is silent when the fix is active, and on kernels that ship the mainline driver. |
| `sudo legion-aw88399-rebuild [kernel]` | The manual fix. It installs the exact matching `linux-source-7.0.0` and headers, with apt's usual confirmation, then builds and installs the driver. |

`linux-source-7.0.0` is marked as manually installed, so `apt autoremove` keeps it.

Once Ubuntu ships a kernel that includes the driver (7.3 or later), the package stops building by
design, and the stock driver uses the firmware already installed under `/lib/firmware/updates/awinic/`.

## What gets installed

| Path | What |
|---|---|
| `/lib/modules/$(uname -r)/updates/dkms/snd-hda-codec-alc269.ko` | Ubuntu's own `alc269.c` plus mainline's Legion fixup (patch in `dkms/patches/`) |
| `…/snd-soc-aw88399-lib.ko` | mainline `aw88399-lib.c` (3 marked 7.0-compat lines) |
| `…/snd-hda-scodec-aw88399-legion.ko` | HDA side-codec glue (`dkms/hda/`) |
| `/lib/firmware/updates/awinic/aw88399_acf_17aa390{6,7}.bin` | Awinic tuning file (from linux-firmware; the two names are the same file) |
| `/etc/modprobe.d/legion-aw88399.conf` | `blacklist snd_soc_aw88399` (the 7.0 ASoC driver would otherwise claim the device) |
| `/etc/apt/apt.conf.d/99legion-aw88399`, `/usr/lib/legion-aw88399/apt-hook` | rebuild after apt runs (see above) |
| `/etc/xdg/autostart/legion-aw88399-check.desktop`, `/usr/lib/legion-aw88399/login-check` | login notification if the driver is missing |
| `/usr/local/sbin/legion-aw88399-rebuild`, `/usr/local/sbin/legion-aw88399-diagnostics` | manual rebuild; read-only diagnostics for bug reports |

`scripts/uninstall.sh` removes all of these.

## How it works

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

[`.github/workflows/build.yml`](.github/workflows/build.yml) runs on every push and twice a week. It runs
in an Ubuntu 26.04 container and runs `prepare.sh`, then the module build, against the newest 7.0 kernel in:
- **`-updates`**: what users have now
- **`-proposed`**: kernels that haven't reached users yet

If an upcoming Ubuntu kernel changes `alc269.c` so that the patch no longer applies, the badge turns
red before that kernel reaches anyone's laptop. The workflow also re-checks that linux-firmware still
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
