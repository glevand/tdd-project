# Kernel config fixups for powerpc systems.

CONFIG_MODULE_SIG_KEY=""
CONFIG_SYSTEM_TRUSTED_KEYS=""

# Reserve space for a full relay triple:           xxx.xxx.xxx.xxx:xxxxx:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
CONFIG_CMDLINE_BOOL=y
CONFIG_CMDLINE="platform_args root=/dev/ram0 console=hvc0 splash=off tdd_relay_triple=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxz systemd.log_level=info  systemd.log_target=console          systemd.journald.forward_to_console=1"
CMDLINE_FROM_BOOTLOADER=y
#CONFIG_CMDLINE_FORCE=y
#CONFIG_INITRAMFS_FORCE=n

# For QEMU testing
CONFIG_HW_RANDOM_VIRTIO=m
