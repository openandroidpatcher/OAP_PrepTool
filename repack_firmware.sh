#!/bin/bash

# Exit codes:
# 64: couldn't create output directory
# 65: boot.img repack failed
# TODO: More verification via other exit codes

# TODO: See if I can replace sudo-requirement with fakeroot
# TODO: actually read the props

#brotliQuality=6
brotliQuality=1

# enforce sudo (no way around this)
if [ $(id -u) != "0" ]; then
	echo "[!] Please run under root/sudo"
	exit 0
fi

PREPTOOL_BIN="$( cd "$( dirname "${BASH_SOURCE[0]}" )/bin" >/dev/null && pwd )"

source "${PREPTOOL_BIN}/preptool_functions.sh"

if [ -d "$1" ]; then
	src="$1"
	out="$(echo "${src}" | sed -e "s|\.oap-prepped\/$||").oap-repacked/"
	if [ "$2" != "" ]; then
		out="$2"
	fi
	# TODO: If {out} already exists, abort
	echo "[#] Starting repack of firmware from"
	echo "    ${src}"
	echo "    ...to..."
	echo "    ${out}"
	
	mkdir -p "${out}/oap"
	if [ ! -d "${out}/oap" ]; then
		echo "[!] Could not create output directory, aborting."
		exit 64
	fi
	
	################ START DEBUG
	if true; then
	################
	# copy whole {src} to {out}
	echo "    [#] Copying {src} to {out}..."
	rsync -a "${src}/" "${out}/"
	
	# Build boot.img
	if [ -d "${out}/boot" ]; then
		echo "[#] Packing boot.img..."
		# repackimg.sh doesn't support parameters and I can't be bothered adapting it, so just copy the boot ramdisk and images to AIK folder
		"${PREPTOOL_BIN}/aik/cleanup.sh" > /dev/null
		rsync -a "${out}/boot/ramdisk/" "${PREPTOOL_BIN}/aik/ramdisk/"
		rsync -a "${out}/boot/split_img/" "${PREPTOOL_BIN}/aik/split_img/"
		"${PREPTOOL_BIN}/aik/repackimg.sh" > "${out}/oap/boot.img-repack.log" 2>&1
		# TODO: AIK re-applies AVB - the devmode plugin should remove that (however it's done)
		if [ ! -f "${PREPTOOL_BIN}/aik/image-new.img" ]; then
			echo "    [!] Failure. Check {out}/boot.img-repack.log for details."
			exit 65
		fi
		mv "${PREPTOOL_BIN}/aik/image-new.img" "${out}/boot.img"
		"${PREPTOOL_BIN}/aik/cleanup.sh" > /dev/null
		# cleanup
		rm -rf "${out}/boot"
	fi
	################
	################ END DEBUG
	fi
	
	# TODO: ART optimization first
	
	# TODO: Use AOSP releasetools properly rather than the subset I've hacked-out below
	
	# build file_contexts.bin
	"${PREPTOOL_BIN}/sefcontext_compile" -o "${out}/oap/file_contexts.bin" "${out}/oap/file_contexts_sorted"
	echo "[i] file_contexts.bin compiled"
	
	################
	# Build system/vendor
	for partName in "system" "vendor"; do
		(
		# TODO: Generate UUID's properly ( see https://github.com/aosp-mirror/platform_build/blob/master/tools/releasetools/add_img_to_target_files.py#L306 )
		# TODO: Fake timestamp? Is it important?
		#MKE2FS_CONFIG="${PREPTOOL_BIN}/mke2fs.conf" E2FSPROGS_FAKE_TIME=0 "${PREPTOOL_BIN}/mke2fs" -O ^has_journal -L system -m 0 -U 29ec4881-24c3-5f9f-ac97-ed077624b328 -E android_sparse,hash_seed=7a71f1bf-6a15-5ead-8986-e121633a19d7 -t ext4 -b 4096 /path/to/system.img 786432
		partBlockSize=$(getOAPSrcProp "${partName}.blockSize")
		partBlockCount=$(getOAPSrcProp "${partName}.blockCount")
		echo "[i] Creating ${partName}.img"
		# restore original ACL
		echo "    [#] Setting ACL..."
		pushd "${out}/${partName}/" >/dev/null
		echo "######## Restore ACL" > "${out}/oap/${partName}.repack.log" 2>&1
		setfacl -R --restore="${out}/oap/${partName}.acl" >> "${out}/oap/${partName}.repack.log" 2>&1
		# TODO: Manual chmod'ing here as new files might be missed...?
		popd >/dev/null
		# build fs_config
		echo "    [#] Building fs_config..."
		fs_config_gen "${out}/oap/file_contexts.bin" "${out}/${partName}/" "${partName}/" > "${out}/oap/fs_config_${partName}.txt"
		# make image
		echo "######## Make img" >> "${out}/oap/${partName}.repack.log" 2>&1
		MKE2FS_CONFIG="${PREPTOOL_BIN}/mke2fs.conf" E2FSPROGS_FAKE_TIME=0 \
			"${PREPTOOL_BIN}/mke2fs" -O ^has_journal -L ${partName} -m 0 -E android_sparse -t ext4 -b "${partBlockSize}" "${out}/${partName}.img" "${partBlockCount}" >> "${out}/oap/${partName}.repack.log" 2>&1
		echo "    [#] Adding files to image..."
		# TODO: Maybe build system.map maybe one day. Seems to only be relevant for keeping OTA delta updates as small as possible though, so probably not.
		#E2FSPROGS_FAKE_TIME=0 "${PREPTOOL_BIN}/e2fsdroid" -T 0 -C /path/to/filesystem_config.txt -B /path/to/system.map -S /path/to/file_contexts.bin -f /path/to/systemIn -a /system /path/to/system.img
		echo "######## Populate img" >> "${out}/oap/${partName}.repack.log" 2>&1
		E2FSPROGS_FAKE_TIME=0 "${PREPTOOL_BIN}/e2fsdroid" -T 0 -C "${out}/oap/fs_config_${partName}.txt" -S "${out}/oap/file_contexts.bin" -f "${out}/${partName}/" -a /"${partName}" "${out}/${partName}.img" >> "${out}/oap/${partName}.repack.log" 2>&1
		# img2sdat
		echo "    [#] Converting image to sdat..."
		echo "######## img2sdat" >> "${out}/oap/${partName}.repack.log" 2>&1
		# NB: transfer list version 4 is still the latest for Pie
		"${PREPTOOL_BIN}/img2sdat/img2sdat.py" -o "${out}/" -v 4 -p "${partName}" "${out}/${partName}.img" >> "${out}/oap/${partName}.repack.log" 2>&1
		if [ ! -f "${out}/${partName}.new.dat" ]; then
			# TODO
			echo "ERROR (FIXME)"
			exit 1
		fi
		rm -f "${out}/${partName}.img"
		# brotli compress
		echo "    [#] Compressing..."
		echo "######## brotli" >> "${out}/oap/${partName}.repack.log" 2>&1
		brotli --quality=${brotliQuality} --rm --output="${out}/${partName}.new.dat.br" "${out}/${partName}.new.dat" 
		# if src .new.dat still exists then error
		# cleanup
		rm -rf "${out}/${partName}"
		)
	done
else
	echo "[i] Usage:"
	echo "    ${BASH_SOURCE[0]} srcFirmwareDir [outDir]"
	exit 0
fi


########################################################################################################################################################
