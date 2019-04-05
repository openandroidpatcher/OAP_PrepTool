#!/bin/bash

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
