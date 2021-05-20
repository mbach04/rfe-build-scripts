##
## Initial ostree install
##

# set locale defaults for the Install
lang en_US.UTF-8
keyboard us
timezone UTC

# initialize any invalid partition tables and destroy all of their contents
zerombr

# erase all disk partitions and create a default label
clearpart --all --initlabel

# automatically create xfs partitions with no LVM and no /home partition
autopart --type=plain --fstype=xfs --nohome

# poweroff after installation is successfully completed
reboot

# installation will run in text mode
text

# activate network devices and configure with DHCP
network --bootproto=dhcp --noipv6

# Kickstart requires that we create default user 'core' with sudo
# privileges using password 'edge'
user --name=core --groups=wheel --password=edge --homedir=/var/home/core


# set up the OSTree-based install with disabled GPG key verification, the base
# URL to pull the installation content, 'rhel' as the management root in the
# repo, and 'rhel/8/x86_64/edge' as the branch for the installation
ostreesetup --nogpg --osname=rhel --remote=edge --url=http://httpd.apps.cluster-ad0c.ad0c.sandbox1728.opentlc.com/repo/ --ref=rhel/8/x86_64/edge


%post
##
## Create 'core' user home directory if it doesn't exist
##

mkdir -p /var/home/core
chown -R core: /var/home/core

# fix ownership of user local files and SELinux contexts
chown -R core: /var/home/core
restorecon -vFr /var/home/core

%end


%post
# Set the update policy to automatically download and stage updates to be
# applied at the next reboot
#stage updates as they become available. This is highly recommended
echo AutomaticUpdatePolicy=stage >> /etc/rpm-ostreed.conf
%end



%post
cat > /etc/systemd/system/dc-metro-map.service << 'EOF'
[Unit]
Description=Podman container-dc-metro-map.service
Requires=network.target
Requires=network-online.target
After=network-online.target
After=nss-lookup.target

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
ExecStartPre=/bin/rm -f %t/container-dc-metro-map.pid %t/container-dc-metro-map.ctr-id
ExecStart=/usr/bin/podman run --conmon-pidfile %t/container-dc-metro-map.pid --cidfile %t/container-dc-metro-map.ctr-id --cgroups=no-conmon --replace -d --label io.containers.autoupdate=image --name dc-metro-map -p 8080:8080 quay.io/mbach/dc-metro-map:latest
ExecStop=/usr/bin/podman stop --ignore --cidfile %t/container-dc-metro-map.ctr-id -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/container-dc-metro-map.ctr-id
PIDFile=%t/container-dc-metro-map.pid
KillMode=none
Type=forking

[Install]
WantedBy=multi-user.target default.target
EOF

systemctl enable dc-metro-map.service

##
## Create service and timer to periodically check if there's staged
## updates and then reboot to apply them.
##

# This systemd service runs one time and exits after each timer
# event. If there are staged updates to the operating system, the
# system is rebooted to apply them.
cat > /etc/systemd/system/applyupdate.service << 'EOF'
[Unit]
Description=Apply Update Check

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'if [[ $(rpm-ostree status -v | grep "Staged: yes") ]]; then systemctl --message="Applying OTA update" reboot; else logger "Running latest available update"; fi'
EOF

# This systemd timer activates every minute to check for staged
# updates to the operating system
cat > /etc/systemd/system/applyupdate.timer <<EOF
[Unit]
Description=Daily Update Reboot Check.

[Timer]
# activate every minute
OnBootSec=30
OnUnitActiveSec=30

#weekly example for Sunday at midnight
#OnCalendar=Sun *-*-* 00:00:00

[Install]
WantedBy=multi-user.target
EOF

# The rpm-ostreed-automatic.timer and accompanying service will
# check for operating system updates and stage them. The applyupdate.timer
# will reboot the system to force an upgrade.
systemctl enable rpm-ostreed-automatic.timer applyupdate.timer
%end

%post
## 
## configure registries
##

cat > /etc/containers/registries.conf <<EOF
[registries.search]
registries = ['quay.io', 'registry.access.redhat.com', 'registry.redhat.io', 'docker.io']
[registries.insecure]
[registries.block]
registries = []
EOF
%end
