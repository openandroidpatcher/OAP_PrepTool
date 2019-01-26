#!/bin/bash

# Exit codes:
# 64: couldn't create output directory
# 65: boot.img unpack failed
# 66: boot.img does not exist in firmware
# 67: .br decompression error
# 68: .new.dat > img conversion error
# 69: Sparse image > raw image conversion error
# 70: Error dumping img contents
# 71: Missing required system/vendor img
# 72: Missing plat_file_contexts and/or nonplat_file_contexts (image unpack failed?)
# 73: Deopt error; a specific package didn't have exactly one APK
# 74: Deopt error; dex could not be extracted from vdex
# 75: Deopt error; couldn't zip dex back to jar/apk
# 76: Deopt error; other edge-case error
# 77: Deopt error; BOOTCLASSPATH entry missing from RAMDisk rc files, or out of sync with vdex table

# TODO LIST:
# - Port over file_contexts rebuild from java
# - Support for deopting non-boot packages which have multiple classes.dex files (hard-coded right now)
# - Fix assumption that we're on arm64

# enforce sudo
if [ $(id -u) != "0" ]; then
	echo "[!] Please run under root/sudo"
	exit 0
fi

PREPTOOL_BIN="$( cd "$( dirname "${BASH_SOURCE[0]}" )/bin" >/dev/null && pwd )"
# debug flag
deoptOnly="false"

if [ -d "$1" ]; then
	src="$1"
	out="${src%/}.oap-prepped"
	if [ "$2" != "" ]; then
		out="$2"
	fi
	echo "[#] Starting unpack of firmware from"
	echo "    ${src}"
	echo "    ...to..."
	echo "    ${out}"
	
	if [ ! -d "${out}" ]; then
		mkdir "${out}"
		if [ ! -d "${out}" ]; then
			echo "[!] Could not create output directory, aborting."
			exit 64
		fi
	fi
	
	if [ "${deoptOnly}" != "true" ]; then
		# extract boot.img
		if [ -f "${src}/boot.img" ]; then
			# boot.img found
			if [ -d "${out}/boot" ]; then
				# already extracted so skip
				echo "[i] {out}/boot/ already exists, skipping boot.img"
			else
				echo "[#] Extracting boot.img..."
				mkdir "${out}/boot"
				"${PREPTOOL_BIN}/aik/unpackimg.sh" --nosudo "${src}/boot.img" > "${out}/boot.img-unpack.log" 2>&1
				mv "${PREPTOOL_BIN}/aik/split_img" "${out}/boot/split_img"
				mv "${PREPTOOL_BIN}/aik/ramdisk" "${out}/boot/ramdisk"
				if [ ! -f "${out}/boot/split_img/boot.img-zImage" -o ! -f "${out}/boot/ramdisk/init" ]; then
					echo "    [!] Failure detected. Check {out}/boot.img-unpack.log for details."
					exit 65
				else
					echo "    ...OK!"
				fi
			fi
		else
			if [ ! -d "${out}/boot" ]; then
				# no boot.img nor boot/ so error-out
				echo "[!] Error - {src}/boot.img does not exist and neither does {out}/boot/"
				exit 66
			fi
		fi
		
		# extract system and vendor
		for imageName in "system" "vendor"; do
			if [ -d "${out}/${imageName}" ]; then
				echo "[i] {out}/${imageName} already exists, skipping"
				continue
			fi
			echo "[#] Processing ${imageName} ..."
			
			if [ -f "${src}/${imageName}.new.dat.br" ]; then
				# brotli-compressed image found
				if [ ! -f "${out}/${imageName}.new.dat" ]; then
					# .new.dat doesn't exist in out
					echo "    [#] Decompressing ${imageName}.new.dat.br to {out}/${imageName}.new.dat (temporary)..."
					brotli -d "${src}/${imageName}.new.dat.br" -o "${out}/${imageName}.new.dat"
					if [ $? -ne 0 ]; then
						# brotli decompress failed
						echo "        [!] Error decompressing ${src}/${imageName}.new.dat.br!"
						exit 67
					else
						echo "        ...OK"
					fi
				else
					echo "    [i] {out}/${imageName}.new.dat already exists, skipping ${imageName}.new.dat.br decompression"
				fi
			fi
			
			if [ -f "${out}/${imageName}.new.dat" -a -f "${src}/${imageName}.transfer.list" ]; then
				# .new.dat and .transfer.list found
				if [ ! -f "${src}/${imageName}.img" ]; then
					# .img doesn't exist
					echo "    [#] Converting ${imageName}.new.dat to ${imageName}.img ..."
					"${PREPTOOL_BIN}/sdat2img.py" "${src}/${imageName}.transfer.list" "${out}/${imageName}.new.dat" "${out}/${imageName}.img" >/dev/null
					if [ $? -ne 0 ]; then
						# convert failed
						echo "        [!] Error converting ${src}/${imageName}.new.dat!"
						exit 68
					fi
					# clean on successful decompress
					rm -f "${out}/${imageName}.new.dat"
				else
					echo "    [i] {out}/${imageName}.img already exists, skipping ${imageName}.new.dat conversion."
				fi
			fi
			
			if [ -f "${out}/${imageName}.img" ]; then
				# an .img is found
				sparse_magic=`hexdump -e '"%02x"' -n 4 "${out}/${imageName}.img"`
				if [ "$sparse_magic" = "ed26ff3a" ]; then
					# sparse image found, convert to raw first
					echo "    [#] Sparse .img detected, converting to raw image..."
					mv "${out}/${imageName}.img" "${out}/${imageName}.simg"
					simg2img "${out}/${imageName}.simg" "${out}/${imageName}.img"
					if [ ! -f "${out}/${imageName}.img" ]; then
						# simg > img failed
						echo "        [!] Error converting sparse image!"
						exit 69
					fi
				fi
				
				# We use debugfs here as it's the only WSL-compatible way to extract ext4 images
				echo "    [#] Dumping {src}/${imageName}.img contents to {out}/${imageName}/"
				rm -f "${out}/${imageName}"
				mkdir "${out}/${imageName}"
				debugfs "${out}/${imageName}.img" -R "rdump / ${out}/${imageName}/" >/dev/null
				if [ $? -eq 0 ]; then
					# dump succeeded, do permissions
					echo "    [#] Backing-up ACL..."
					pushd "${out}/${imageName}/" >/dev/null
					getfacl -R . > "../${imageName}.acl"
					echo "    [#] Clearing permissions..."
					chmod -R 777 .
					popd >/dev/null
				else
					echo "        [!] Error - could not dump ext4 image"
					exit 70
				fi
			else
				if [ ! -d "${src}/${imageName}" ]; then
					# .img file not found, nor is extracted filesystem
					echo "    [!] Error - {src}/${imageName}.img is missing"
					exit 71
				fi
			fi
		done
		
		# rebuild file_contexts
		fileContextsSrc1="${out}/system/etc/selinux/plat_file_contexts"
		# NB: nonplat_file_contexts was renamed to vendor_file_contexts in Pie
		fileContextsSrc2="${out}/vendor/etc/selinux/vendor_file_contexts"
		if [ ! -f "${fileContextsSrc1}" -o ! -f "${fileContextsSrc2}" ]; then
			echo "[!] Error - filesystem images did not appear to unpack correctly (missing required file_contexts)"
			exit 72
		fi
		echo "[#] Rebuilding file_contexts..."
		cat "${fileContextsSrc1}" "${fileContextsSrc2}" > "${out}/file_contexts_tmp"
		# Sort and remove duplicate entries. OAP java kitchen has a better method for this, but that's Java - port it over as a standalone applet
		sort -u -k1,1 "${out}/file_contexts_tmp" > "${out}/file_contexts"
		rm -f "${out}/file_contexts_tmp"
	fi
	
	# Deopt
	if [ -f "${out}/system/framework/arm64/boot-framework.oat" ]; then
		echo "[i] Starting deopt (deodex), logging to {out}/deopt.log"
		rm -rf "${out}/deopt.log"
		rm -rf "${out}/deopt_tmp"
		deoptOut="${out}/deopt_tmp/OUT"
		mkdir -p "${deoptOut}"
		echo "    [#] Copying packages to temporary directory..."
		rsync -a "${out}/system/framework/" "${deoptOut}/framework/"
		rsync -a "${out}/system/app/" "${deoptOut}/app/"
		rsync -a "${out}/system/priv-app/" "${deoptOut}/priv-app/"
		### DEBUG switch
		if true; then
		# First deopt app and priv-app
		for systemSubdir in "app" "priv-app"; do
			echo "    [#] Deopt ${systemSubdir}..."
			pushd "${deoptOut}/${systemSubdir}/" > /dev/null
			deOptDirs2do=(*/)
			popd > /dev/null
			for appDir in "${deOptDirs2do[@]}"; do
				# trim trailing slashes
				appDir=$(echo $appDir | sed 's|/*$||')
				echo "        [#] system/${systemSubdir}/${appDir}..."
				echo "        [#] system/${systemSubdir}/${appDir}..." >>"${out}/deopt.log" 2>&1
				# verify that there's exactly one apk file, if not then abort
				pushd "${deoptOut}/${systemSubdir}/${appDir}/" > /dev/null
				appApkFiles=(*.apk)
				popd > /dev/null
				if [ ${#appApkFiles[@]} -ne 1 ]; then
					# echo to console and log
					echo "            [!] Could not find exactly one APK file for this package. Deopt aborted."
					echo "            [!] Could not find exactly one APK file for this package. Deopt aborted." >>"${out}/deopt.log" 2>&1
					exit 73
				fi
				
				# verify that there's exactly one vdex file, if not then skip it (assume already deopt'd)
				if [ -d "${deoptOut}/${systemSubdir}/${appDir}/oat/arm64/" ]; then
					pushd "${deoptOut}/${systemSubdir}/${appDir}/oat/arm64/" > /dev/null
					appVdexFiles=(*.vdex)
					popd > /dev/null
				fi
				
				# check if the APK already contains a classes.dex (e.g. AndroidPlatformServices)
				unzip -l "${deoptOut}/${systemSubdir}/${appDir}/${appApkFiles[0]}" | grep -q ' classes.dex' >>"${out}/deopt.log" 2>&1
				if [ "$?" == "0" ];	then
					# echo to console and log
					echo "            [i] APK already contains classes.dex - skipping deopt (and deleting redundant odex/vdex if present)"
					echo "            [i] APK already contains classes.dex - skipping deopt (and deleting redundant odex/vdex if present)" >>"${out}/deopt.log" 2>&1
					rm -rf "${deoptOut}/${systemSubdir}/${appDir}/oat"
					continue
				fi
				
				# verify exactly one vdex file exists
				if [ ${#appVdexFiles[@]} -ne 1 -o ! -d "${deoptOut}/${systemSubdir}/${appDir}/oat/arm64/" ]; then
					# echo to console and log
					echo "            [i] No vdex file found, skipping (either already deopted or resource-only APK)"
					echo "            [i] No vdex file found, skipping (either already deopted or resource-only APK)" >>"${out}/deopt.log" 2>&1
					continue
				fi
				
				# extract dex from vdex
				deoptDexOutput="${deoptOut}/../vdexExtractor_deodexed/${appDir}/${appDir}_classes.dex"
				"${PREPTOOL_BIN}/vdexExtractor_deopt.sh" -i "${deoptOut}/${systemSubdir}/${appDir}/oat/arm64/${appVdexFiles[0]}" -o "${deoptOut}/../" >>"${out}/deopt.log" 2>&1
				# error-out if non-zero return or output dex missing
				if [ $? -ne 0 -o ! -f "${deoptDexOutput}" ]; then
					echo "            [!] Error during vdex extraction (see {out}/deopt.log)."
					echo "            [!] Error during vdex extraction" >>"${out}/deopt.log" 2>&1
					exit 74
				fi
				
				# got the dex file - rename and zip it to the APK
				mv "${deoptDexOutput}" "${deoptOut}/${systemSubdir}/${appDir}/classes.dex"
				pushd "${deoptOut}/${systemSubdir}/${appDir}/" > /dev/null
				zip -u9 "${appApkFiles[0]}" "classes.dex" >>"${out}/deopt.log" 2>&1
				if [ $? -ne 0 -a $? -ne 12 ]; then
					# Note to self: error code 12 = "nothing to do" (doesn't need updating)
					echo "            [!] Error during deopt process (zip error; see {out}/deopt.log)."
					echo "            [!] Error during deopt process" >>"${out}/deopt.log" 2>&1
					exit 75
				fi
				# cleanup
				rm -f "./classes.dex"
				rm -rf "${deoptOut}/${systemSubdir}/${appDir}/oat"
				popd > /dev/null
			done
		done
		rm -rf "${deoptOut}/../vdexExtractor_deodexed"
		# done deopt app and priv-app
		
		# Do non-bootclasspath framework jar's
		echo "    [#] Deopt framework..."
		pushd "${deoptOut}/framework/oat/arm64/" > /dev/null
		deOptVdexs2do=(*.vdex)
		popd > /dev/null
		for vdexFile in "${deOptVdexs2do[@]}"; do
			targetJar="${vdexFile%.*}.jar"
			echo "        [#] ${targetJar}..."
			if [ ! -f "${deoptOut}/framework/${targetJar}" ]; then
				echo "        [!] Error - SHOULD NOT HAPPEN - could not find ${targetJar}. Aborting."
				exit 76
			fi
			deoptDexOutput="${deoptOut}/../vdexExtractor_deodexed/${vdexFile%.*}/${vdexFile%.*}_classes.dex"
			"${PREPTOOL_BIN}/vdexExtractor_deopt.sh" -i "${deoptOut}/framework/oat/arm64/${vdexFile}" -o "${deoptOut}/.." >>"${out}/deopt.log" 2>&1
			# error-out if non-zero return or output dex missing
			if [ $? -ne 0 -o ! -f "${deoptDexOutput}" ]; then
				echo "            [!] Error during vdex extraction (see {out}/deopt.log)."
				echo "            [!] Error during vdex extraction" >>"${out}/deopt.log" 2>&1
				exit 74
			fi
			
			# got the dex file - rename and zip it to the APK
			mv "${deoptDexOutput}" "${deoptOut}/framework/classes.dex"
			pushd "${deoptOut}/framework/" > /dev/null
			zip -u9 "${targetJar}" "classes.dex" >>"${out}/deopt.log" 2>&1
			if [ $? -ne 0 -a $? -ne 12 ]; then
				# Note to self: error code 12 = "nothing to do" (doesn't need updating)
				echo "            [!] Error during deopt process (zip error; see {out}/deopt.log)."
				echo "            [!] Error during deopt process" >>"${out}/deopt.log" 2>&1
				exit 75
			fi
			rm "classes.dex"
		done
		# cleanup
		rm -rf "${deoptOut}/framework/oat"
		rm -rf "${deoptOut}/../vdexExtractor_deodexed"
		
#echo "~~~ Returning early (before bootclasspath deopt)"
#exit 0
		
		### DEBUG switch
		fi
		
		
		###############################
		# Finally do boot jars
		###############################
		echo "    [#] Preparing to deopt boot jars..."
		# Get the readable strings from any 'ol .oat file (they all contain the bootclasspath remapped to .art file paths which is alongside vdex files)
		rm -f "${deoptOut}_vDexStringsDump"
		strings "${deoptOut}/framework/arm64/boot-framework.oat" > "${deoptOut}_vDexStringsDump"
		# Trim the string dump to the interesting part (the text between 'bootclasspath' and 'compiler-filter' lines), and also line-split on ':' character
		vDexBootClassPath="$(sed -n '/bootclasspath/,/compiler-filter/{/bootclasspath/b;/compiler-filter/b;p}' "${deoptOut}_vDexStringsDump" | tr ":" "\n")"
		rm -f "${deoptOut}_vDexStringsDump"
		# Finally, trim to a format of "originalPackageDirectory/optFilenameWithoutExtension". We can use basename/dirname to easily parse that.
		# (Strip text after and including '/out/target/', up to and including '/system/framework/arm64/', then strip the .art extension)
		vDexBootClassesUnsplit="$(sed 's/out\/target\/.*\/system\/framework\/arm64\///g; s/\.art//g' <<< "${vDexBootClassPath}")"
		#vDexBootClasses="$(readarray -t y <<< "${vDexBootClassesUnsplit}")"
		IFS=$'\n' vDexBootClasses=($vDexBootClassesUnsplit)
		# Now, "${vDexBootClasses}" will contain a list like so:
		#     /system/framework/boot
		#     [...]
		#     /system/app/miuisystem/boot-miuisystem
		# ...i.e. the vdex filename (without extension) and their origin path. It will correspond to the init bootclasspath:
		#     /system/framework/QPerformance.jar
		#     [...]
		#     /system/app/miuisystem/miuisystem.apk
		# Deopt'ing the non-boot jars is relatively trivial though

		# Next, get the BOOTCLASSPATH from initramfs - need to find the file that contains BOOTCLASSPATH entry first
		bootClassPathFile="$(grep -Elr --include=*.rc "BOOTCLASSPATH" "${out}/boot/ramdisk/")"
		if [ "${bootClassPathFile}" == "" ]; then
			echo "        [!] Error - Could not find BOOTCLASSPATH entry in RAMDisk. Maybe boot.img extraction failed?"
			exit 77
		fi
		initBootClassesRaw="$(cat "${bootClassPathFile}" | grep -i 'export BOOTCLASSPATH ' | sed 's|^[ \t]*export BOOTCLASSPATH[ \t]*||')"
		IFS=':' read -r -a initBootClasses <<< "${initBootClassesRaw}"

		# cheap safety check: make sure both bootclasspath lists are equal size. we assume that the *order* is the same for both arrays 
		# of bootclasspath entries, since they have to be AFAIK
		if [ ! ${#initBootClasses[@]} -eq ${#vDexBootClasses[@]} ]; then
			echo "        [!] Bootclasspath size mismatch between initramfs (${#initBootClasses[@]}) and ART cache (${#vDexBootClasses[@]})."
			exit 77
		fi
		
		echo "    [#] Deopt boot jars..."
		mkdir -p "${deoptOut}/boot"
		for i in "${!vDexBootClasses[@]}"; do
			echo "        [#] $(basename ${vDexBootClasses[i]}).vdex ( for ${initBootClasses[i]} )..."
			"${PREPTOOL_BIN}/vdexExtractor_deopt.sh" -i "${deoptOut}/framework/$(basename ${vDexBootClasses[i]}).vdex" -o "${deoptOut}/boot" >>"${out}/deopt.log" 2>&1
			# error-out if non-zero return
			if [ $? -ne 0 ]; then
				echo "            [!] Error during vdex extraction (see deopt.log)."
				exit 74
			fi
			# rename and move the dex file(s) in preparation for zipping back to the original package...
			pushd "${deoptOut}/boot/vdexExtractor_deodexed/$(basename ${vDexBootClasses[i]})" > /dev/null
			for dexFile in *.dex; do
				mv "${dexFile}" "${dexFile/$(basename ${vDexBootClasses[i]})_/}"
			done
			targetDir="${deoptOut}/$(dirname ${initBootClasses[i]/system/})/"
			mv *.dex "${targetDir}"
			popd > /dev/null
			# ...now zip it back to the APK
			pushd "${targetDir}" > /dev/null
			zip -u9 "$(basename ${initBootClasses[i]})" *.dex >>"${out}/deopt.log" 2>&1
			if [ $? -ne 0 -a $? -ne 12 ]; then
				# Note to self: error code 12 = "nothing to do" (doesn't need updating)
				echo "            [!] Error during deopt process (zip error; see {out}/deopt.log)."
				echo "            [!] Error during deopt process" >>"${out}/deopt.log" 2>&1
				exit 75
			fi
			rm -f "./classes*.dex"
			# also delete original vdex
			rm -f "${deoptOut}/framework/$(basename ${vDexBootClasses[i]}).vdex"
			popd > /dev/null
		done
		
		#for bootVdexFile in "${deoptOut}/framework"/*.vdex; do
		
		#done
		
		#for i in "${!vDexBootClasses[@]}"; do 
			#echo "        [#] $(basename ${vDexBootClasses[i]}).vdex ( for ${initBootClasses[i]} )..."
			#"${KITCHEN_BIN}/vdexExtractor_deopt.sh" -i "${deoptOut}/framework/arm64/$(basename ${vDexBootClasses[i]}).vdex" -o "${deoptOut}/boot/$(basename ${vDexBootClasses[i]})" > /dev/null
			#vdexExtractorOutput="${deoptOut}/boot/$(basename ${vDexBootClasses[i]})/vdexExtractor_deodexed/"
			#if [ $? -ne 0 -o 
			
			
			#echo "---------------------------------"
			#echo ${vDexBootClasses[i]}
			#echo ${initBootClasses[i]}
			#echo "---------------------------------"
		#done;
	else
		echo "[i] Skipping deopt (already done?)"
	fi
else
	echo "[i] Usage:"
	echo "    ${BASH_SOURCE[0]} srcFirmwareDir [outDir]"
	exit 0
fi

echo "[i] All done!"
echo ""
exit 0


########################################################################################################################################################
