#!/bin/bash

##############################################################################
#
# Module: build-with-cli.sh
#
# Function:
#	This script must be sourced; it sets variables used by other
#	scripts in this directory.
#
# Usage:
#	build-with-cli.sh --help
#
# Copyright and License:
#	See accompanying LICENSE.md file
#
# Author:
#	Terry Moore, MCCI	February 2021
#
##############################################################################

# install arduino-cli from github using:
#  curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh

# if Linux, to set up:
#  sudo dpkg --add-architecture i386
#  sudo apt install libc6-i386

# exit if any errors encountered
set -e

INVOKEDIR=$(realpath .)
readonly INVOKEDIR

SCRIPTNAME=$(basename "$0")
readonly SCRIPTNAME

[[ -z "$PNAME" ]] && PNAME="$SCRIPTNAME"

PDIR=$(realpath "$(dirname "$0")")
readonly PDIR

typeset -i OPTDEBUG=0
typeset -i OPTVERBOSE=0

#---- project settings -----
readonly OPTKEYFILE_DEFAULT="$INVOKEDIR/keys/project.pem"
readonly OPTREGION_DEFAULT=us915
readonly OPTNETWORK_DEFAULT=ttn
readonly OPTSUBBAND_DEFAULT=default

readonly OPTCLOCK_DEFAULT=32
declare -A OPTCLOCK_LIST
OPTCLOCK_LIST=([2]=msi2097k [4]=msi4194k [16]=hsi16m [24]=pll24m [32]=pll32m)
readonly OPTCLOCK_LIST

readonly OPTXSERIAL_DEFAULT=usb
declare -A OPTXSERIAL_LIST
OPTXSERIAL_LIST=([usb]=usb [hw]=generic [none]=none [both]=usbhwserial)
readonly OPTXSERIAL_LIST

readonly ARDUINO_FQBN="mcci:stm32:mcci_catena_4610"
readonly ARDUINO_SOURCE=libraries/mcci-catena-4430/examples/Catena4430_Sensor/Catena4430_Sensor.ino
readonly BOOTLOADER_NAME=McciBootloader_46xx

##############################################################################
# verbose output
##############################################################################

function _verbose {
	if [ "$OPTVERBOSE" -ne 0 ]; then
		echo "$PNAME:" "$@" 1>&2
	fi
}

##############################################################################
# debug output
##############################################################################

function _debug {
	if [ "$OPTDEBUG" -ne 0 ]; then
		echo "$@" 1>&2
	fi
}

##############################################################################
# error output
##############################################################################

#### _error: define a function that will echo an error message to STDERR.
#### using "$@" ensures proper handling of quoting.
function _error {
	echo "$@" 1>&2
}

#### _fatal: print an error message and then exit the script.
function _fatal {
	_error "$@" ; exit 1
}

##############################################################################
# help
##############################################################################

function _help {
    less <<.
${PNAME} calls ${SCRIPTNAME} in order to build the Model 4811
firmware $(basename ${ARDUINO_SOURCE}) using the arduino-cli tool.

All the work is in the script ${SCRIPTNAME} is invoked from a
top-level collection, not directly.

Options:
    --clean does a clean prior to building.

    --verbose causes more info to be displayed.

    --test makes this a test-signing build (no use of private key)

    --key={file} gives the path to the public/private key files.
        The default is ${OPTKEYFILE_DEFAULT}. The public file is
        found by changing "*.pem" to "*.pub.pem".

    --region={region} sets the region for the build; this must
        be a recognized region. The default is ${OPTREGION_DEFAULT}.

    --network={netid} sets the target network for the build. The
        default is ${OPTNETWORK_DEFAULT}.

    --subband={subband} sets the target subband. This should be
        'default', or a zero-origin number. The default is ${OPTSUBBAND_DEFAULT}.

    --clock={rate} sets the target clock rate. This should be one of
        {${!OPTCLOCK_LIST[@]}}. The default is ${OPTCLOCK_DEFAULT}.

    --serial={how} specifies how the target serial port is to be configured.
        This should be in {${!OPTXSERIAL_LIST[@]}}.  Clock rate must be >= 16
        in order for USB serial to work. The default is ${OPTXSERIAL_DEFAULT}.

    --debug turns on more debug output.

    --help prints this message.
.
}

##############################################################################
# extract version
##############################################################################

# $1 is the name of the script
# result is version as either x.y.z-N or x.y.z (if pre-release tag is -0)
function _getversion {
    sed -n -e '/^constexpr std::uint32_t kAppVersion /s/^.*makeVersion[ \t]*([ \t]*\([0-9]*\)[ \t]*,[ \t]*\([0-9]*\)[ \t]*,[ \t]*\([0-9]*\)[ \t]*,[ \t]*\([0-9]*\)[ \t]*).*/\1.\2.\3_pre\4/p' \
           -e '/^constexpr std::uint32_t kAppVersion /s/^.*makeVersion[ \t]*([ \t]*\([0-9]*\)[ \t]*,[ \t]*\([0-9]*\)[ \t]*,[ \t]*\([0-9]*\)[ \t]*).*/\1.\2.\3/p' "$1" |
        sed -e 's/_pre0$//'
}

##############################################################################
# the script
##############################################################################

typeset -i OPTTESTSIGN=0
#typeset -i OPTVERBOSE=0    -- above
typeset -i OPTCLEAN=0

OPTKEYFILE="${OPTKEYFILE_DEFAULT}"
OPTREGION="${OPTREGION_DEFAULT}"
OPTNETWORK="${OPTNETWORK_DEFAULT}"
OPTSUBBAND="${OPTSUBBAND_DEFAULT}"
OPTXSERIAL="${OPTXSERIAL_DEFAULT}"
OPTCLOCK="${OPTCLOCK_DEFAULT}"

# make sure everything is clean
for opt in "$@"; do
    case "$opt" in
    "--clean" )
        rm -rf "$OUTPUT_ROOT"
        OPTCLEAN=1
        ;;
    "--verbose" )
        OPTVERBOSE=$((OPTVERBOSE + 1))
        if [[ $OPTVERBOSE -gt 1 ]]; then
            ARDUINO_CLI_FLAGS="${ARDUINO_CLI_FLAGS}${ARDUINO_CLI_FLAGS+ }-v"
        fi
        ;;
    "--test" )
        OPTTESTSIGN=1
        ;;
    "--key="* )
        OPTKEYFILE=$(realpath "${opt#--key=}")
        OPTTESTSIGN=0
        ;;
    "--help" )
        _help
        exit 0
        ;;
    "--network="* )
        OPTNETWORK="${opt#--network=}"
        ;;
    "--region="* )
        OPTREGION="${opt#--region=}"
        ;;
    "--subband="* )
        OPTSUBBAND="${opt#--subband=}"
        ;;
    "--clock="* )
        OPTCLOCK="${opt#--clock=}"
        ;;
    "--serial="* )
        OPTXSERIAL="${opt#--serial=}"
        ;;
    "--debug" )
        OPTDEBUG=1
        ;;
    *)
        echo "not recognized: $opt -- use '--help' for help."
        exit 1
        ;;
    esac
done

#--- change to directory containing script
cd "$PDIR"

[[ -z "$OPTREGION" ]] && _fatal "region must not be empty"
[[ -z "$OPTNETWORK" ]] && _fatal "network must not be empty"
[[ -z "$OPTSUBBAND" ]] && _fatal "subband must not be empty"
[[ -z "${OPTXSERIAL_LIST[${OPTXSERIAL}]}" ]] && _fatal "--serial=$OPTXSERIAL not in ${!OPTXSERIAL_LIST[*]}"
[[ -z "${OPTCLOCK_LIST[${OPTCLOCK}]}" ]] && _fatal "--clock=$OPTCLOCK not in ${!OPTCLOCK_LIST[*]}"

##############################################################################
# Compute the arduino platform options to be used.
##############################################################################

ARDUINO_OPTIONS="$(echo "
                    upload_method=STLink
                    xserial=${OPTXSERIAL_LIST[${OPTXSERIAL}]}
                    sysclk=${OPTCLOCK_LIST[${OPTCLOCK}]}
                    boot=trusted
                    opt=osstd
                    lorawan_region=${OPTREGION}
                    lorawan_network=${OPTNETWORK}
                    lorawan_subband=${OPTSUBBAND}
                    " | xargs echo)"
readonly ARDUINO_OPTIONS
_debug "ARDUINO_OPTIONS: ${ARDUINO_OPTIONS}"

##############################################################################
# fetch sketch version to variable
##############################################################################

SKETCHVERSION=$(_getversion "$ARDUINO_SOURCE")
readonly SKETCHVERSION
[[ -z "$SKETCHVERSION" ]] && _fatal "Version not found in $ARDUINO_SOURCE"

_verbose "Building sketch: version $SKETCHVERSION"

##############################################################################
# create output signature
##############################################################################

if [[ $OPTTESTSIGN -eq 0 ]]; then
    BUILDKEYSIG="$(basename "${OPTKEYFILE}" .pem | tr ' \t-' _)"
else
    BUILDKEYSIG=mcci_test
fi

##############################################################################
# Deal wtih BSP and output paths
##############################################################################

if [[ ! -d "$INVOKEDIR"/build ]]; then
    _verbose "No build dir in $INVOKEDIR: create it"
    mkdir "$INVOKEDIR"/build
fi

BSP_MCCI=$HOME/.arduino15/packages/mcci
BSP_CORE=$BSP_MCCI/hardware/stm32/
LOCAL_BSP_CORE="$(realpath extra/Arduino_Core_STM32)"
OUTPUT_SIG="v${SKETCHVERSION}-${OPTNETWORK}-${OPTREGION}-${OPTSUBBAND}-clk${OPTCLOCK}-ser${OPTXSERIAL}-${BUILDKEYSIG}"
OUTPUT_ROOT="$(realpath "$INVOKEDIR/build/$(basename "$ARDUINO_SOURCE")-${OUTPUT_SIG}")"
OUTPUT="${OUTPUT_ROOT}/ide"
OUTPUT_BOOTLOADER="${OUTPUT_ROOT}/boot"

# --- post checks
if [[ ! -d "${OUTPUT}" ]]; then
    # the IDE hammers the specified directory; and we need other things here...
    # so make it a subdir of build.
    mkdir -p "${OUTPUT}"
fi
if [[ ! -d "${OUTPUT_BOOTLOADER}" ]]; then
    mkdir -p "${OUTPUT_BOOTLOADER}"
fi

if [[ -d ~/Arduino/libraries ]]; then
    printf "%s\n" "Error: you have a ~/Arduino/libraries directory." \
                  "Please remove or hide it to use this script."
    exit 1
fi

# set up links to IDE
if [[ ! -d "$BSP_CORE" ]]; then
    echo "Not installed: $BSP_CORE"
    exit 1
fi

function _cleanup {
    [[ -f "$PRIVATE_KEY_UNLOCKED" ]] && shred -u "$PRIVATE_KEY_UNLOCKED"
    if [[ -h "$BSP_CORE"/2.8.0 ]]; then
        _verbose "remove symbolic link"
        rm "$BSP_CORE"/2.8.0
    fi
    if [[ -n "$SAVE_BSP_CORE" ]] && [[ -d "$SAVE_BSP_CORE" ]]; then
        _verbose "restore BSP"
        mv "$SAVE_BSP_CORE" "$BSP_CORE"/"$SAVE_BSP_VER"
    fi
    rm -f "$LOCAL_BSP_CORE"/platform.local.txt
}

function _errcleanup {
    _verbose "Build error: remove output files"
    rm -f "$OUTPUT"/*.elf "$OUTPUT"/*.bin "$OUTPUT"/*.hex "$OUTPUT"/*.dfu
}

trap '_cleanup' EXIT
trap '_errcleanup' ERR

# set up BSP
OLD_BSP_CORE="$(echo "$BSP_CORE"/*)"
if [[ ! -h "$OLD_BSP_CORE" ]] && [[ -d "$OLD_BSP_CORE" ]]; then
    _verbose "save and overlay BSP"
    SAVE_BSP_VER="$(basename "$OLD_BSP_CORE")"
    SAVE_BSP_CORE="$(dirname "$BSP_CORE")"/stm32-"$SAVE_BSP_VER"
    mv "$OLD_BSP_CORE" "$SAVE_BSP_CORE"
    ln -sf "$LOCAL_BSP_CORE" "$BSP_CORE"/2.8.0
elif [[ -h "$OLD_BSP_CORE" ]] ; then
    _verbose "replace existing BSP link"
    ln -sf "$LOCAL_BSP_CORE" "$OLD_BSP_CORE"
else
    _verbose "link BSP core"
    ln -s "$LOCAL_BSP_CORE" "$OLD_BSP_CORE"
fi

# check tools
BSP_CROSS_COMPILE="$(printf "%s" "$BSP_MCCI"/tools/arm-none-eabi-gcc/*)"/bin/arm-none-eabi-
if [[ ! -x "$BSP_CROSS_COMPILE"gcc ]]; then
    echo "Toolchain not found: $BSP_CROSS_COMPILE"
    exit 1
fi

# set up private key
if [[ $OPTTESTSIGN -eq 0 ]]; then
    if [[ ! -r "${OPTKEYFILE}" ]]; then
        echo "Can't find project key file: ${OPTKEYFILE} -- did you do git clone --recursive?"
        exit 1
    fi
    PRIVATE_KEY_LOCKED="$(realpath "${OPTKEYFILE}")"
    PRIVATE_KEY_UNLOCKED_DIR="${OUTPUT}/../key.d"
    if [[ ! -d "${PRIVATE_KEY_UNLOCKED_DIR}" ]]; then
        _verbose make key directory "${PRIVATE_KEY_UNLOCKED_DIR}"
        mkdir "${PRIVATE_KEY_UNLOCKED_DIR}"
    fi
    PRIVATE_KEY_UNLOCKED="$(realpath "${PRIVATE_KEY_UNLOCKED_DIR}"/"$(basename "${PRIVATE_KEY_LOCKED/%.pem/.tmp.pem}")")"
    chmod 700 "${PRIVATE_KEY_UNLOCKED_DIR}"
    _verbose "Unlocking private key:"
    rm -f "${PRIVATE_KEY_UNLOCKED}"                     # remove old
    touch "${PRIVATE_KEY_UNLOCKED}"                     # create new
    chmod 600 "${PRIVATE_KEY_UNLOCKED}"                 # fix permissions
    cat "$PRIVATE_KEY_LOCKED" >"$PRIVATE_KEY_UNLOCKED"  # copy encrypted key (preserving permissions)
    ssh-keygen -p -N '' -f "$PRIVATE_KEY_UNLOCKED"      # decrypt key (ssh-keygen is careful with permissions)

    # set up Arduino IDE to use the key
    printf "%s\n" mccibootloader_keys.path="$(dirname "$PRIVATE_KEY_UNLOCKED")" mccibootloader_keys.test="$(basename "$PRIVATE_KEY_UNLOCKED")" > "$LOCAL_BSP_CORE"/platform.local.txt

    # set input key path for signing bootloader
    KEYFILE="${PRIVATE_KEY_UNLOCKED}"
else
    _verbose "** using test key **"
    rm -rf "$LOCAL_BSP_CORE"/platform.local.txt

    # set input key pay for signing bootloader
    KEYFILE="$(realpath extra/bootloader/tools/mccibootloader_image/test/mcci-test.pem)"
fi

# remove previous build artifacts
_verbose "Remove previous build artifacts"
rm -f "$OUTPUT"/*.hex "$OUTPUT"/*.bin "$OUTPUT"/*.dfu "$OUTPUT"/*.elf

# do a build
_verbose arduino-cli compile $ARDUINO_CLI_FLAGS \
    -b "${ARDUINO_FQBN}":"${ARDUINO_OPTIONS//[[:space:]]/,}" \
    --build-path "$OUTPUT" \
    --libraries libraries \
    "${ARDUINO_SOURCE}"

arduino-cli compile $ARDUINO_CLI_FLAGS \
    -b "${ARDUINO_FQBN}":"${ARDUINO_OPTIONS//[[:space:]]/,}" \
    --build-path "$OUTPUT" \
    --libraries libraries \
    "${ARDUINO_SOURCE}"

# build & sign the bootloader
_verbose "Building mccibootloader_image"

if [[ $OPTCLEAN -ne 0 ]]; then
    make -C extra/bootloader/tools/mccibootloader_image clean
fi
make -C extra/bootloader/tools/mccibootloader_image all

_verbose "Building and signing bootloader"
MCCIBOOTLOADER_IMAGE_FLAGS_ARG=
if [[ $OPTVERBOSE -ne 0 ]]; then
    MCCIBOOTLOADER_IMAGE_FLAGS_ARG="MCCIBOOTLOADER_IMAGE_FLAGS=-v"
fi
if [[ $OPTCLEAN -ne 0 ]]; then
    CROSS_COMPILE="${BSP_CROSS_COMPILE}" make -C extra/bootloader clean T_BUILDTREE="$OUTPUT_BOOTLOADER" MCCI_BOOTLOADER_KEYFILE="$KEYFILE" ${MCCIBOOTLOADER_IMAGE_FLAGS_ARG}
fi
CROSS_COMPILE="${BSP_CROSS_COMPILE}" make -C extra/bootloader all T_BUILDTREE="$OUTPUT_BOOTLOADER" MCCI_BOOTLOADER_KEYFILE="$KEYFILE" ${MCCIBOOTLOADER_IMAGE_FLAGS_ARG}

# copy bootloader images to output dir
_verbose "Save bootloader"
cp -p "$OUTPUT_BOOTLOADER"/arm-none-eabi/release/${BOOTLOADER_NAME}.* "$OUTPUT"

# combine hex images to simplify download
_verbose "Combine bootloader and app"

# all lines but the last, then append the main app
ARDUINO_SOURCE_BASE="$(basename ${ARDUINO_SOURCE} .ino)"
head -n-1 "$OUTPUT"/${BOOTLOADER_NAME}.hex | cat - "$OUTPUT"/"${ARDUINO_SOURCE_BASE}".ino.hex > "$OUTPUT"/"${ARDUINO_SOURCE_BASE}"-bootloader.hex

# make a packed DFU variant
_verbose "Make a packed DFU variant"
pip3 --disable-pip-version-check -q install IntelHex
python3 extra/dfu-util/dfuse-pack.py -i "$OUTPUT"/${BOOTLOADER_NAME}.hex -i "$OUTPUT"/"${ARDUINO_SOURCE_BASE}".ino.hex -D 0x040e:0x00a1 "$OUTPUT"/"${ARDUINO_SOURCE_BASE}"-bootloader.dfu

# rename everything
_verbose "Rename output files to include build signature"
for ext in hex dfu elf bin; do
    for file in "$OUTPUT"/*."${ext}" ; do
        newfile="$OUTPUT"/$(basename "$file" ".${ext}")-${OUTPUT_SIG}.${ext}
        _debug "rename $(basename "$file") => $(basename "$newfile")"
        mv -f "$file" "$newfile"
    done
done

# all done
_verbose "done"
exit 0
