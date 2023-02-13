#!/bin/bash
#Particioón de Disco
parted -s /dev/sdc mklabel gpt 
parted -s -a optimal /dev/sdc mkpart logical 0% 100%
parted -s /dev/sdc 'set 1 lvm on' 
#Configuración de LVM
pvcreate /dev/sdc1 
vgcreate vg_elk /dev/sdc1 
lvcreate -l 100%FREE -n lv_lineal vg_elk 
mkfs.ext4 /dev/vg_elk/lv_lineal 
mkdir -p /var/lib/elasticsearch
mount /dev/vg_elk/lv_lineal /var/lib/elasticsearch
echo "/dev/vg_elk/lv_lineal	/var/lib/elasticsearch	 ext4	defaults	0 0" >> /etc/fstab
#umount /dev/vg_elk/lv_lineal
#reboot # Reinicio para hacer el montaje persistente