#!/bin/bash

echo "Are you sure? This will destroy and recreate /dev/sda yes/no?"
echo "yes/no?"
read response
echo

if [[ $response =~ ^[Yy]es$ ]]
then

    nc -z 8.8.8.8 53  >/dev/null 2>&1 && online=$?
    if [ ! $online -eq 0 ]; then
        wifi-menu
    fi

    # make sure nothing is mounted and turn off all swap partitions
    umount /mnt/boot
    umount /mnt
    swapoff -a

    # create guid partition table
    parted -s /dev/sda mklabel gpt

    # write /dev/sda1 as an EFI boot partition (msdos + boot flags) into the gpt
    #                               200MB
    parted -s /dev/sda mkpart msdos 2048s 411647s
    parted -s /dev/sda set 1 esp on # efi system partition
    parted -s /dev/sda set 1 boot on
    # actually make the efi filesystem
    mkfs.fat -F32 /dev/sda1 -F

    # write /dev/sda2 as an EFI boot partition (msdos + boot flags) into the gpt
    #                              20GB
    parted -s /dev/sda mkpart ext4 411648s 42354687s
    # actually make the ext4
    mkfs.ext4 /dev/sda2 -F

    # write /dev/sda3 as a linux swap partition
    #                                    2GB
    parted -s /dev/sda mkpart linux-swap 42354688s 46548991s
    mkswap /dev/sda3
    swapon /dev/sda3

    # mount / at /mnt and /boot at /mnt/boot
    mount /dev/sda2 /mnt
    mkdir -p /mnt/boot
    mount /dev/sda1 /mnt/boot
    #remove any residual images in /boot
    rm -r /mnt/boot/*

    # install the indicated packages to the new system
    pacstrap /mnt       \
        base            \
        base-devel      \
        grub-efi-x86_64 \
        os-prober       \
        efibootmgr      \
        wpa_supplicant  \
        dialog          \
        git             \
        vim             \
        tmux            \
        wget            \
        sudo 		\
	openssh

    genfstab /mnt > /mnt/etc/fstab

    arch-chroot /mnt /bin/bash -c '
        git config --global user.name "Jeff Fowler" &&
        git config --global user.email "jeffowler@gmail.com" &&
        locale-gen en_US.UTF-8 &&
        ln -s /usr/shar/zoneinfo/America/New_York /etc/localtime &&
        hwclock --systohc --utc &&
        grub-install --efi-directory=/boot &&
        grub-mkconfig -o /boot/grub/grub.cfg &&
	systemctl enable sshd.service &&
	systemctl start sshd.service &&
        useradd -m -g users -G wheel,storage,power -s /bin/bash jfo && passwd jfo &&
        su jfo -c "git clone https://github.com/urthbound/scripts ~/"'


    echo "new-arch.sh is done. you can probably reboot now. Don't forget to edit the sudoers file."

fi
