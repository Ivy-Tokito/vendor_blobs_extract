#!/usr/bin/bash

set -e

device=munch
vendor=xiaomi
maintainer="Ivy-Tokito"
device_tree="device_xiaomi_munch" #Repo Name
branch="voltage-14" #Device Tree Branch
vendor_tree="https://gitlab.com/Ivy-Tokito/vendor_xiaomi_munch.git"
commit_msg=""
img_list=(vendor product system_ext mi_ext odm)

err() { echo -e "\e[91m*\e[39m $*"; exit 1; }

fastboot_stockrom_zip() { find . -name "${device}*.tgz"; }

super_img() { find . -name super.img; }

cleanup() {
	echo "Running Cleanup"
	sudo umount -R super/system 2> /dev/null
	sudo losetup -d /dev/loop0 2> /dev/null
	rm -rv super super.raw.img
}

mount-super() {
	trap cleanup ERR INT TSTP QUIT
	[ $(super_img) ] || err "super.img Not Found!. Aborting"
	echo "Creating Super Raw image"; simg2img "$(super_img)" ./super.raw.img
	mkdir -p super/system
	echo "Extracting Super Raw image"; lpunpack super.raw.img super
	rm super/*_b.img #Empty Images
	echo "Loop Setup"; sudo losetup -r /dev/loop0 super/system_a.img
	echo "Mount super/system_a.img to super/system"
	sudo mount -o loop super/system_a.img super/system
	for img in ${img_list[@]}; do
		sleep 3 # Avoid Race Condition
		echo "Mounting: ${img}_a.img to super/system/$img"
		if ! sudo mount -o loop super/${img}_a.img super/system/$img; then
			err "Mounting Failed!"
		fi
	done
	echo -e "\e[92mSuper Mounted Sucessfully.\e[39m"
}

if [ $(super_img) ]; then
	echo -e "\e[92mSuper.img:\e[39m $(super_img)"
	mount-super
elif [ $(fastboot_stockrom_zip) ]; then
	echo -e "\e[92mExtracting:\e[39m $(fastboot_stockrom_zip)"
	tar -xzf "$(fastboot_stockrom_zip)" | progress -m
	mount-super
else
	echo -e "\e[91mStock Fastboot ROM Archive Not Found!\nCopy It To Current Dir & Try Again\e[39m"
fi

#fetch extract scripts
fetch() { curl -fso $1 "https://raw.githubusercontent.com/${maintainer}/${device_tree}/${branch}/$1" || err "Fetching $1 Failed"; }

fetch extract-files.sh && chmod +x extract-files.sh
fetch setup-makefiles.sh && chmod +x setup-makefiles.sh
fetch proprietary-files.txt
curl -fso extract_utils.sh https://raw.githubusercontent.com/LineageOS/android_tools_extract-utils/lineage-21.0/extract_utils.sh && chmod +x extract_utils.sh

# Adapt extract scripts
sed -i '/ANDROID_ROOT/s|/../../..||'  extract-files.sh setup-makefiles.sh
sed -i '/HELPER=/s|/tools/extract-utils||'  extract-files.sh setup-makefiles.sh

# Fetch Required Prebuilt Binaries
git clone https://github.com/LineageOS/android_prebuilts_extract-tools.git prebuilts/extract-tools || echo "Prebuilts Already Exists"

# Clone Vendor Tree # use depth=1 for faster clone
git clone --depth=1 ${vendor_tree} vendor/${vendor}/${device} || echo "Vendor Tree Already Exists"

# extract proprietary blobs
./extract-files.sh super/system 2>&1 | tee extract.log

# Commit changes
build_version=$(sudo grep -e "ro.system.build.version.incremental" super/system/system/build.prop | cut -d '=' -f 2)
cd vendor/${vendor}/${device}
git add .
git commit -m "${device}: Update blobs from ${build_version}" \
  -m "${commit_msg}"
cd ../../../

# Cleanup
cleanup
