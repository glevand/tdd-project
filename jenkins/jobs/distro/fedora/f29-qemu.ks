#version=DEVEL
ignoredisk --only-use=vda
# System bootloader configuration
bootloader --location=mbr --boot-drive=vda --append "text"
autopart --type=plain
# Partition clearing information
clearpart --drives=vda --all
# Use text mode install
text
# Use network installation
url --url="https://dl.fedoraproject.org/pub/fedora/linux/development/29/Server/aarch64/os/"
# Keyboard layouts
keyboard --vckeymap=us --xlayouts=''
# System language
lang en_US.UTF-8

# Network information
network  --bootproto=dhcp --device=eth0 --ipv6=auto --activate
network  --hostname=f29-install-test
# Root password
rootpw --plaintext r
# Run the Setup Agent on first boot
firstboot --disable
# Do not configure the X Window System
skipx
# System services
services --enabled="chronyd"
# System timezone
timezone America/Los_Angeles --isUtc
user --groups=sudo,docker,wheel --name=tdd-tester

firewall --disabled

poweroff

%packages
@^server-product-environment

%end

#%addon com_redhat_kdump --disable --reserve-mb='128'
#
#%end

%anaconda
pwpolicy root --minlen=6 --minquality=1 --notstrict --nochanges --notempty
pwpolicy user --minlen=6 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=6 --minquality=1 --notstrict --nochanges --notempty
%end

%post

# Setup ssh keys
mkdir -p -m0700 /root/.ssh/
cat >> /root/.ssh/authorized_keys << EOF
@@ssh-keys@@
EOF
chmod 0600 /root/.ssh/authorized_keys
restorecon -R /root/.ssh/

%end
