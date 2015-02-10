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
function get_config_name {
	boot_parm=`sed 's/ /\n/g' /proc/cmdline 2>/dev/null`

	for st in $boot_parm; do
		echo $st | egrep 'conf=(.*)' 1>/dev/null 2>&1
		if [[ $? -eq 0 ]]; then
			echo $st | sed 's/conf=//' 2>/dev/null
		fi
	done
}

config=`get_config_name()`
if [[ -f $path_to_confs/$config ]]; then
	source $path_to_confs/$config
else
	log_err "Can't read configuration file\n"
fi

log_info "Start installation\n"

# check more than one disk
log_info "Check local discks... "
if [[ `sfdisk -s | awk -F: '!/total/ && /dev/ { print $1 }' | wc -l` < 1 ]]; then
	log_err "Not found disks"
	exit 1
fi
log_add "passed\n"

# Check already mounted dev, sys, proc 
log_info "Check already mounted dev, sys, proc... "
for mount_point in dev sys proc; do
	`mount | egrep "/mnt/$mount_point" 1>/dev/null 2>&1`
	if [[ $? == 0 ]]; then
		err_msg=`umount /mnt/$mount_point 2>&1 1>/dev/null`
		if [[ $? != 0 ]]; then
			log_err "\n/dev/$mount_point mount is mounted. Try unmount failed: $err_msg \n"
			exit 8
		fi
	fi
done
log_add "passed\n"

# check already mounted rootfs
log_info "Check already mounted rootfs... "
`mount | egrep "/dev/sda1" 1>/dev/null 2>&1`
if [[ $? == 0 ]]; then
	log_add "umount /dev/sda1... "
	err_msg=`umount /dev/sda1 2>&1 1>/dev/null`
	if [[ $? != 0 ]]; then
		log_err "Disk /dev/sda1 is mounted. Try unmount failed: $err_msg \n"
		exit 4
	fi
fi
log_add "passed\n"

# create DOS partition table and a new partition
log_info "Create DOS partition table and a new partition... "
err_msg=`echo -e "o\nn\np\n1\n\n\nw" | fdisk /dev/sda 2>&1 1>/dev/null`
if [[ $? != 0 ]]; then
	log_err "\nCan't create new partition: $err_msg \n"
	exit 2
fi
log_add "passed\n"

# create ext4 filesystem
log_info "Create ext4 filesystem... "
err_msg=`mkfs.ext4 /dev/sda1 2>&1 1>/dev/null`
if [[ $? != 0 ]]; then
	log_err "\nCan't create filesystem: $err_msg \n"
	exit 3
fi
log_add "passed\n"

# check mount dir
log_info "Check mount dir... "
if [[ ! -d /mnt ]]; then
	log_info "\nCreate direcrory /mnt \n"
	mkdir /mnt
fi
log_add "passed\n"


# mount local disk
log_info "Mount local disk... "
err_msg=`mount -t ext4 /dev/sda1 /mnt/ 2>&1 1>/dev/null`
if [[ $? != 0 ]]; then
	log_err "\nCan't mount local filesystem: $err_msg \n"
	exit 5
fi
log_add "passed\n"

# Copy and untar rootfs
log_info "Copy and untar rootfs... "
err_msg=`cd /mnt && tar xzf /srv/images/niitp-ubuntu-minimal-amd64.tgz 2>&1 1>/dev/null`
if [[ $? != 0 ]]; then
	log_err "\nCan't extrat rootfs from the archive: $err_msg \n"
	exit 6
fi
cd /
log_add "passed\n"

# Install GRUB
log_info "Install GRUB... "
err_msg=`grub-install --root-directory=/mnt /dev/sda 2>&1 1>/dev/null`
if [[ $? != 0 ]]; then
	log_err "\nCan't install grub: $err_msg \n"
	exit 7
fi
log_add "passed\n"

# Mount dev, sys, proc
log_info "Mount dev, sys, proc... "
err_msg=`mount -t proc none /mnt/proc && mount --bind /dev/ /mnt/dev/ && mount --bind /sys/ /mnt/sys/ 2>&1 1>/dev/null`
if [[ $? != 0 ]]; then
	log_err "\nFailed mount dev,sys,proc: $err_msg \n"
	exit 9
fi
log_add "passed\n"

# Update GRUB
log_info "Update GRUB in chroot... "
err_msg=`chroot /mnt/ update-grub 2>&1 1>/dev/null`
if [[ $? != 0 ]]; then
	log_err "\nFailed run update-grub in chroot: $err_msg \n"
	exit 9
fi
log_add "passed\n"

log_info "Installation was successful!\n"

# Show must go on!
# Umount proc, sys, dev
log_info "Umount dev, sys, proc... "
for mount_point in proc sys dev; do
	err_msg=`umount /mnt/$mount_point 2>&1 1>/dev/null`
	if [[ $? != 0 ]]; then
		log_err "\n/dev/$mount_point mount is mounted. Try unmount failed: $err_msg \n"
		exit 10
	fi
done
log_add "passed\n"

# Umount rootfs
log_info "Umount rootfs... "
err_msg=`umount /dev/sda1 2>&1 1>/dev/null`
if [[ $? != 0 ]]; then
	log_err "\n/dev/$mount_point mount is mounted. Try unmount failed: $err_msg \n"
	exit 11
fi
log_add "passed\n"
log_info "DONE.\n"
