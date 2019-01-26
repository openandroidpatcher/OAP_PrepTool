# OAP PrepTool

## About

A Linux-only (or WSL under Windows 10) tool for unpacking Android firmware packs in preparation for OAP



## Usage

### Required binaries (packages not installed by default in Ubuntu):

 - brotli
 - simg2img

E.g.:
`sudo apt install brotli android-tools-fsutils libguestfs-tools`

If running in WSL, there may be other dependencies which are not included by default in Ubuntu guest):

`sudo apt install zip unzip`



### Setup and first-build of new device/ROM:

- [Optional] Create a new device directory under ./devices, based on an existing device as a template;
- Extract a recovery ZIP firmware of the device ROM you wish to work with to the device folder. This must include:
  `firmware-update/` *(directory)*
  `META-INF/` *(directory)*
  `boot.img`
  `file_contexts.bin` *or* `file_contexts` *(plain text)*
  `system.img` *or* `system.transfer.list` *with* `system.new.dat[.br]`
  `vendor.img` *or* `vendor.transfer.list` *with* `vendor.new.dat[.br]`
- Run `. ./build/envsetup.sh`;
- Run `lunch [device]` or run `lunch` without arguments to see available devices;
  NB: If any files are missing from the firmware ZIP you extracted, it will say so here and error-out
- Run `prep all` to extract and prepare the base firmware you previously extracted (this needs a few GB of HDD space, will prompt for sudo, and will take some time);
  NB: Check `prep` for other arguments that may be of interest




## Sources and Credits

- https://github.com/wuxianlin/sefcontext_decompile - file_contexts.bin decompiler
- https://github.com/jamflux/make_ext4fs - Updated make_ext4fs (can fetch fs_config from the binaries in /etc)
- https://github.com/osm0sis/Android-Image-Kitchen/tree/AIK-Linux - Source for unpacking/repacking boot.img
- https://github.com/JesusFreke/smali - (bak)smali
- https://github.com/anestisb/vdexExtractor - vdexExtractor