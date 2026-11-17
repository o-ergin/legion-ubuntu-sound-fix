// SPDX-License-Identifier: GPL-2.0-only
//
// AW88399 HDA side-codec glue for Lenovo Legion Pro 7 16IAX10H on Linux 7.0 (DKMS)
//
// Backport adaptation of mainline sound/hda/codecs/side-codecs/aw88399_hda.c
// (Yakov Till, Marco Giunta), which is "Based on cs35l41_hda.c and aw88399.c".
//
// Why this differs from mainline:
//   Mainline creates one I2C client per amplifier through serial-multi-instantiate,
//   which needs "AWDZ8399" in the built-in drivers/acpi/scan.c. A DKMS module cannot
//   change built-in code, so on 7.0 the ACPI core creates a single client
//   (i2c-AWDZ8399:00, first I2cSerialBus resource = 0x35). This driver binds that
//   client, creates the second amplifier (0x34) as an ancillary client, and registers
//   both amplifiers as ONE HDA component (Realtek side: comp_generic_fixup(...,
//   "-%s:00", 1), the same pattern the TAS2781 single-device laptops use).
//
// What is kept identical to mainline, per amplifier:
//   index = addr - 0x34, channel = index, channel swap for the same SSID table,
//   firmware "awinic/aw88399_acf_<acpi _SUB, lowercase>.bin", init order
//   (hw_reset, aw88399_init, aw88399_dev_set_channel, aw88399_request_firmware_file),
//   playback hook actions (PREPARE: synchronous aw88399_start; CLEANUP/CLOSE:
//   aw88399_stop), and fw_needs_reload on system suspend.
//
// Deliberate deviations (see README-v2.md):
//   - no runtime PM: amps are only ever powered between PREPARE and CLEANUP/CLOSE;
//   - on system resume the amps are NOT restarted here; HDA PCMs cannot resume, so
//     userspace must re-prepare the stream, and the PREPARE hook starts the amps
//     once the codec is streaming again (avoids failing start retries with
//     DSP reloads while the I2S clock is still stopped);
//   - start/stop are serialized with each amplifier's own core->lock.
//

#include <linux/acpi.h>
#include <linux/cleanup.h>
#include <linux/component.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/regmap.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/string_helpers.h>
#include <sound/hda_codec.h>
#include "../codecs/generic.h"
#include "../codecs/side-codecs/hda_component.h"
#include "../lib/aw88399.h"

#define AW88399_HDA_I2C_BASE_ADDR	0x34	/* mainline: index = addr - 0x34 */
#define AW88399_LEGION_ADDR_A		0x34
#define AW88399_LEGION_ADDR_B		0x35
#define AW88399_LEGION_NUM_AMPS		2

/* Same SSID list as mainline aw88399_prop_model_table (all use aw88399_swap_channels). */
static const char * const aw88399_legion_swap_ssids[] = {
	"17AA3906", "17AA3907", "17AA3927", "17AA3928", "17AA3934",
	"17AA3935", "17AA3936", "17AA3937", "17AA3938", "17AA3939",
};

struct aw88399_legion_amp {
	struct i2c_client *client;
	struct regmap *regmap;
	struct aw88399 *core;
	int index;
	int channel;
};

struct aw88399_legion {
	struct device *dev;
	struct gpio_desc *reset_gpio;
	const char *acpi_subsystem_id;
	struct aw88399_legion_amp amps[AW88399_LEGION_NUM_AMPS];	/* [0]=0x34, [1]=0x35 */
	bool playing;
};

static void aw88399_legion_start_all(struct aw88399_legion *lg)
{
	int i;

	for (i = 0; i < AW88399_LEGION_NUM_AMPS; i++) {
		struct aw88399 *core = lg->amps[i].core;

		mutex_lock(&core->lock);
		aw88399_start(core, AW88399_SYNC_START);
		mutex_unlock(&core->lock);
	}
}

static void aw88399_legion_stop_all(struct aw88399_legion *lg)
{
	int i, ret;

	for (i = 0; i < AW88399_LEGION_NUM_AMPS; i++) {
		struct aw88399 *core = lg->amps[i].core;

		mutex_lock(&core->lock);
		ret = aw88399_stop(core->aw_pa);
		mutex_unlock(&core->lock);
		if (ret)
			dev_err(lg->dev, "Failed to stop amplifier 0x%02x: %d\n",
				lg->amps[i].client->addr, ret);
	}
}

static void aw88399_legion_playback_hook(struct device *dev, int action)
{
	struct aw88399_legion *lg = dev_get_drvdata(dev);

	dev_dbg(lg->dev, "Playback action: %d\n", action);

	switch (action) {
	case HDA_GEN_PCM_ACT_OPEN:
		lg->playing = true;
		break;
	case HDA_GEN_PCM_ACT_PREPARE:
		aw88399_legion_start_all(lg);
		break;
	case HDA_GEN_PCM_ACT_CLEANUP:
		aw88399_legion_stop_all(lg);
		break;
	case HDA_GEN_PCM_ACT_CLOSE:
		aw88399_legion_stop_all(lg);
		lg->playing = false;
		break;
	default:
		dev_warn(lg->dev, "Unsupported action: %d\n", action);
		break;
	}
}

static int aw88399_legion_bind(struct device *dev, struct device *master, void *master_data)
{
	struct aw88399_legion *lg = dev_get_drvdata(dev);
	struct hda_component_parent *parent = master_data;
	struct hda_component *comp;

	comp = hda_component_from_index(parent, 0);
	if (!comp)
		return -EINVAL;

	if (comp->dev)
		return -EBUSY;

	comp->dev = dev;
	strscpy(comp->name, dev_name(dev), sizeof(comp->name));
	comp->playback_hook = aw88399_legion_playback_hook;

	dev_info(lg->dev, "AW88399 Bound - SSID: %s, 0x%02x->ch%d, 0x%02x->ch%d\n",
		 lg->acpi_subsystem_id,
		 lg->amps[0].client->addr, lg->amps[0].channel,
		 lg->amps[1].client->addr, lg->amps[1].channel);

	return 0;
}

static void aw88399_legion_unbind(struct device *dev, struct device *master, void *master_data)
{
	struct aw88399_legion *lg = dev_get_drvdata(dev);
	struct hda_component_parent *parent = master_data;
	struct hda_component *comp;

	comp = hda_component_from_index(parent, 0);
	if (comp && (comp->dev == dev))
		memset(comp, 0, sizeof(*comp));

	/* Never leave the amplifiers running without a codec to control them. */
	aw88399_legion_stop_all(lg);
	lg->playing = false;

	dev_dbg(lg->dev, "Unbound from HDA codec\n");
}

static const struct component_ops aw88399_legion_comp_ops = {
	.bind = aw88399_legion_bind,
	.unbind = aw88399_legion_unbind,
};

/* Per-amplifier init, same order as mainline aw88399_hda_init(). */
static int aw88399_legion_amp_init(struct aw88399_legion *lg, struct aw88399_legion_amp *amp,
				   bool swap, bool do_reset)
{
	struct device *dev = &amp->client->dev;
	struct aw88399 *core;
	int ret;

	amp->regmap = devm_regmap_init_i2c(amp->client, &aw88399_remap_config);
	if (IS_ERR(amp->regmap))
		return dev_err_probe(lg->dev, PTR_ERR(amp->regmap),
				     "0x%02x: failed to obtain regmap\n", amp->client->addr);

	amp->index = amp->client->addr - AW88399_HDA_I2C_BASE_ADDR;
	amp->channel = swap ? 1 - amp->index : amp->index;

	core = devm_kzalloc(dev, sizeof(*core), GFP_KERNEL);
	if (!core)
		return -ENOMEM;

	mutex_init(&core->lock);
	core->reset_gpio = lg->reset_gpio;
	core->regmap = amp->regmap;

	/* Both amps hang off one ACPI node; reset (if any) only once, before either init. */
	if (do_reset)
		aw88399_hw_reset(core);

	ret = aw88399_init(core, amp->client, amp->regmap);	/* verifies chip ID first */
	if (ret)
		return ret;

	/* Set channel BEFORE loading firmware so ACF parser sees correct value */
	aw88399_dev_set_channel(core, amp->channel);

	char *fw_name __free(kfree) =
		kasprintf(GFP_KERNEL, "awinic/aw88399_acf_%s.bin", lg->acpi_subsystem_id);
	if (!fw_name)
		return -ENOMEM;
	string_lower(fw_name, fw_name);

	ret = aw88399_request_firmware_file(core, fw_name);
	if (ret)
		return ret;

	dev_info(lg->dev, "0x%02x: loaded firmware %s, channel %d\n",
		 amp->client->addr, fw_name, amp->channel);

	amp->core = core;
	return 0;
}

static int aw88399_legion_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct acpi_device *adev = ACPI_COMPANION(dev);
	struct i2c_client *other;
	struct aw88399_legion *lg;
	bool swap = false;
	int i, n, ret;

	if (!adev || !strstr(dev_name(dev), "AWDZ8399"))
		return -ENODEV;

	/* Only the exact topology this backport was written for: one node, two amps. */
	n = i2c_acpi_client_count(adev);
	if (n != AW88399_LEGION_NUM_AMPS ||
	    (client->addr != AW88399_LEGION_ADDR_A && client->addr != AW88399_LEGION_ADDR_B))
		return dev_err_probe(dev, -ENODEV,
				     "unexpected topology (%d I2C resources, addr 0x%02x)\n",
				     n, client->addr);

	lg = devm_kzalloc(dev, sizeof(*lg), GFP_KERNEL);
	if (!lg)
		return -ENOMEM;
	lg->dev = dev;
	dev_set_drvdata(dev, lg);

	lg->reset_gpio = devm_gpiod_get_optional(dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(lg->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(lg->reset_gpio), "Failed to get reset GPIO\n");

	const char *sub __free(kfree) = acpi_get_subsystem_id(ACPI_HANDLE(dev));
	if (IS_ERR_OR_NULL(sub))
		return dev_err_probe(dev, -ENODEV, "ACPI subsystem ID not available\n");

	lg->acpi_subsystem_id = devm_kstrdup(dev, sub, GFP_KERNEL);
	if (!lg->acpi_subsystem_id)
		return -ENOMEM;

	for (i = 0; i < ARRAY_SIZE(aw88399_legion_swap_ssids); i++) {
		if (!strcasecmp(aw88399_legion_swap_ssids[i], lg->acpi_subsystem_id)) {
			dev_info(dev, "Applying properties for SSID %s\n", lg->acpi_subsystem_id);
			swap = true;
			break;
		}
	}

	other = devm_i2c_new_dummy_device(dev, client->adapter,
					  client->addr == AW88399_LEGION_ADDR_A ?
					  AW88399_LEGION_ADDR_B : AW88399_LEGION_ADDR_A);
	if (IS_ERR(other))
		return dev_err_probe(dev, PTR_ERR(other), "cannot create second amp client\n");

	lg->amps[0].client = client->addr == AW88399_LEGION_ADDR_A ? client : other;
	lg->amps[1].client = client->addr == AW88399_LEGION_ADDR_B ? client : other;

	for (i = 0; i < AW88399_LEGION_NUM_AMPS; i++) {
		ret = aw88399_legion_amp_init(lg, &lg->amps[i], swap, i == 0);
		if (ret)
			return dev_err_probe(dev, ret, "Chip initialization failed (0x%02x)\n",
					     lg->amps[i].client->addr);
	}

	ret = component_add(dev, &aw88399_legion_comp_ops);
	if (ret)
		return dev_err_probe(dev, ret, "Failed to register component\n");

	dev_info(dev, "AW88399 HDA side codec registered successfully (2 amplifiers)\n");
	return 0;
}

static void aw88399_legion_remove(struct i2c_client *client)
{
	struct aw88399_legion *lg = dev_get_drvdata(&client->dev);

	component_del(&client->dev, &aw88399_legion_comp_ops);	/* unbind stops the amps */
	aw88399_legion_stop_all(lg);
}

static int aw88399_legion_system_suspend(struct device *dev)
{
	struct aw88399_legion *lg = dev_get_drvdata(dev);
	int i;

	if (lg->playing)
		aw88399_legion_stop_all(lg);

	/* As mainline: reload DSP firmware on the first start after resume. */
	for (i = 0; i < AW88399_LEGION_NUM_AMPS; i++)
		lg->amps[i].core->fw_needs_reload = true;

	return 0;
}

static int aw88399_legion_system_resume(struct device *dev)
{
	struct aw88399_legion *lg = dev_get_drvdata(dev);

	aw88399_hw_reset(lg->amps[0].core);	/* no-op unless a reset GPIO exists */
	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(aw88399_legion_pm_ops,
				aw88399_legion_system_suspend, aw88399_legion_system_resume);

static const struct acpi_device_id aw88399_legion_acpi_match[] = {
	{ "AWDZ8399", 0 },
	{ }
};
MODULE_DEVICE_TABLE(acpi, aw88399_legion_acpi_match);

static struct i2c_driver aw88399_legion_i2c_driver = {
	.driver = {
		.name = "aw88399-hda-legion",
		.acpi_match_table = aw88399_legion_acpi_match,
		.pm = pm_sleep_ptr(&aw88399_legion_pm_ops),
	},
	.probe = aw88399_legion_probe,
	.remove = aw88399_legion_remove,
};
module_i2c_driver(aw88399_legion_i2c_driver);

MODULE_DESCRIPTION("AW88399 HDA side codec glue for Lenovo Legion (DKMS backport for Linux 7.0)");
MODULE_IMPORT_NS("SND_SOC_AW88399_LIB");
MODULE_LICENSE("GPL");
MODULE_FIRMWARE("awinic/aw88399_acf_*.bin");
