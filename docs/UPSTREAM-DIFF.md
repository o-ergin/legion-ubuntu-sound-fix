# Differences from mainline Linux (7.4-rc3)

## `dkms/lib/aw88399-lib.c` and `dkms/lib/aw88399.h`

These are mainline `sound/soc/codecs/aw88399-lib.c` and `include/sound/aw88399.h`. Three lines in
the `.c` file are changed, each marked `/* DKMS: ... */`:

1. `#include <sound/aw88399.h>` becomes `#include "aw88399.h"` (the header doesn't exist in 7.0).
2. `devm_kzalloc_flex(...)` becomes `devm_kzalloc(dev, struct_size(...), GFP_KERNEL)`. 7.0 lacks the helper.
3. `devm_kzalloc_obj(...)` becomes `devm_kzalloc(dev, sizeof(*aw_dev), GFP_KERNEL)`. Same reason.

The aw88395 parser headers are taken from the target kernel's own source at build time.

## `dkms/patches/alc269-legion-aw88399.patch`

This patch applies to Ubuntu's 7.0 `alc269.c`.

- `alc287_fixup_legion_16iax10h_aw88399()` is mainline's function, copied verbatim.
- The quirks `HDA_CODEC_QUIRK(0x17aa, 0x3906/0x3907, …)` and the model name
  `alc287-lenovo-legion-aw88399` are placed as in mainline.
- **Changed:** the chained binding fixup uses `comp_generic_fixup(cdc, action, "i2c", "AWDZ8399", "-%s:00", 1)`.
  Mainline uses `"-%s:00-aw88399-hda.%d", 2`.

The helpers the Legion fixup calls (headset mode and jack, mic boost limit) behave identically in 7.0
for the ALC287.

## `dkms/hda/aw88399_hda_legion.c`

This file replaces mainline's `aw88399_hda.c` and `aw88399_hda_i2c.c`.

**Topology.** Mainline expects two I2C clients created by `serial-multi-instantiate`. That requires
`AWDZ8399` in the built-in `drivers/acpi/scan.c`, which DKMS cannot change. Instead, this driver:
- binds the ACPI client `i2c-AWDZ8399:00` (`0x35`)
- creates `0x34` with `devm_i2c_new_dummy_device()`
- registers **one** component for both amps

**Kept from mainline, per amp:**
- `index = addr - 0x34`, `channel = index`, swapped for the same SSID table. That gives `0x35` → ch0 (left) and `0x34` → ch1.
- Firmware `awinic/aw88399_acf_<_SUB lowercase>.bin`.
- Init order: `hw_reset`, then `aw88399_init` (chip-ID check), then `aw88399_dev_set_channel`, then `aw88399_request_firmware_file`.
- Hooks: PREPARE does a synchronous `aw88399_start`. CLEANUP and CLOSE call `aw88399_stop`.
- System suspend: stop the amps and set `fw_needs_reload`.

**Deviations:**
- **No runtime PM.** The amps only run between PREPARE and CLEANUP/CLOSE.
- **No amp restart in the resume callback.** HDA PCMs cannot resume, so userspace re-prepares, and the PREPARE hook starts the amps once the codec streams again. This avoids failing start retries, with DSP reloads, while I2S is still stopped.
- **Locking.** Start and stop are serialized with each amp's `core->lock`.
- **Reset.** Reset runs once, before both amps. It is a no-op on this machine, which has no reset GPIO.
