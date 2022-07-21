#!/bin/bash

sed -i '/'$LANG'/s/^#//g' /etc/locale.gen
[ -z $(localectl list-locales | grep --ignore-case $LANG) ] && locale-gen
localectl set-locale LANG=$LANG

pacman -Runs xf86-video-intel xf86-video-vesa
pacman -Syu --needed xorg gnome gnome-tweaks nautilus-sendto gnome-nettool gnome-usage \
                     gnome-multi-writer adwaita-icon-theme xdg-user-dirs-gtk fwupd \
                     arc-gtk-theme seahorse networkmanager \
                     base-devel git \
                     sof-firmware \
                     mesa libva libva-mesa-driver \
                     libva-utils intel-ucode iucode-tool \
                     vulkan-intel intel-gmmlib intel-graphics-compiler \
                     intel-media-driver intel-media-sdk intel-opencl-clang libmfx \
                     intel-compute-runtime ocl-icd opencl-headers

sed -i 's/.*MODULES=.*/MODULES=(intel_agp i915)/' /etc/mkinitcpio.conf

cat <<EOT | tee /etc/modprobe.d/i915.conf
options i915 enable_guc=2
options i915 enable_gvt=0
options i915 enable_fbc=1
EOT
echo -e 'options snd_intel_dspcfg dsp_driver=3\noptions snd-sof-pci fw_path="intel/sof"' \
     | sudo tee  /etc/modprobe.d/inteldsp.conf
cat <<EOT | tee /etc/udev/rules.d/91-pulseaudio-apl.rules
SUBSYSTEM!="sound", GOTO="pulseaudio_end"
ACTION!="change", GOTO="pulseaudio_end"
KERNEL!="card*", GOTO="pulseaudio_end"
SUBSYSTEMS=="pci", ATTRS{vendor}=="0x8086", ATTRS{device}=="0x5a98", ENV{PULSE_PROFILE_SET}="apl-profile.conf"
LABEL="pulseaudio_end"
EOT
cat <<EOT | tee /usr/share/pulseaudio/alsa-mixer/paths/sof-apl-speaker-output.conf 
# This file is a custom file intended for PulseAudio.
; Sound Open Firmware - Apollo Lake DA7219 Speaker Path
; Works with:
; sof-bxtda7219max
[General]
priority = 200
description-key = analog-output-speaker
[Properties]
device.icon_name = audio-speakers
[Element PGA1.0 1 Master]
volume = merge
override-map.1 = all
override-map.2 = all-left,all-right
[Element Spk]
switch = mute
EOT
cat <<EOT | tee /usr/share/pulseaudio/alsa-mixer/profile-sets/apl-profile.conf 
# This file is a custom file intended for PulseAudio.
; Sound Open Firmware - Apollo Lake Chromebook
[General]
auto-profiles = no
[Mapping analog-stereo-speaker]
description = Speaker
device-strings = hw:%f,0
channel-map = left,right
direction = output
priority = 9
paths-output = sof-apl-speaker-output
[Profile myprofile]
description = My Description
output-mappings = analog-stereo-speaker
priority = 60
EOT

mkinitcpio -P
##sudo grub-mkconfig -o /boot/grub/grub.cfg  # ???? again ????

for user in /home/*; do
  sudo -u $(basename $user) dbus-launch --exit-with-session gsettings set \
    org.gnome.desktop.peripherals.touchpad click-method areas
done

systemctl reenable gdm
systemctl reenable NetworkManager
systemctl disable systemd-networkd
systemctl disable systemd-resolved

#yay -S gnome-shell-extension-dash-to-dock

