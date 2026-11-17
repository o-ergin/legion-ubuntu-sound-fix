# Investigation log

How the "thin speakers on Ubuntu" problem on the Legion Pro 7 16IAX10H was diagnosed. Each entry
says how it was verified. Wrong conclusions reached along the way are recorded below, with their
corrections.

## 1. Hardware identification (verified on the machine)

- DMI: `LENOVO 83F5`, product version `Legion Pro 7 16IAX10H`.
- Audio hardware:
  - Intel 800-series ACE HDA controller (`8086:7f50`, Arrow Lake-S)
  - Realtek ALC287 codec (`10ec0287`), subsystem `17aa:3907`
  - NVIDIA HDMI audio
- Kernel 7.0.0-43-generic, legacy HDA driver (`snd_hda_intel`), PipeWire 1.6.
- The stock driver logs `ALC287: picked fixup  for PCI SSID 17aa:0000`. That is the catch-all
  `SND_PCI_QUIRK_VENDOR(0x17aa, "Lenovo XPAD", …)` entry, so there is no model-specific setup.
- Codec pins:
  - `0x14` Speaker, on DAC `0x02`, which has a volume control
  - `0x17` Bass Speaker, on DAC **`0x06`, which has no volume control** (`wcaps 0x411`, no amp)
  - `0x21` Headphone

## 2. ACPI (verified from the machine's DSDT)

```
Device (SPKR) in \_SB.PC02.I2C2
  _HID/_CID "AWDZ8399", _SUB "17AA3907" (SPID==1) else "17AA3906"
  _CRS: I2cSerialBusV2 0x35, I2cSerialBusV2 0x34 (400 kHz),
        GpioIo (IoRestrictionInputOnly), GpioInt (edge, active low)
  _DSM 1cc539cd-5a26-4288-a572-25c5744ebf1b:
        fn0 -> 02 35 02 34, fn1 -> 02, fn3 -> 01 F4 0B 2C 10 48 0D F8 11
```

- The Linux 7.0 I2C core only instantiates the first resource (`i2c-AWDZ8399:00` at `0x35`).
- The NHLT table is **empty** (zero endpoints). So the kernel's automatic DSP-driver selection for
  ARL-S (`FLAG_SOF_ONLY_IF_DMIC_OR_SOUNDWIRE`) picks legacy HDA.
- The GpioIo pin is input-only. debugfs showed no GPIO held for AWDZ8399, so the drivers' optional
  "reset" GPIO lookup returns nothing on this machine.

## 3. Amplifier registers (read-only, via `i2cget`)

- Both `0x35` and `0x34` return chip ID `0x2183` (AW88399).
- Idle *and* during playback (stream RUNNING on the ALC287), both amps read:
  - `SYSCTRL = 0xe307`: power-down bit set
  - `SYSST = 0x0820`: NOCLKS set

  So the amps are **off**, and the audible sound comes from the tweeters on the codec's own pins.

## 4. Firmware

- Lenovo's "Realtek Audio Driver for Windows 11 – Legion Pro 7 16IAX10H" (6.0.9882.1) contains:
  - Realtek codec drivers (`HDXLVSST.inf`, which lists `17AA3907 ; Y7P for Veco speaker`)
  - Intel OED
  - Nahimic and Elevoc processing
  - Awinic's amp driver (`AwinicSmartKAmps.inf`, binding `ACPI\AWDZ8399`) with **`AWDZ8399.bin`**

  The download's SHA-256 matched Lenovo's listing.
- `AWDZ8399.bin`:
  - is an Awinic ACF container (magic `0x0A15F908`, header v0)
  - has 4 entries: default type, dev_index 0/1, profiles 0/1, multi-bin
  - its two channels differ in only 4 bytes
  - its two profiles are identical
- SHA-256 `1e927c9bca76d868181c0f81df2bccef3cf19c7d0910219f229360c87babd42c` is **byte-identical**
  to linux-firmware's `awinic/aw88399_acf_17aa3907.bin` and `…_17aa3906.bin`.

## 5. Upstream status (read from primary sources)

- **Mainline (7.4-rc3):**
  - `sound/hda/codecs/side-codecs/aw88399_hda*.c` and `sound/soc/codecs/aw88399-lib.c`
  - `ALC287_FIXUP_LENOVO_LEGION_AW88399`, with codec quirks for 17aa:3906 and 17aa:3907
  - firmware name `awinic/aw88399_acf_<_SUB lowercase>.bin`
- **The original community project** describes the final architecture as *legacy HDA* with AW88399
  side codecs. It says `snd_intel_dspcfg.dsp_driver=3` (SOF) is "no longer necessary". An older
  DKMS project still says SOF is required; that comes from an earlier generation of the patch.
- **Mainline vs Ubuntu 7.0 AW88399 device code**, compared function by function:
  - 34 functions are identical
  - the functional differences are:
    - BSTS (boost-finished) check skipped when EN_HVBAT/EPS is set
    - `fw_needs_reload` after suspend
    - firmware name passed in by the caller
    - ACPI channel fallback
  - the aw88395 parser is identical apart from allocator helpers and an annotation

## 6. Mistakes made and corrected during this investigation

| Initial claim | Correction |
|---|---|
| Sound is thin because the amps run on default settings | The amps are powered down. Only the codec-driven tweeters play. |
| "NOCLKS during playback" proves the amps get no I2S clock | Not evidence: the clock detector reads that way while the amp is powered down. Mainline works in legacy HDA mode. |
| A hand-written driver (v1, never installed) was fine | It lacked the `0x17`→DAC `0x02` reroute, so the woofer level would have ignored the volume slider. It also lacked the EPS/BSTS fix, so the amps would most likely never have started. Replaced by this mainline backport. |
| `dmic_detect=0` in modprobe.d was a useless leftover | It forces legacy HDA, which is also the automatic choice here. Harmless, left alone. |
| Windows uses Dolby | The Windows package contains Nahimic and Elevoc. |

Lesson: check upstream before writing driver code.
