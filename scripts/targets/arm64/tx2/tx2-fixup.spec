# Kernel config fixups for Cavium ThunderX2 (TX2) systems.

CONFIG_I2C_THUNDERX=m
CONFIG_MDIO_THUNDER=m
CONFIG_SPI_THUNDERX=m
CONFIG_THUNDER_NIC_VF=m
CONFIG_THUNDER_NIC_BGX=m
CONFIG_THUNDER_NIC_RGX=m

CONFIG_MODULE_SIG_KEY=""
CONFIG_SYSTEM_TRUSTED_KEYS=""

# Reserve space for a full relay triple:           xxx.xxx.xxx.xxx:xxxxx:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
CONFIG_CMDLINE="platform_args initrd=tdd-initrd tdd_relay_triple=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxz systemd.log_level=info  systemd.log_target=console          systemd.journald.forward_to_console=1 "
CONFIG_CMDLINE_FORCE=y
CONFIG_INITRAMFS_FORCE=n

# Ethernet drivers
CONFIG_QED=m
CONFIG_QED_SRIOV=y
CONFIG_QEDE=m

CONFIG_BNX2X=m
CONFIG_BNX2X_SRIOV=y

# storage drivers
CONFIG_RAID_ATTRS=m
#CONFIG_SCSI_MPT2SAS=m
CONFIG_SCSI_MPT2SAS_MAX_SGE=128
CONFIG_SCSI_MPT3SAS=m
CONFIG_SCSI_MPT3SAS_MAX_SGE=128

# For QEMU testing
CONFIG_HW_RANDOM_VIRTIO=m
