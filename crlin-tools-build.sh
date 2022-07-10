#!/bin/bash

pacman -S --needed base-devel linux-headers git bc inetutils cmake meson libusb libftdi cmocka dkms

packages="chromeos-gsctool-git chromeos-acpi-dkms-git chromeos-flashrom-git chromeos-vboot-reference-git"

[ -z "$packages" ] && exit 0
[ $USER = "root" ] && sudo="" || sudo="sudo -s"

function finish { $sudo rm -rf /tmp/aurinstall ; }
trap finish EXIT

sudo -u nobody mkdir /tmp/aurinstall

for package in $packages
do 
  if [ ! -d "/tmp/aurinstall/$package" ]; then
    sudo -u nobody git --no-pager clone --depth 1 https://aur.archlinux.org/$package.git /tmp/aurinstall/$package 2>&0
    [[ $? != 0 ]] && exit
  fi
  (cd "/tmp/aurinstall/$package"; sudo HOME=/tmp/aurinstall/$package -u nobody makepkg)
  for package in /tmp/aurinstall/$package/*.pkg.*
  do 
    $sudo pacman -U --noconfirm $package
  done
done

exit 0

# To try out:
# flashrom -p host --wp-status
# flashrom -p host -i GBB -r "$@"
# gbb_utility -s --flags="${value}" "${image_file}"
# flashrom -p host -i GBB --noverify-all -w "$@"

