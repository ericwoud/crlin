#!/bin/bash

pacman -S --needed base-devel git bc evtest busybox kexec-tools

CHAINCMDLINE="iomem=relaxed quiet loglevel=2"

LASTCMDLINE="iomem=relaxed"

CHAIN_DEFCONFIG="x86_64_defconfig"

KERNELURL="https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.18.8.tar.xz"
#KERNELURL="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/snapshot/linux-5.19-rc4.tar.gz"

CAURL="https://chromium.googlesource.com/chromiumos/third_party/kernel/+/refs/heads/chromeos-5.15/drivers/platform/x86/chromeos_acpi.c?format=TEXT"

#makej=-j$(grep ^processor /proc/cpuinfo  | wc -l)
makej=-j2

function mkchroot
{
  [ $# -lt 2 ] && return
  dest=$1
  shift
  for i in "$@"
  do
    [ "${i:0:1}" == "/" ] || i=$(which $i 2>/dev/null)
    [ -f "$dest/$i" ] && continue
    if [ -e "$i" ]
    then
      echo MKCHROOT adding: $i
      d=`echo "$i" | grep -o '.*/'` &&
      mkdir -p "$dest/$d" &&
      cat "$i" > "$dest/$i" &&
      chmod +x "$dest/$i"
      mkchroot "$dest" $(ldd "$i" | egrep -o '/.* ')
    fi
  done
}

function mkchromeosacpi
{
############# MOET NOG WORDEN GETEST !!!!!!!!!! ###################
if [ ! -d "/usr/src/chainlinux/chromeos_acpi" ]; then
  mkdir -p "/usr/src/chainlinux/chromeos_acpi"
  ( cd /usr/src/chainlinux/chromeos_acpi ; curl $CAURL | base64 --decode > chromeos_acpi.c )
  cat <<'EOT' | tee -a "/usr/src/chainlinux/chromeos_acpi/chromeos_acpi.c"
MODULE_AUTHOR("This is a local copy");
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("ChromeOS specific ACPI extensions");
EOT
  cat <<'EOT' | tee -a "/usr/src/chainlinux/chromeos_acpi/Makefile"
CONFIG_MODULE_SIG=n
obj-m += chromeos_acpi.o
KERNELVERSION ?= $(shell uname -r)
all:
	make -C /usr/src/chainlinux M=$(PWD) modules
clean:
	make -C /usr/src/chainlinux M=$(PWD) clean
EOT
fi
  PWD=/usr/src/chainlinux/chromeos_acpi make -C /usr/src/chainlinux/chromeos_acpi clean all
  cp -vf /usr/src/chainlinux/chromeos_acpi/chromeos_acpi.ko /usr/src/chainlinux/initramfs/lib
}

if [ ! -d "/usr/src/chainlinux" ]; then
  linuxtar=$(basename $KERNELURL)
  if [ ! -f "/usr/src/$linuxtar" ]; then
    curl -vo "/usr/src/$linuxtar" $KERNELURL
    [[ $? != 0 ]] && exit
  fi
  mkdir -p "/usr/src/chainlinux"
  tar -xvf "/usr/src/$linuxtar" \
        -C "/usr/src/chainlinux" --strip-components=1
fi
mkdir -p      /usr/src/chainlinux/initramfs/{dev,etc,proc,sys,usr/lib,usr/bin,usr/local,mnt/root}
ln -s usr/bin /usr/src/chainlinux/initramfs/bin
ln -s usr/bin /usr/src/chainlinux/initramfs/sbin
ln -s ../bin /usr/src/chainlinux/initramfs/usr/local/bin
ln -s ../bin /usr/src/chainlinux/initramfs/usr/local/sbin
ln -s bin     /usr/src/chainlinux/initramfs/usr/sbin
ln -s usr/lib /usr/src/chainlinux/initramfs/lib
ln -s usr/lib /usr/src/chainlinux/initramfs/lib64
ln -s lib     /usr/src/chainlinux/initramfs/usr/lib64
mkchroot /usr/src/chainlinux/initramfs cgpt \
                                       crossystem \
                                       futility \
                                       gsctool \
                                       flashrom \
                                       busybox \
                                       kexec \
                                       evtest
mknod -m 622 /usr/src/chainlinux/initramfs/dev/console c 5 1
echo '#!/bin/sh'                   > /usr/src/chainlinux/initramfs/usr/bin/prio
cat /usr/local/sbin/crlin-prio.sh >> /usr/src/chainlinux/initramfs/usr/bin/prio
chmod +x                             /usr/src/chainlinux/initramfs/usr/bin/prio

cp -f /usr/src/chainlinux/arch/x86/configs/$CHAIN_DEFCONFIG \
      /usr/src/chainlinux/arch/x86/configs/chain_defconfig
cat <<'EOT' | tee -a /usr/src/chainlinux/arch/x86/configs/chain_defconfig
CONFIG_NET=n
CONFIG_NETDEVICES=n
CONFIG_FB=y
CONFIG_FB_SIMPLE=y
CONFIG_GOOGLE_COREBOOT_TABLE=y
CONFIG_GOOGLE_FIRMWARE=y
CONFIG_GOOGLE_MEMCONSOLE_COREBOOT=y
#CONFIG_GOOGLE_MEMCONSOLE_X86_LEGACY=y
CONFIG_GOOGLE_SMI=y
CONFIG_GOOGLE_VPD=y
CONFIG_INITRAMFS_SOURCE="/usr/src/chainlinux/initramfs/"
CONFIG_MMC=y
CONFIG_MMC_SDHCI=y
CONFIG_MMC_SDHCI_PCI=y
CONFIG_BTRFS_FS=y
CONFIG_F2FS_FS=y
CONFIG_XFS_FS=y
EOT
make --directory=/usr/src/chainlinux/ ARCH=x86 chain_defconfig
[[ $? != 0 ]] && exit
make --directory=/usr/src/chainlinux/ ARCH=x86 modules_prepare
[[ $? != 0 ]] && exit
mkchromeosacpi

cat <<'EOT' | tee /usr/src/chainlinux/initramfs/init
#!/sbin/busybox sh
/sbin/busybox --install
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs none /dev
echo "Welcome to the kexec bootloader. To interrupt press SHIFT"
dev=""
while [ -z "$dev" ]; do
  dev=$(basename $(cgpt find -u $bootedkernel) 2>/dev/null)
  [ -z "$dev" ] && sleep 0.1
done
echo dev=$dev
devnr=$(cgpt find -nu $bootedkernel)
echo devnr=$devnr
par=$(basename $(readlink -f "/sys/class/block/$dev/.."))
echo par=$par
devlabel=$(cgpt show -i $devnr -l /dev/$par)
echo devlabel=$devlabel
rootlabel=${devlabel/KERN-/ROOT-}
echo rootlabel=$rootlabel
rootdev=$(cgpt find -l $rootlabel /dev/$par)
echo rootdev=$rootdev
rootdevnr=$(cgpt find -nl $rootlabel /dev/$par)
echo rootdevnr=$rootdevnr
rootdevuuid=$(cgpt show -ui $rootdevnr /dev/$par)
echo rootdevuuid=$rootdevuuid
mount -o ro,nofail $rootdev /mnt/root
echo mounted $rootdev
chpst -e /mnt/root/boot/bootcfg/ sh /boot.sh "$bootedkernel" "$rootdevuuid"
exit 2
EOT
cat <<'EOT' | tee /usr/src/chainlinux/initramfs/boot.sh
#!/bin/sh
root=$(echo $2 | tr [:upper:] [:lower:])
shift="false"
for ev in /dev/input/event*; do
  /bin/evtest --query $ev EV_KEY KEY_LEFTSHIFT
  [ $? == 10 ] && shift="true"
done
if [ "$shift" != "true" ]; then
  echo /mnt/root$linux and /mnt/root$initrd loading...
  /sbin/kexec -f -l "/mnt/root$linux" --command-line="root=PARTUUID=$root rw kerneluuid=$1 $cmdline" --initrd="/mnt/root$initrd"
  echo /mnt/root$linux and /mnt/root$initrd loaded
  /sbin/kexec -f -e
  echo SHOULD NOT SEE THIS!
fi
insmod /lib/chromeos_acpi.ko
echo "This is the busybox prompt. Use all available busybox commands."
echo "Extra commands: kexec, crossystem (experimental), futility, gsctool, flashrom (cros), evtest."
echo "Use the prio command to easily edit the kernel priorities."
setsid sh -c 'exec sh </dev/tty1 >/dev/tty1 2>&1'
exit 3
EOT

mkdir -p /boot/bootcfg/
echo /boot/vmlinuz-linux |       tee /boot/bootcfg/linux
echo /boot/initramfs-linux.img | tee /boot/bootcfg/initrd
echo $LASTCMDLINE |              tee /boot/bootcfg/cmdline

chmod +x /usr/src/chainlinux/initramfs/init

rm -f /usr/src/chainlinux/arch/x86/boot/bzImage
make --directory=/usr/src/chainlinux/ ARCH=x86 $makej bzImage
[[ $? != 0 ]] && exit

echo "bootedkernel=%U $CHAINCMDLINE" | tee /usr/src/chainlinux/chainkernel.config
futility vbutil_kernel --pack /usr/src/chainlinux/chainkernel.bin \
  --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
  --version 1 \
  --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
  --config /usr/src/chainlinux/chainkernel.config \
  --vmlinuz /usr/src/chainlinux/arch/x86/boot/bzImage \
  --arch x86_64 \
  --bootloader /usr/src/chainlinux/chainkernel.config
[[ $? != 0 ]] && exit
futility vbutil_kernel --verify /usr/src/chainlinux/chainkernel.bin
[[ $? != 0 ]] && exit

if [ -z $1 ]; then
  for i in $(cat /proc/cmdline) ; do
    if [ "${i:0:11}" = "kerneluuid=" ]; then
      dev=$(lsblk -prno name,partuuid | grep "${i:11}" | cut -d " " -f1)
      echo "Writing bootloader kernel to $dev..."
      dd if=/usr/src/chainlinux/chainkernel.bin of=$dev
    fi
  done
else
  echo "Writing bootloader kernel to $1..."
  dd if=/usr/src/chainlinux/chainkernel.bin of=$1
fi
sync

exit

