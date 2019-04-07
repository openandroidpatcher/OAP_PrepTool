#!/bin/bash

# Assumption: "${out}/oap/srcinfo.prop" is valid
# $1 = Prop key
# $2 = New value
setOAPSrcProp() {
	propFile="${out}/oap/srcinfo.prop"
	propKey="$1"
	propValue="$2"
	if [ ! -f "${propFile}" ]; then touch "${propFile}"; fi
	if grep -q "${propKey}=" "${propFile}"; then
		# prop key already found, update value
		propKeyEscaped=`getEscapedVarForSed "${propKey}"`
		propValueEscaped=`getEscapedVarForSed "${propValue}"`
		sed -i "s|${propKeyEscaped}.*|${propKeyEscaped}=${propValueEscaped}|g" "${propFile}"
	else
		echo "${propKey}=${propValue}" >>"${propFile}"
	fi
}

# Assumption: "${out}/oap/srcinfo.prop" is valid
# $1 = Prop key
getOAPSrcProp() {
	propFile="${out}/oap/srcinfo.prop"
	propKey="$1"
	if grep -q "${propKey}=" "${propFile}"; then
		propKeyEscaped=`getEscapedVarForSed "${propKey}"`
		grep "${propKey}=" "${propFile}" | sed "s|${propKeyEscaped}=||g"
	fi
}

# ported from AOSP makefile
# $1 = full path to file_contexts.bin
# $2 = full path to image root
# $3 = string to substitute for current directory (e.g. "system/")
fs_config_gen() {
	(
	#(cd $(1); find . -type d | sed 's,$$,/,'; find . \! -type d) | cut -c 3- | sort | sed 's,^,$(2),' | $(HOST_OUT_EXECUTABLES)/fs_config -C -D $(TARGET_OUT) -S $(SELINUX_FC) -R "$(2)"
	fileContextsPath="$1"
	fsPath="$2"
	fsPrefix="$3"
	pushd "${fsPath}" > /dev/null
	dirListing=$(find . -type d | sed 's,$$,/,'; find . \! -type d)
	dirListingSorted=$(echo "${dirListing}" | cut -c 3- | sort | sed "s,^,${fsPrefix},")
	echo "${dirListingSorted}" | "${PREPTOOL_BIN}/fs_config" -C -D "${out}" -S "${fileContextsPath}" -R "${fsPrefix}"
	popd > /dev/null
	)
}

# Thanks to "Nominal Animal" @ linuxquestions.org
getEscapedVarForSed() {
	 # start with the original pattern
    escaped="$1"

    # escape all backslashes first
    escaped="${escaped//\\/\\\\}"

    # escape slashes
    escaped="${escaped//\//\\/}"

    # escape asterisks
    escaped="${escaped//\*/\\*}"

    # escape full stops
    escaped="${escaped//./\\.}"    

    # escape [ and ]
    escaped="${escaped//\[/\\[}"
    escaped="${escaped//\[/\\]}"

    # escape ^ and $
    escaped="${escaped//^/\\^}"
    escaped="${escaped//\$/\\\$}"

    # remove newlines
    escaped="${escaped//[$'\n']/}"

    # Now, "$escape" should be safe as part of a normal sed pattern.
    # Note that it is NOT safe if the -r option is used.
	echo "${escaped}"
}
