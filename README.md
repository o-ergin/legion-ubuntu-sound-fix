# Legion Pro 7 16IAX10H: full speaker sound on Ubuntu 7.0 kernels (AW88399 DKMS backport)

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
> Other kernels and the `17aa:3906` variant are untested.

## Supported configuration (the installer refuses anything else)

| | |
|---|---|
| Laptop | Lenovo Legion Pro 7 16IAX10H, DMI product `83F5` |
| Codec | Realtek ALC287, codec SSID `17aa:3907` ("Y7P for Veco speaker") |
| Amps | 2× AW88399 at I2C `0x35` and `0x34`, ACPI `AWDZ8399` |
| Kernel | Ubuntu `7.0.0-NN-generic` with a matching `linux-source-7.0.0` |
| Audio driver | legacy HDA (`snd_hda_intel`). This is the kernel's automatic choice on this platform. |

The `17aa:3906` variant ("YG speaker") uses the same firmware and the mainline quirk. The installer
still only accepts `3907`, because that is the only variant tested here.

## Install

```bash
sudo apt install dkms linux-source-7.0.0 curl
./scripts/fetch-firmware.sh            # downloads + verifies the tuning file from linux-firmware
sudo ./scripts/install.sh
# turn speaker volume to ~15-20%, then reboot
```

## After installing: verify

1. Run `sudo ./scripts/check-amps.sh`. It only reads registers and is safe. The log should show:
   - `picked fixup … for codec SSID 17aa:3907`
   - `0x34: loaded firmware awinic/aw88399_acf_17aa3907.bin, channel 1`
   - `0x35: … channel 0`
   - `AW88399 Bound - SSID: 17AA3907`
2. Play a test sound at low volume: `speaker-test -c 2 -t wav -l 1`.
   - While it plays, run `check-amps.sh` again. Both amps should show `power=ON pll_locked=yes`.
   - "Front Left" should come from the left side, including its bass.
   - To test each woofer on its own, play a 150 Hz tone on one channel. Use `-s 1` for left and
     `-s 2` for right:
     `timeout 4 speaker-test -c 2 -t sine -f 150 -s 1`
     80 Hz is mostly inaudible on laptop woofers.
   - The amps stay powered while any stream is open, even a paused browser tab. That is normal.
   - The kernel logs "module verification failed … tainting kernel" when Secure Boot is off.
     That is expected for an unsigned out-of-tree module and harmless.
3. Move the volume slider. The bass must follow it.
4. Plug in headphones. All speakers must go silent.
5. Suspend, resume, and play again.

If something fails, the woofers stay silent and the tweeters keep working as before.

## Uninstall

```bash
sudo ./scripts/uninstall.sh && reboot
```

If a boot ever goes wrong, add `modprobe.blacklist=snd_hda_scodec_aw88399_legion` to the kernel command line.

## Kernel updates

`dkms/prepare.sh` rebuilds only from the **exact** Ubuntu source of the target kernel. It refuses to
build, leaving the stock drivers (tweeters only) in place, if any of these is true:
- the `linux-source-7.0.0` version doesn't match the kernel
- the patch doesn't apply with zero fuzz
- the kernel already contains AW88399 support

After an Ubuntu kernel update:

```bash
sudo apt install linux-source-7.0.0 && sudo dkms autoinstall
```

Once Ubuntu ships a kernel that includes the driver (7.3 or later), the package stops building by
design, and the stock driver uses the firmware already installed under `/lib/firmware/updates/awinic/`.

## What gets installed

| Path | What |
|---|---|
| `/lib/modules/$(uname -r)/updates/dkms/snd-hda-codec-alc269.ko` | Ubuntu's own `alc269.c` plus mainline's Legion fixup (patch in `dkms/patches/`) |
| `…/snd-soc-aw88399-lib.ko` | mainline `aw88399-lib.c` (3 marked 7.0-compat lines) |
| `…/snd-hda-scodec-aw88399-legion.ko` | HDA side-codec glue (`dkms/hda/`) |
| `/lib/firmware/updates/awinic/aw88399_acf_17aa3907.bin` | Awinic tuning file (from linux-firmware) |
| `/etc/modprobe.d/legion-aw88399.conf` | `blacklist snd_soc_aw88399` (the 7.0 ASoC driver would otherwise claim the device) |

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
