ROOTDIR=~/mendel

function build_linux
{
    pushd linux-imx
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=-imx defconfig
    cat $ROOTDIR/packages/linux-imx/debian/defconfig | tee -a .config
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=-imx olddefconfig
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=-imx -j4 Image modules dtbs
    popd
}


function build_uboot
{
    IMX_FIRMWARE_DIR=$ROOTDIR/imx-firmware/imx8m
    pushd  uboot-imx
    make CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm mx8mq_phanbell_defconfig _all

    objcopy -I binary -O binary --pad-to 0x4000 --gap-fill 0x0 $IMX_FIRMWARE_DIR/lpddr4_pmu_train_1d_dmem.bin lpddr4_pmu_train_1d_dmem_pad.bin
    objcopy -I binary -O binary --pad-to 0x8000 --gap-fill 0x0 $IMX_FIRMWARE_DIR/lpddr4_pmu_train_1d_imem.bin lpddr4_pmu_train_1d_imem_pad.bin
    objcopy -I binary -O binary --pad-to 0x8000 --gap-fill 0x0 $IMX_FIRMWARE_DIR/lpddr4_pmu_train_2d_imem.bin lpddr4_pmu_train_2d_imem_pad.bin

    cat lpddr4_pmu_train_1d_imem_pad.bin lpddr4_pmu_train_1d_dmem_pad.bin > lpddr4_pmu_train_1d_fw.bin
    cat lpddr4_pmu_train_2d_imem_pad.bin $IMX_FIRMWARE_DIR/lpddr4_pmu_train_2d_dmem.bin > lpddr4_pmu_train_2d_fw.bin
    cat spl/u-boot-spl.bin lpddr4_pmu_train_1d_fw.bin lpddr4_pmu_train_2d_fw.bin > u-boot-spl-ddr.bin

    bash $ROOTDIR/tools/imx-mkimage/iMX8M/mkimage_fit_atf.sh \
	 $ROOTDIR/imx-atf/build/imx8mq/release/bl31.bin \
	 u-boot-nodtb.bin \
	 arch/arm/dts/fsl-imx8mq-phanbell.dtb > u-boot.its
    tools/mkimage -E -p 0x3000 -f u-boot.its u-boot.itb
    
    tools/mkimage -A arm -T script -O linux -d $ROOTDIR/packages/uboot-imx/debian/boot.txt boot.scr
    
    $IMX_FIRMWARE_DIR/mkimage_imx8 -fit \
				   -signed_hdmi $IMX_FIRMWARE_DIR/signed_hdmi_imx8m.bin \
				   -loader u-boot-spl-ddr.bin 0x7E1000 \
				   -second_loader u-boot.itb 0x40200000 0x60000 \
				   -out u-boot.imx
    popd
}

function build_atf
{
    pushd imx-atf
    make LDFLAGS= CFLAGS= CROSS_COMPILE=aarch64-linux-gnu- PLAT=imx8mq bl31
    popd
}

function make_image
{
    SDIMAGE_SIZE_MB=256M
    UBOOT_START=66
    BOOT_START=8
    ROOTFS_START=136
    SDCARD_WIP_PATH=sdcard.img
    export PATH=$PATH:/sbin/ # parted
    
    mkdir tmp
    pushd tmp
    fallocate -l $SDIMAGE_SIZE_MB $SDCARD_WIP_PATH
    parted -s $SDCARD_WIP_PATH mklabel msdos
    parted -s $SDCARD_WIP_PATH unit MiB mkpart primary ext2 $BOOT_START $ROOTFS_START
    parted -s $SDCARD_WIP_PATH unit MiB mkpart primary ext4 $ROOTFS_START 100%
    dd if=$ROOTDIR/uboot-imx/u-boot.imx of=$SDCARD_WIP_PATH conv=notrunc seek=$UBOOT_START bs=512
    dd if=$ROOTDIR/out/target/product/imx8m_phanbell/boot_arm64.img of=$SDCARD_WIP_PATH conv=notrunc seek=$BOOT_START bs=1M

    losetup --show -f $SDCARD_WIP_PATH
    partx -d /dev/loop0
    partx -a /dev/loop0
    #mount /dev/loop0p2 /root/mendel/out/target/product/imx8m_phanbell/obj/ROOTFS/rootfs
    mkdir boot
    mount /dev/loop0p1 boot/

    #root@debian:~/mendel/tmp# ls /mnt
    #Image                   boot.scr            fsl-imx8mq-phanbell.dtb  lost+found    u-boot.imx
    #System.map-4.14.98-imx  config-4.14.98-imx  fsl-imx8mq-yorktown.dtb  overlays.txt  vmlinuz-4.14.98-imx
    mkdir -p boot/_old_

    mv boot/boot.scr boot/_old_
    cp $ROOTDIR/uboot-imx/boot.scr boot/
    
    mv boot/Image boot/_old_
    mv boot/*.dtb boot/_old_
    mv boot/config* boot/_old_
    mv boot/vmlinu* boot/_old_
    cp $ROOTDIR/linux-imx/arch/arm64/boot/Image boot/
    cp $ROOTDIR/linux-imx/arch/arm64/boot/dts/freescale/fsl-imx8mq-phanbell.dtb boot/
    cp $ROOTDIR/linux-imx/.config boot/config-4.14.98-imx
    cp $ROOTDIR/linux-imx/arch/arm64/boot/Image boot/vmlinuz-4.14.98-imx
    cp $ROOTDIR/linux-imx/System.map boot/System.map-4.14.98-imx
    ls boot/
    
    umount boot/
    partx -d /dev/loop0
    losetup -d /dev/loop0

    rmdir boot/
   
    popd
    
}

build_atf
build_uboot
build_linux
make_image
