# OAP PrepTool

## About

A Linux-only (or WSL under Windows 10) tool for unpacking Android firmware packs in preparation for OAP



## Usage

### Required binaries (packages not installed by default in Ubuntu):

 - brotli
 - simg2img

E.g.:
`sudo apt install brotli android-tools-fsutils`

If running in WSL, there may be other dependencies which are not included by default in Ubuntu guest:

`sudo apt install zip unzip`

