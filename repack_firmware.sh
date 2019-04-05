#!/bin/bash

# Exit codes:
# 64: couldn't create output directory
# 65: boot.img repack failed

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
	
	if [ -d "${src}/boot" ]; then
		echo "[#] Packing boot.img..."
		# repackimg.sh doesn't support parameters and I can't be bothered updating it, so copy the boot ramdisk and images to AIK folder
		"${PREPTOOL_BIN}/aik/cleanup.sh" > /dev/null
		rsync -a "${src}/boot/ramdisk/" "${PREPTOOL_BIN}/aik/ramdisk/"
		rsync -a "${src}/boot/split_img/" "${PREPTOOL_BIN}/aik/split_img/"
		"${PREPTOOL_BIN}/aik/repackimg.sh" > "${out}/oap/boot.img-repack.log" 2>&1
		# TODO: AIK re-applies AVB - the devmode plugin should remove that (however it's done)
		if [ ! -f "${PREPTOOL_BIN}/aik/image-new.img" ]; then
			echo "    [!] Failure. Check {out}/boot.img-repack.log for details."
			exit 65
		fi
		mv "${PREPTOOL_BIN}/aik/image-new.img" "${out}/boot.img"
		"${PREPTOOL_BIN}/aik/cleanup.sh" > /dev/null
	fi
else
	echo "[i] Usage:"
	echo "    ${BASH_SOURCE[0]} srcFirmwareDir [outDir]"
	exit 0
fi


########################################################################################################################################################
