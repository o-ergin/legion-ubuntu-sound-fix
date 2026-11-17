# legion-aw88399 2.1 - AW88399 woofer amps for Lenovo Legion Pro 7 16IAX10H on Linux 7.0
obj-m := snd-hda-codec-alc269.o snd-soc-aw88399-lib.o snd-hda-scodec-aw88399-legion.o
snd-hda-codec-alc269-y := codecs/realtek/alc269.o
snd-soc-aw88399-lib-y := lib/aw88399-lib.o
snd-hda-scodec-aw88399-legion-y := hda/aw88399_hda_legion.o
ccflags-y := -I$(src)/common

KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
