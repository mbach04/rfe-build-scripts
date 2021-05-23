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

# reboot after installation is successfully completed
reboot

# installation will run in text mode
text

# activate network devices and configure with DHCP
network --bootproto=dhcp --noipv6

# create default user with sudo privileges
user --name={{ rfe_user | default('core') }} --groups=wheel --password={{ rfe_password | default('edge') }}

# set up the OSTree-based install with disabled GPG key verification, the base
# URL to pull the installation content, 'rhel' as the management root in the
# repo, and 'rhel/8/x86_64/edge' as the branch for the installation
ostreesetup --nogpg --url={{ rfe_tarball_url }}/repo/ --osname=rhel --remote=edge --ref=rhel/8/x86_64/edge


%post

##
## Create 'core' user home directory if it doesn't exist
##

mkdir -p /var/home/core
chown -R core: /var/home/core
%end

%post

##
## Configure the virtual router redundancy protocol for keepalived
##

# parse out boot parameters beginning with "vip"
#cmdline=`cat /proc/cmdline`
#params=(${cmdline// / })
#for param in "${params[@]}"; do
#  if [[ $param =~ "vip" ]]; then
#    eval $param
#  fi
#done

# write the keepalived config file with the vip params
#cat << EOF > /etc/keepalived/keepalived.conf
#vrrp_instance RFE_VIP {
#    state $vip_state
#    interface enp1s0
#    virtual_router_id 50
#    priority $vip_priority
#    advert_int 1
#    authentication {
#        auth_type PASS
#        auth_pass edge123
#    }
#    virtual_ipaddress {
#        $VIP_IP/$VIP_MASK
#    }
#}
#EOF
%end

%post

##
## Set the rpm-ostree update policy to automatically download and
## stage updates to be applied at the next reboot
##

# stage updates as they become available. This is highly recommended
echo AutomaticUpdatePolicy=stage >> /etc/rpm-ostreed.conf

##
## Create service and timer to periodically check if there's staged
## updates and then reboot to apply them.
##

# This systemd service runs one time and exits after each timer
# event. If there are staged updates to the operating system, the
# system is rebooted to apply them.
# LEAVE THIS HERE!!
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
## add our insecure registry to the list of registries we'll search for images
##

cat > /etc/containers/registries.conf <<EOF
[registries.search]
registries = ['quay.io', 'registry.access.redhat.com', 'registry.redhat.io', 'docker.io']
[registries.insecure]
registries = []
[registries.block]
registries = []
EOF
%end



%post

##
## Create a scale from zero systemd service for a container web
## server using socket activation
##

# create systemd user directories for rootless services, timers,
mkdir -p /var/home/core/.config/systemd/user/timers.target.wants
mkdir -p /var/home/core/.config/systemd/user/default.target.wants
mkdir -p /var/home/core/.config/systemd/user/multi-user.target.wants


##
## Create a service to launch the container workload and restart
## it on failure
##

cat > /var/home/core/.config/systemd/user/container-dc-metro-map.service <<EOF
# container-dc-metro-map.service
# autogenerated by Podman 3.0.2-dev
# Thu May 20 16:47:09 EDT 2021

[Unit]
Description=Podman container-dc-metro-map.service
Documentation=man:podman-generate-systemd(1)
#Wants=network.target
#After=network-online.target

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=always
TimeoutStopSec=70
ExecStartPre=/bin/rm -f %t/container-dc-metro-map.pid %t/container-dc-metro-map.ctr-id
ExecStart=/usr/bin/podman run --conmon-pidfile %t/container-dc-metro-map.pid --cidfile %t/container-dc-metro-map.ctr-id --cgroups=no-conmon -d --replace --name dc-metro-map -p 8080:8080 quay.io/mbach/dc-metro-map:edge1
ExecStop=/usr/bin/podman stop --ignore --cidfile %t/container-dc-metro-map.ctr-id -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/container-dc-metro-map.ctr-id
PIDFile=%t/container-dc-metro-map.pid
Type=forking

[Install]
WantedBy=multi-user.target default.target
EOF

##
## Create a service and timer to periodically check if the container
## image has been updated and then, if so, refresh the workload
##

# podman auto-update looks up containers with a specified
# "io.containers.autoupdate" label (i.e., the auto-update policy).
#
# If the label is present and set to “image”, Podman reaches out
# to the corresponding registry to check if the image has been updated.
# An image is considered updated if the digest in the local storage
# is different than the one in the remote registry. If an image must
# be updated, Podman pulls it down and restarts the systemd unit
# executing the container.

cat > /var/home/core/.config/systemd/user/podman-auto-update.service <<EOF

[Unit]
Description=Podman auto-update service
Documentation=man:podman-auto-update(1)

[Service]
ExecStart=/usr/bin/podman auto-update

[Install]
WantedBy=multi-user.target default.target
EOF


# This timer ensures podman auto-update is run every minute
cat > /var/home/core/.config/systemd/user/podman-auto-update.timer <<EOF
[Unit]
Description=Podman auto-update timer

[Timer]
# This example runs the podman auto-update daily within a two-hour
# randomized window to reduce system load
#OnCalendar=daily
#Persistent=true
#RandomizedDelaySec=7200

# activate every minute
OnBootSec=30
OnUnitActiveSec=30

[Install]
WantedBy=timers.target
EOF


# enable timer
ln -s /var/home/core/.config/systemd/user/podman-auto-update.timer /var/home/core/.config/systemd/user/timers.target.wants/podman-auto-update.timer
ln -s /var/home/core/.config/systemd/user/container-dc-metro-map.service /var/home/core/.config/systemd/user/default.target.wants/container-dc-metro-map.service
ln -s /var/home/core/.config/systemd/user/container-dc-metro-map.service /var/home/core/.config/systemd/user/multi-user.target.wants/container-dc-metro-map.service

# fix ownership of user local files and SELinux contexts
chown -R core: /var/home/core
restorecon -vFr /var/home/core

# enable linger so user services run whether user logged in or not
cat << EOF > /etc/systemd/system/enable-linger.service
[Service]
Type=oneshot
ExecStart=loginctl enable-linger core

[Install]
WantedBy=multi-user.target default.target
EOF

systemctl enable enable-linger.service
%end

%post

##
## Create a greenboot script to determine if an upgrade should
## succeed or rollback. At startup, the script writes the ostree commit
## hash to the files orig.txt, if it doesn't already exist, and
## current.txt, whether it exists or not. The two files are then
## compared. If those files are different, the upgrade fails after
## three attempts and the ostree image is rolled back. A upgrade can
## be allowed to succeed by deleting the orig.txt file prior to the
## upgrade attempt.
##

#mkdir -p /etc/greenboot/check/required.d
#cat > /etc/greenboot/check/required.d/01_check_upgrade.sh <<EOF
#!/bin/bash

#
# This test fails if the current commit identifier is different
# than the original commit
#

#if [ ! -f /etc/greenboot/orig.txt ]
#then
#    rpm-ostree status | grep -A2 '^\*' | grep Commit > /etc/greenboot/orig.txt
#fi
#
#rpm-ostree status | grep -A2 '^\*' | grep Commit > /etc/greenboot/current.txt
#
#diff -s /etc/greenboot/orig.txt /etc/greenboot/current.txt
#EOF

#chmod +x /etc/greenboot/check/required.d/01_check_upgrade.sh
%end
