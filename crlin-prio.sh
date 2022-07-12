#!/bin/bash

echo "0. Exit"
i=1
devs=$(cgpt find -t kernel)
for dev in $devs; do
  dev=${dev/\/dev\//}
  par=$(basename $(readlink -f "/sys/class/block/$dev/.."))
  nr=$(cat "/sys/class/block/$dev/partition")
  pri=$(cgpt show -i $nr -P /dev/$par)
  lab=$(cgpt show -i $nr -l /dev/$par)
  echo $i. $dev : drive=$par partition=$nr label=$lab priority=$pri
  i=$(($i+1))
done
echo "Enter which kernel partition to edit and press <enter>:"
read i
[ -z "$i" ] && exit
[ $i = 0 ] && exit
echo "Enter new priority and press <enter>:"
read pp
[ $pp -lt 0 ] && exit
[ $pp -gt 15 ] && exit
dev=$(echo $devs | cut -d " " -f$i)
dev=${dev/\/dev\//}
par=$(basename $(readlink -f "/sys/class/block/$dev/.."))
nr=$(cat "/sys/class/block/$dev/partition")
echo Changing $par partition $nr to prio $pp
echo cgpt add -i $nr -P $pp /dev/$par
     cgpt add -i $nr -P $pp /dev/$par

