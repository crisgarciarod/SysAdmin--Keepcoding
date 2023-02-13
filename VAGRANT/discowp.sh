#!/bin/bash
#Partición de Disco
parted -s /dev/sdc mklabel gpt 
parted -s -a optimal /dev/sdc mkpart logical 0% 100%
parted -s /dev/sdc 'set 1 lvm on' 
#Configuración de LVM
pvcreate /dev/sdc1 
vgcreate vg_wp /dev/sdc1 
lvcreate -l 100%FREE -n lv_lineal vg_wp 
mkfs.ext4 /dev/vg_wp/lv_lineal 
mkdir -p /var/lib/mysql
mount /dev/vg_wp/lv_lineal /var/lib/mysql
echo "/dev/vg_wp/lv_lineal	/var/lib/mysql	 ext4	defaults	0 0" >> /etc/fstab
#umount /dev/vg_wp/lv_lineal
#reboot # Reinicio para hacer el montaje persistente

