#!/bin/bash

SD_BLOCK_SIZE_KB=16                  # in kilo bytes
SD_ERASE_SIZE_MB=4                   # in Mega bytes
ROOTFS_LABEL="CRLIN-ROOT"
STATEFULSIZE=4096                    # in Mega bytes

USERNAME="user"
USERPWD="admin"
ROOTPWD="admin"

SSID="MYWIFI"
PSK="password"

PACKAGES="base nano screen sudo linux linux-firmware wpa_supplicant crda f2fs-tools"

LC="en_US.UTF-8"                      # Locale
TIMEZONE="Europe/Paris"              # Timezone
hostname="chromebook"


function unmount {
    echo $(mountpoint $1)
    while [[ $(mountpoint $1) =~  (is a mountpoint) ]]; do
      echo "Unmounting...DO NOT REMOVE!"
      umount -lR $1
      sleep 0.1
    done    
}

function unmountrootfs {
  if [ -v rootfsdir ] && [ ! -z $rootfsdir ]; then
    sync
    echo Running exit function to clean up...
    unmount $rootfsdir
    sync
    rm -rf $rootfsdir
    sync
    echo -e "Done. You can remove the card now.\n"
  fi
  unset rootfsdir
}

function finish {
  unmountrootfs
}

function format {
  partx -d ${device}
  sync
  last=$(cgpt show ${device} | grep 'Sec GPT table' | awk '{ print $1 }')
  gpt=$(cgpt show ${device} | grep "Pri GPT header")
  if [ -z "$gpt" ]; then
    echo gw | fdisk ${device}
    sync
    echo "Was not GPT before, changed to GPT. Need to reboot and format again!!!"
    exit
  fi
  cgpt create ${device}
  sync
  cgpt add -i 6 -b $((16*2048)) -s $((16*2048))       -S 1 -T 15 -P 15 -l KERN-C -t kernel ${device}
  sync
  cgpt add -i 7 -b $((32*2048)) -s $(($last-32*2048)) -S 1 -P 5        -l ROOT-C -t rootfs ${device}
  sync
  udevadm settle
  blockdev --rereadpt $device
  udevadm settle
  makefs
  exit
}

function dualboot {
  last=$(cgpt show ${device} | grep 'Sec GPT table' | awk '{ print $1 }')
  statestart=$(cgpt show -i 1 -b -n ${device})
  statesize=$(cgpt show -i 1 -s -n ${device})
  oemstart=$(cgpt show -i 8 -b -n ${device})
  oemsize=$(cgpt show -i 8 -s -n ${device})
  parted ${device} rm 6
  parted ${device} rm 7
  sync
  partprobe ${device}
  udevadm settle
  e2fsck -f -p "${partdev}1"
  sync
  align=$(( (statestart+(STATEFULSIZE*2048)) % (SD_ERASE_SIZE_MB*2048) ))
  [ "$align" -ne "0" ] && align=$(( (SD_ERASE_SIZE_MB*2048) - $align ))
  if [ "$statesize" -gt "$((STATEFULSIZE*2048))" ]; then
    echo "Shrinking stateful partition..."
    resize2fs "${partdev}1" "$((STATEFULSIZE*2048))s"
    sync
    cgpt add -i 1 -b "$statestart" -s $(( (STATEFULSIZE*2048)+$align )) -l STATE ${device}
    sync
  else
    echo "Expanding stateful partition..."
    cgpt add -i 1 -b "$statestart" -s $(( (STATEFULSIZE*2048)+$align )) -l STATE ${device}
    sync
    resize2fs "${partdev}1" "$((STATEFULSIZE*2048))s"
    sync
  fi
  e2fsck -f -p "${partdev}1"
  sync
  cgpt repair ${device}
  sync
  partprobe ${device}
  statesize=$(cgpt show -i 1 -s -n ${device})
  unallocsize=$(parted ${device} unit s print free | grep -A1 "STATE" | tail -n +2 | awk '{print $3}')
  unallocsize=${unallocsize/s/}
  unallocstart=$(($statestart+$statesize))
  echo UNALLOCSIZE : $unallocsize
  if [ "$unallocsize" -gt "$((4*1024*2048))" ]; then
    # More then 4 Gigabytes freed up space
    # Create kernel C partition after OEM partition (reserved space)
    cgpt add -i 6 -b $(($oemstart+$oemsize)) -s $((16*2048)) -S 1 -T 15 -P 3 -l KERN-C -t kernel ${device}
    sync
    # Create rootfs C partition after STATE partition (freed space)
    cgpt add -i 7 -b $(($unallocstart)) -s $(($unallocsize)) -S 1       -P 5 -l ROOT-C -t rootfs ${device}
    sync
  fi
  partprobe ${device}
  udevadm settle
  blockdev --rereadpt $device
  udevadm settle
  makefs
  exit
}

function makefs {
  cgpt show ${device}
  which mkfs.f2fs
  if [[ $? != 0 ]]; then
    [[ $SD_BLOCK_SIZE_KB -lt 4 ]] && blksize=$SD_BLOCK_SIZE_KB || blksize=4
    stride=$(( $SD_BLOCK_SIZE_KB / $blksize ))
    stripe=$(( ($SD_ERASE_SIZE_MB * 1024) / $SD_BLOCK_SIZE_KB ))
    mkfs.ext4 -v -b $(( $blksize * 1024 ))  -L $ROOTFS_LABEL \
              -E stride=$stride,stripe-width=$stripe "${partdev}7"
  else
    nrseg=$(( $SD_ERASE_SIZE_MB / 2 )); [[ $nrseg -lt 1 ]] && nrseg=1
    mkfs.f2fs -w $(( $SD_BLOCK_SIZE_KB * 1024 )) -s $nrseg \
              -d 9 -t 0 -f -l $ROOTFS_LABEL "${partdev}7"
  fi
  sync
  lsblk -o name,mountpoint,label,size,uuid "${device}"
  echo "Finished formatting. Under ChromeOS, better reboot and start script again!!!"
}

function bootstrap {
  if [ ! -d "$rootfsdir/usr" ]; then
    if [ ! -f "$rootfsdir/albootstr.tar.gz" ]; then
      echo -e "\nThis will take a long time, please wait, even when not seeing any progress!\n"
      version=$(curl "http://mirror.rackspace.com/archlinux/iso/latest/arch/version")
      url="http://mirror.rackspace.com/archlinux/iso/latest/archlinux-bootstrap-$version-x86_64.tar.gz"
      curl -vo "$rootfsdir/albootstr.tar.gz" $url
      if [[ $? != 0 ]]; then 
        rm -vf "$rootfsdir/albootstr.tar.gz"
        exit
      fi
    fi
    tar -xvzf "$rootfsdir/albootstr.tar.gz" --numeric-owner \
        -C $rootfsdir --strip-components=1
    echo "Synchronising..."
    sync
  fi
}

function rootfs {
$schroot pacman -Sy
if [[ $? != 0 ]]; then
  $schroot pacman-key --init
  $schroot pacman-key --populate archlinux
  $schroot sed -i '/mirror.rackspace.com/s/^#//g' /etc/pacman.d/mirrorlist
fi
$schroot pacman -Syu --needed --noconfirm $PACKAGES
sync
$schroot systemctl reenable systemd-networkd
$schroot systemctl reenable systemd-resolved
$schroot systemctl reenable systemd-timesyncd
$schroot systemctl reenable wpa_supplicant@wlp1s0
$schroot useradd --create-home -g users \
             --groups audio,games,log,lp,optical,power,scanner,storage,video,wheel \
             -s /bin/bash $USERNAME
echo $USERNAME:$USERPWD | $schroot chpasswd
echo      root:$ROOTPWD | $schroot chpasswd
echo "%wheel ALL=(ALL) ALL" | sudo tee $rootfsdir/etc/sudoers.d/wheel
$schroot ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
echo $hostname | tee $rootfsdir/etc/hostname
cp -vf ./crlin-* $rootfsdir/usr/local/sbin/
chmod +x $rootfsdir/usr/local/sbin/crlin-*.sh
chmod g+w $rootfsdir/usr/local/sbin/crlin-*.sh
chown root:video $rootfsdir/usr/local/sbin/crlin-*.sh
mkdir -p $rootfsdir/etc/systemd/network/
cat <<EOT | tee $rootfsdir/etc/hosts
127.0.0.1        localhost
::1              localhost
127.0.1.1        $hostname
EOT
cat <<EOT | tee $rootfsdir/etc/systemd/network/25-wireless.network
[Match]
Name=wlp1s0
[Network]
DHCP=yes
EOT
cat <<EOT | tee $rootfsdir/etc/wpa_supplicant/wpa_supplicant-wlp1s0.conf
ctrl_interface=/var/run/wpa_supplicant
eapol_version=1
ap_scan=1
fast_reauth=1
network={
	ssid="$SSID"
	psk="$PSK"
	priority=100
}
EOT
cat <<EOT | tee $rootfsdir/etc/locale.conf
LANG=$LC
EOT
cat <<EOT | tee $rootfsdir/etc/fstab
# <file system> <dir> <type> <options> <dump> <pass>
PARTUUID=$(lsblk ${partdev}7 -prno partuuid) / auto defaults,noatime,nodiratime 0 1
# PARTUUID=$(lsblk ${partdev}12 -prno partuuid) /boot vfat defaults 0 2
EOT
# if [ ! -d /sys/block/mmcblk0/ ]; then
#   echo 1 > /sys/class/mmc_host/mmc0/device/remove
#   echo 1 > /sys/bus/pci/rescan
# fi
}
# end of function rootfs

cd $(dirname $BASH_SOURCE)

while getopts ":rb" opt $args; do declare "${opt}=true" ; done

if [ ! -z $(cat /etc/os-release | grep ID=chrome) ]; then
  rootdev=$(lsblk -pilno name,type,mountpoint | grep 'part /mnt/stateful_partition')
else
  rootdev=$(lsblk -pilno name,type,mountpoint | grep -G 'part /$')
fi
rootdev=${rootdev%% *}
echo ROOTDEV: $rootdev
lsblkrootdev=($(lsblk -prno name,pkname,partlabel | grep $rootdev))
[ -z $lsblkrootdev ] && exit
realrootdev=${lsblkrootdev[1]}
echo REALROOTDEV: $realrootdev

readarray -t options < <(lsblk --nodeps -no name,serial,size \
                    | grep -v "^"${realrootdev/"/dev/"/}'\|^loop\|^zram' \
                    | grep -v 'boot0 \|boot1 \|boot2 ')
PS3="Choose device: "
select dev in "${options[@]}" "Quit" ; do
  if (( REPLY > 0 && REPLY <= ${#options[@]} )) ; then
    break
  else exit
  fi
done    
device="/dev/"${dev%% *}
[[ $device == /dev/mmcblk* ]] && partdev="${device}p" || partdev="${device}"
echo DEVICE: $device
echo PARTDEV: $partdev
trap finish EXIT
for PART in $(df -k --output=source,target | grep ${device} | awk '{ print $1 }') 
  do unmount $PART; done
sync
cgpt show $device
runningcros=$(cgpt show -i 1 ${device} | grep 'Label: "STATE"')
if [ -z "runningcros" ]; then
  echo -e "\nNo Chrome OS found, assuming empty disk\n"
  echo -e "Do you want to format "$device"???\n" 
  echo -e "Format will destroy all data!!!\n" 
  read -p "Type <format> to format or press <enter> to continue without formatting: " prompt
  [[ $prompt == "format" ]] && format
else
  echo -e "\nChrome OS found\n"
  echo -e "Do you want to format or install new dualboot partitions "$device"???\n" 
  echo -e "Format will destroy all data!!!\n" 
  echo -e "Dualboot will destroy data on KERN-C ROOT-C and STATE!!!\n" 
  read -p "Type <format> or <dualboot> or press <enter> to continue without formatting: " prompt
  [[ $prompt == "format" ]] && format
  [[ $prompt == "dualboot" ]] && dualboot
fi
if [ -d "/media/removable" ]; then
######### always /mnt/crlinrootfs ?????
  rootfsdir="/media/removable/crlinrootfs"
else
  rootfsdir="/mnt/crlinrootfs"
fi
[ -d $rootfsdir ] || sudo mkdir $rootfsdir
[ -z "runningcros" ] && secl="" || secl="seclabel,data=ordered"
mount --source "${partdev}7" --target $rootfsdir \
      -o symfollow,exec,rw,nosuid,nodev,noatime,nodiratime,sync
bootstrap
mount -t proc               /proc $rootfsdir/proc
mount --rbind --make-rslave /sys  $rootfsdir/sys
mount --rbind --make-rslave /dev  $rootfsdir/dev
mount --rbind --make-rslave /run  $rootfsdir/run
[ -z "$(cat $rootfsdir/etc/resolv.conf | grep nameserver)" ] && cat <<EOT | tee $rootfsdir/etc/resolv.conf
nameserver 8.8.8.8
options single-request timeout:1 attempts:5
EOT

schroot="chroot $rootfsdir"

if [ "$r" = true ]; then
  rootfs
  exit
elif [ "$b" = true ]; then
  $schroot bash /usr/local/sbin/crlin-tools-build.sh
  $schroot bash /usr/local/sbin/crlin-boot.sh "${partdev}6"
  exit
else
  $schroot
  exit
fi

exit

# earlyprintk root=UUID=009060d4-e6f9-4519-95e5-00bf7ec54a2c rootwait rootfstype=ext4 console=ttyS2,115200n8 console=tty1
# consoleblank=0 loglevel=1 usb-storage.quirks=   cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1


