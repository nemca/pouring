#! /usr/bin/env bash

# logging
log_file="/var/log/pouring.log"
function now_time() {
	date +"%Y-%m-%d %H:%M:%S"
}
function log_info() {
	echo -ne "`now_time` [INFO] $1" >> $log_file
}
function log_add() {
	echo -ne "$1" >> $log_file
}
function log_err() {
	echo -ne "\n`now_time` [ERR] $1" >> $log_file
}

# get config
path_to_confs="/etc/pouring"
function get_config_name() {
	sed -nre 's/(^config=|^.* config=)([^ ]+).*$/\2/; T; p' /proc/cmdline
}

# read config
config=`get_config_name`
if [[ -z $config ]]; then
	log_err "No configuration file is specified\n" && exit 1
fi
if [[ -f $path_to_confs/$config ]]; then
	source $path_to_confs/$config
else
	log_err "Can't read configuration file\n" && exit 1
fi

log_info "Start installation\n"

function mk_rootfs_part_pre() {
	log_info "Check local discks... "
	# check more than one disk
	if [[ `sfdisk -s | awk -F: "!/total/ && /$root_dev/ { print $1 }" | wc -l` < 1 ]]; then
		log_err "Not found disks" && exit 2
	fi
	log_add "ok\n"

	# Check already mounted dev, sys, proc 
	log_info "Check already mounted dev, sys, proc... "
	for mount_point in dev sys proc; do
		`mount | egrep "/mnt/$mount_point" 1>/dev/null 2>&1`
		if [[ $? == 0 ]]; then
			err_msg=`umount /mnt/$mount_point 2>&1 1>/dev/null`
			if [[ $? != 0 ]]; then
				log_err "\n/dev/$mount_point mount is mounted. Try unmount failed: $err_msg \n" && exit 2
			fi
		fi
	done
	log_add "ok\n"

	# check already mounted rootfs
	log_info "Check already mounted rootfs... "
	`mount | egrep "/dev/${root_dev}1" 1>/dev/null 2>&1`
	if [[ $? == 0 ]]; then
		log_add "umount /dev/${root_dev}1... "
		err_msg=`umount /dev/${root_dev}1 2>&1 1>/dev/null`
		if [[ $? != 0 ]]; then
			log_err "Disk /dev/sda1 is mounted. Try unmount failed: $err_msg \n" && exit 2
		fi
	fi
	log_add "ok\n"
}
mk_rootfs_part_pre

function mk_rootfs_part() {
	# create DOS partition table and a new partition
	log_info "Create DOS partition table and a new partition... "
	err_msg=`echo -e "o\nn\np\n1\n\n\nw" | fdisk /dev/$root_dev 2>&1 1>/dev/null`
	if [[ $? != 0 ]]; then
		log_err "\nCan't create new partition: $err_msg \n" && exit 3
	fi
	log_add "ok\n"
}
mk_rootfs_part

function mk_rootfs() {
	# create ext4 filesystem
	log_info "Create ext4 filesystem... "
	err_msg=`mkfs.ext4 /dev/${root_dev}1 2>&1 1>/dev/null`
	if [[ $? != 0 ]]; then
		log_err "\nCan't create filesystem: $err_msg \n" && exit 4
	fi
	log_add "ok\n"
}
mk_rootfs

function os_setup_pre() {
	# check mount dir
	log_info "Check mount dir... "
	if [[ ! -d /mnt ]]; then
		log_info "\nCreate direcrory /mnt \n"
		mkdir /mnt
	fi
	log_add "ok\n"

	# mount local disk
	log_info "Mount local disk... "
	err_msg=`mount -t ext4 /dev/${root_dev}1 /mnt/ 2>&1 1>/dev/null`
	if [[ $? != 0 ]]; then
		log_err "\nCan't mount local filesystem: $err_msg \n" && exit 5
	fi
	log_add "ok\n"
}
os_setup_pre

function os_setup() {
	# Copy and untar rootfs
	log_info "Copy and untar rootfs... "
	err_msg=`cd /mnt && tar xzf /srv/images/$archive 2>&1 1>/dev/null`
	if [[ $? != 0 ]]; then
		log_err "\nCan't extrat rootfs from the archive: $err_msg \n" && exit 6
	fi
	cd /
	log_add "ok\n"

	# Install GRUB
	log_info "Install GRUB... "
	err_msg=`grub-install --root-directory=/mnt /dev/$root_dev 2>&1 1>/dev/null`
	if [[ $? != 0 ]]; then
		log_err "\nCan't install grub: $err_msg \n" && exit 6
	fi
	log_add "ok\n"

	# Mount dev, sys, proc
	log_info "Mount dev, sys, proc... "
	err_msg=`mount -t proc none /mnt/proc && mount --bind /dev/ /mnt/dev/ && mount --bind /sys/ /mnt/sys/ 2>&1 1>/dev/null`
	if [[ $? != 0 ]]; then
		log_err "\nFailed mount dev,sys,proc: $err_msg \n" && exit 6
	fi
	log_add "ok\n"

	# Update GRUB
	log_info "Update GRUB in chroot... "
	err_msg=`chroot /mnt/ update-grub 2>&1 1>/dev/null`
	if [[ $? != 0 ]]; then
		log_err "\nFailed run update-grub in chroot: $err_msg \n" && exit 6
	fi
	log_add "ok\n"

	log_info "Set root password... "
	err_msg=`chroot /mnt/ echo "root:$root_password" | chpasswd 2>&1 1>/dev/null`
	if [[ $? != 0 ]]; then
		log_err "\nFailed set root password: $err_msg \n" && exit 6
	fi
	log_add "ok\n"

	log_info "Permit ssh root login... "
	err_msg=`chroot /mnt/ sed -i '/PermitRootLogin/s/no/yes/' /etc/ssh/sshd_config 2>&1 1>/dev/null`
	if [[ $? != 0 ]]; then
		log_err "\nFailed permit ssh root login: $err_msg \n" && exit 6
	fi
	log_add "ok\n"

	log_info "Installation was successful!\n"
}
os_setup

function os_setup_post() {
	# Show must go on!
	# Remove udev rules
	log_info "Remove udev rules... "
	err_msg=`chroot /mnt/ rm -f /etc/udev/rules.d/* 2>&1 1>/dev/null`
	if [[ $? != 0 ]]; then
		log_err "\nFailed remove udev rules: $err_msg \n" && exit 7
	fi
	log_add "ok\n"

	# Umount proc, sys, dev
	log_info "Umount dev, sys, proc... "
	for mount_point in proc sys dev; do
		err_msg=`umount /mnt/$mount_point 2>&1 1>/dev/null`
		if [[ $? != 0 ]]; then
			log_err "\n/dev/$mount_point mount is mounted. Try unmount failed: $err_msg \n" && exit 7
		fi
	done
	log_add "ok\n"

	# Umount rootfs
	log_info "Umount rootfs... "
	err_msg=`umount /dev/${root_dev}1 2>&1 1>/dev/null`
	if [[ $? != 0 ]]; then
		log_err "\n/dev/${root_dev}1 mount is mounted. Try unmount failed: $err_msg \n" && exit 7
	fi
	log_add "ok\n"
	log_info "DONE.\n"
}
os_setup_post

# reboot host
reboot
