
# CRLIN : Dualboot Chromebook ArchLinux or ChromeOS, without firmware alterations and normal arch-linux kernel.

Dualboot Chromebook ArchLinux or ChromeOS without any firmware alterations (also not on legacy). It will boot the normal arch-linux kernel.

I've build this build script for use on an Apollo Lake Chromebook. It might work very well on others too. It will only work on x86 Chromebooks.
The only specific about APL is a custom pulseaudio configuration gets loaded when the APL soundcard is detected.

It is still in early development stage, and might still have bugs. You use it with `sudo` so use at your own risk!!! Make backups!!!

It installs a bootloader on KERN-C. No firmware needs to be written, as the original firmware is used.

The system uses the KERN-C and ROOT-C partition, so it can also be installed as dualboot on the same disk as chromeos.

The build script can be run on chrome-os or on linux, both options work. However, usb access is slow on chrome-os, so building the bootloader will take hours and hours on chrome-os. You need to leave it building overnight. On archlinux (running from usb, or from another commputer) it will build much faster.


## Prereq:

First you need a high quality usb-stick. Not every usb-stick handles thousands of files nicely on chromeos. I always use sandisk for root usb-sticks. Price does not guarantee high quality. Using a low quality usb-stick will hang the installation process. You will not get very far...

Setup your chromebook to Developer Mode and set it up to be able to boot from usb. Open the cros-shell (CTRL-SHIFT-T and type `shell`).

## Installation on USB

Download the scripts and copy the scripts, using the following one-liner:

```
export p="https://github.com/ericwoud/crlin/raw/main/" ; sudo mkdir -p /usr/local/sbin/ ; for f in crlin-build.sh crlin-prio.sh crlin-tools-build.sh crlin-postinstall.sh crlin-boot.sh ; do sudo curl -Lo /usr/local/sbin/$f $p$f ; done ; sudo chmod +x /usr/local/sbin/crlin-*
```

Now execute the first part of the build-script:

```
sudo crlin-build.sh -r
```

Choose to format the correct usb-stick (sdX). If it was not GPT then it will fix this and you really need to reboot. After formatting, on chrome-os, if there was a partition mounted before formatting, better reboot again. I could not find a good alternative.


At this point you may want to edit crlin-build.sh to use the correct username,  wifi network and passwords.
Now start the script again, choose the same usb-stick and:

```
sudo crlin-build.sh -r
```

Now the installation starts. When it finally finishes, you only need to install the chainloading linux (used here as bootloader). On chrome-os building this will take hours and hours. 

Build it like so (leaving it overnight):

```
sudo crlin-build.sh -b
```

Or you could choose to build the bootloader on another comuputer running archlinux. Then you need the `cgpt` command, which is part of the AUR package `chromeos-vboot-reference-git`. 

## Entering chroot

Now you can now use:

```
sudo crlin-build.sh
```

Without any option. It will run you a chroot on the usb-stick, if you want to install more stuff. Type `exit` to exit the chroot and unmount ths mount nicely.


## First boot

After booting with CTRL-U, there are more installation scripts available. You could also run these on the chroot.

```
sudo crlin-tools.sh
```

Builds some extra tools originating from chrome-os. These are also needed for the bootloader. Some are extra on the bootloader.

```
sudo crlin-postinstall.sh
```

Setup GDM and everything necessairy to boot to graphical interface.

```
sudo crlin-boot.sh
```

Builds the bootloader and writes it to the last booted partition. It optionally takes one argument, specifying an other partition to write to, for example /dev/sda6.

```
sudo crlin-prio.sh
```

Tool to setup kernel priorities. You can change the priority of the KERN-C partition on a dual-booting system.

## Installing dualboot

Once running on an usb-stick, you can shrink the statefull partition on the chromeos disk and start installing a dualbooting linux on the very same disk as chromeos.

```
sudo crlin-build.sh -r
```

Now choose the mmcblk device that holds chromeos. You can choose `format` to wipe and delete chromeos, or `dualboot` which will shrink statefull and leaves chromeos in tact. Now start the script again:

```
sudo crlin-build.sh -r
```

And choose the same mmcblk and it will install ArchLinux on the very same disk as chromeos. Keep the usb-stick as a backup.


## Bootloader

The bootloader can be interrupted by holding down the SHIFT key. The tricky part is, not too early, not too late. Now all busybox commands are available, also cgpt, crossystem (experimental), futility (vbutil_kernel) and gsctool.

When started from partition KERN-X it finds and mounts ROOT-X. From there in examines:

```
/boot/bootcfg/linux
/boot/bootcfg/initrd
/boot/bootcfg/cmdline
```

From this it loads the specified linux and initrd files and starts the kernel with the specified cmdline.

It supports ext4 and f2fs.

