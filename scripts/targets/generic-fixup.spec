# Kernel config fixups for generic systems.

CONFIG_MODULE_SIG_KEY=""
CONFIG_SYSTEM_TRUSTED_KEYS=""

# Reserve space for a full relay triple:           xxx.xxx.xxx.xxx:xxxxx:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
CONFIG_CMDLINE_BOOL=y
CONFIG_CMDLINE="platform_args initrd=tdd-initrd tdd_relay_triple=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxz systemd.log_level=info  systemd.log_target=console          systemd.journald.forward_to_console=1 "
CONFIG_CMDLINE_FORCE=y
CONFIG_INITRAMFS_FORCE=n

# For QEMU testing
CONFIG_HW_RANDOM_VIRTIO=m
