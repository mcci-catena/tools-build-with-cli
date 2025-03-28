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

# exit if any errors encountered
set -e

INVOKEDIR=$(realpath .)
readonly INVOKEDIR

# we only want tthe first word.
# shellcheck disable=SC2128
SCRIPTPATH="$(realpath "$BASH_SOURCE")"
SCRIPTNAME=$(basename "$SCRIPTPATH")
readonly SCRIPTNAME

[[ -z "$PNAME" ]] && PNAME="$SCRIPTNAME"

PDIR=$(realpath "$(dirname "$SCRIPTPATH")/../..")
readonly PDIR

function _setDefaults {
    declare -g -i OPTDEBUG=0
    declare -g -i OPTVERBOSE=0

    declare -g -A OPTCLOCK_LIST
    OPTCLOCK_LIST=([2]=msi2097k [4]=msi4194k [16]=hsi16m [24]=pll24m [32]=pll32m)
    readonly OPTCLOCK_LIST

    declare -g -A OPTXSERIAL_LIST
    OPTXSERIAL_LIST=([usb]=usb [hw]=generic [none]=none [both]=usbhwserial [two]=two)
    readonly OPTXSERIAL_LIST

    declare -g -A MCCI_ARDUINO_BOARD_LIST
    MCCI_ARDUINO_BOARD_LIST=(
        [4610]=mcci:stm32:mcci_catena_4610
        [4612]=mcci:stm32:mcci_catena_4612
        [4618]=mcci:stm32:mcci_catena_4618
        [4630]=mcci:stm32:mcci_catena_4630
        [4801]=mcci:stm32:mcci_catena_4801
        [4802]=mcci:stm32:mcci_catena_4802
        )
    readonly MCCI_ARDUINO_BOARD_LIST

    declare -g -A MCCI_ARDUINO_BOOTLOADER_LIST
    MCCI_ARDUINO_BOOTLOADER_LIST=(
        [4610]=46xx
        [4612]=46xx
        [4618]=46xx
        [4630]=46xx
        [4801]=4801
        [4802]=4801
    )
    readonly MCCI_ARDUINO_BOOTLOADER_LIST
}

##############################################################################
# Override this function with one of your own
##############################################################################
function _setProject {
    _fatal "You must provide your own _setProject function"
}

##############################################################################
# Check that project settings are complete
##############################################################################
function _checkProject {
    #---- project settings -----
    [[ -n "$OPTKEYFILE_DEFAULT" ]]          || _fatal "OPTKEYFILE_DEFAULT must be set to a suitable default keyfile location (.pem)"
    [[ -n "$OPTREGION_DEFAULT" ]]           || _fatal "OPTREGION_DEFAULT must be set to a value from MCCI_ARDUINO_BOOTLOADER_LIST"
    [[ -n "$OPTNETWORK_DEFAULT" ]]          || _fatal "OPTNETWORK_DEFAULT must be set to a target network"
    [[ -n "$OPTSUBBAND_DEFAULT" ]]          || _fatal "OPTSUBBAND_DEFAULT must be set"
    [[ -n "$OPTCLOCK_DEFAULT" ]]            || _fatal "OPTCLOCK_DEFAULT must be set"
    [[ -n "$OPTXSERIAL_DEFAULT" ]]          || _fatal "OPTXSERIAL_DEFAULT must be set"
    [[ -n "$OPTARDUINO_BOARD_DEFAULT" ]]    || _fatal "OPTARDUINO_BOARD_DEFAULT must be set"
    [[ -n "$OPTARDUINO_SOURCE_DEFAULT" ]]   || _fatal "OPTARDUINO_SOURCE_DEFAULT must be set"
    [[ -n "$OPTOUTPUTNAME_DEFAULT" ]]       || _fatal "OPTOUTPUTNAME_DEFAULT must be set"
    true
}

##############################################################################
# verbose output
##############################################################################

function _verbose {
	if [[ "$OPTVERBOSE" -ne 0 ]]; then
		echo "$PNAME:" "$@" 1>&2
	fi
}

##############################################################################
# debug output
##############################################################################

function _debug {
	if [[ "$OPTDEBUG" -ne 0 ]]; then
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
	_error "fatal error:" "$@" ; exit 1
}

##############################################################################
# help
##############################################################################

function _help {
    # shellcheck disable=SC2086
    less <<.
${PNAME} calls ${SCRIPTNAME} in order to build the target
firmware $(basename "${OPTARDUINO_SOURCE_DEFAULT}") using the arduino-cli tool.

All the work is in the script ${SCRIPTNAME}, which is invoked from a
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

    --sketch={file} gives the path to the sketch to be built.

    --outputname={name} gives the base pattern for the output name. The
        default is ${OPTOUTPUTNAME_DEFAULT}, unless --sketch is given, in
        which case the default is the name of the sketch.

    --debug turns on more debug output.

    --help prints this message.
.
}

##############################################################################
# extract version from file passed as $1.
##############################################################################

# $1 is the name of the script
# result is version as either x.y.z-N or x.y.z (if pre-release tag is -0)
if [[ "$(type -t _getversion)" != function ]]; then
    _verbose "Using default _getversion"
    function _getversion {
        sed -n -e '/^constexpr std::uint32_t kAppVersion /s/^.*makeVersion[ \t]*([ \t]*\([0-9]*\)[ \t]*,[ \t]*\([0-9]*\)[ \t]*,[ \t]*\([0-9]*\)[ \t]*,[ \t]*\([0-9]*\)[ \t]*).*/\1.\2.\3_pre\4/p' \
            -e '/^constexpr std::uint32_t kAppVersion /s/^.*makeVersion[ \t]*([ \t]*\([0-9]*\)[ \t]*,[ \t]*\([0-9]*\)[ \t]*,[ \t]*\([0-9]*\)[ \t]*).*/\1.\2.\3/p' "$1" |
            sed -e 's/_pre0$//'
    }
fi

##############################################################################
# scan options
##############################################################################

function _parseOptions {
    declare -g -i OPTTESTSIGN=0
    #typeset -i OPTVERBOSE=0    -- during init
    #typeset -i OPTDEBUG=0
    declare -g -i OPTCLEAN=0
    declare -g -i OPTSKETCH=0

    OPTKEYFILE="${OPTKEYFILE_DEFAULT}"
    OPTREGION="${OPTREGION_DEFAULT}"
    OPTNETWORK="${OPTNETWORK_DEFAULT}"
    OPTSUBBAND="${OPTSUBBAND_DEFAULT}"
    OPTXSERIAL="${OPTXSERIAL_DEFAULT}"
    OPTCLOCK="${OPTCLOCK_DEFAULT}"
    OPTARDUINO_SOURCE="${OPTARDUINO_SOURCE_DEFAULT}"
    OPTARDUINO_BOARD="${OPTARDUINO_BOARD_DEFAULT}"
    OPTOUTPUTNAME=

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
        "--sketch="* )
            OPTARDUINO_SOURCE="${opt#--sketch=}"
            OPTSKETCH=1
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
}

##############################################################################
# Set up the FQBN
##############################################################################
function _setfqbn {
    _debug "Set up FTQBN and bootloader"
    [[ -z "$OPTARDUINO_BOARD" ]] && _fatal "Arduino board must not be null"
    ARDUINO_FQBN="${MCCI_ARDUINO_BOARD_LIST[$OPTARDUINO_BOARD]}"
    [[ -z "$ARDUINO_FQBN" ]] && _fatal "Arduino board not recognized: $OPTARDUINO_BOARD"

    readonly BOOTLOADER_NAME=McciBootloader_"${MCCI_ARDUINO_BOOTLOADER_LIST[$OPTARDUINO_BOARD]}"
}

##############################################################################
# Compute the arduino sketch to be built
##############################################################################
function _findsrc {
    _debug "Find the source sketch"
    [[ -r "$OPTARDUINO_SOURCE" ]] || _fatal "Can't find sketch:" "$OPTARDUINO_SOURCE"

    ARDUINO_SOURCE="$(realpath "$OPTARDUINO_SOURCE")"
    _debug "Building: $ARDUINO_SOURCE"
}

##############################################################################
# Check arguments
##############################################################################
function _checkargs {
    _debug "Check arguments"
    [[ -z "$OPTREGION" ]] && _fatal "region must not be empty"
    [[ -z "$OPTNETWORK" ]] && _fatal "network must not be empty"
    [[ -z "$OPTSUBBAND" ]] && _fatal "subband must not be empty"
    [[ -z "${OPTXSERIAL_LIST[${OPTXSERIAL}]}" ]] && _fatal "--serial=$OPTXSERIAL not in ${!OPTXSERIAL_LIST[*]}"
    [[ -z "${OPTCLOCK_LIST[${OPTCLOCK}]}" ]] && _fatal "--clock=$OPTCLOCK not in ${!OPTCLOCK_LIST[*]}"
    _setfqbn
}

##############################################################################
# Compute the arduino platform options to be used.
##############################################################################
function _setarduinooptions {
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
}

##############################################################################
# fetch sketch version to variable
##############################################################################
function _setSketchVersion {
    SKETCHVERSION=$(_getversion "$ARDUINO_SOURCE")
    readonly SKETCHVERSION
    [[ -z "$SKETCHVERSION" ]] && _fatal "Version not found in $ARDUINO_SOURCE"

    _verbose "Building sketch $(basename "$ARDUINO_SOURCE"): version $SKETCHVERSION"
}

##############################################################################
# Get signing info
##############################################################################

function _setBuildKeySig {
    if [[ $OPTTESTSIGN -eq 0 ]]; then
        BUILDKEYSIG="$(basename "${OPTKEYFILE}" .pem | tr ' \t-' _)"
    else
        BUILDKEYSIG=mcci_test
    fi
}

##############################################################################
# Deal wtih BSP and output paths
##############################################################################

function _makeOutputDir {
    if [[ ! -d "$INVOKEDIR"/build ]]; then
        _verbose "No build dir in $INVOKEDIR: create it"
        mkdir "$INVOKEDIR"/build
    fi
}

function _setBspVars {
    BSP_MCCI=$HOME/.arduino15/packages/mcci
    BSP_CORE=$BSP_MCCI/hardware/stm32/
    LOCAL_BSP_CORE="$(realpath extra/Arduino_Core_STM32)"

    # set up links to IDE
    if [[ ! -d "$BSP_CORE" ]]; then
        _fatal "Not installed: $BSP_CORE"
    fi
}

function _setupOutput {
    OUTPUT_SIG="v${SKETCHVERSION}-${OPTNETWORK}-${OPTREGION}-${OPTSUBBAND}-clk${OPTCLOCK}-ser${OPTXSERIAL}-${BUILDKEYSIG}"
    if [[ -n "$OPTOUTPUTNAME" ]]; then
        OUTPUT_SLUG="${OPTOUTPUTNAME}-${OUTPUT_SIG}"
    elif [[ $OPTSKETCH -ne 0 ]]; then
        OUTPUT_SLUG="$(basename "$ARDUINO_SOURCE")-${OUTPUT_SIG}"
    else
        OUTPUT_SLUG="${OPTOUTPUTNAME_DEFAULT}-${OUTPUT_SIG}"
    fi
    [[ -n "$OUTPUT_SLUG" ]] || _fatal "Internal error: empty OUTPUT_SLUG"
    OUTPUT_ROOT="$(realpath "$INVOKEDIR/build")/$OUTPUT_SLUG"
    _verbose "output tree:" "$OUTPUT_ROOT"
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
}

function _checkPreconditions {
    _verbose "Check preconditions"
    if [[ -d ~/Arduino/libraries ]]; then
        printf "%s\n" "Error: you have a ~/Arduino/libraries directory." \
                    "Please remove or hide it to use this script."
        exit 1
    fi

    which arduino-cli > /dev/null || _fatal "please install arduino-cli"
}

function _cleanup_trap {
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

function _errcleanup_trap {
    _verbose "Build error: remove output files"
    rm -f "$OUTPUT"/*.elf "$OUTPUT"/*.bin "$OUTPUT"/*.hex "$OUTPUT"/*.dfu
}

# set up BSP
function _setupBsp {
    _verbose "setup BSP for build"
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
}

# set up private key
function _setupPrivateKey {
    _verbose "Process private key instructions"
    if [[ $OPTTESTSIGN -eq 0 ]]; then
        if [[ ! -r "${OPTKEYFILE}" ]]; then
            _fatal "Can't find project key file: ${OPTKEYFILE} -- did you do git clone --recursive?"
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
}

# remove previous build artifacts
function _removeOldBuilds {
    _verbose "Remove previous build artifacts"
    rm -f "$OUTPUT"/*.hex "$OUTPUT"/*.bin "$OUTPUT"/*.dfu "$OUTPUT"/*.elf
}

# do a build
function _buildSketchWithCli {
    # shellcheck disable=SC2086
    _verbose arduino-cli compile $ARDUINO_CLI_FLAGS \
        -b "${ARDUINO_FQBN}":"${ARDUINO_OPTIONS//[[:space:]]/,}" \
        --build-path "$OUTPUT" \
        --libraries libraries \
        "${ARDUINO_SOURCE}"

    # shellcheck disable=SC2086
    arduino-cli compile $ARDUINO_CLI_FLAGS \
        -b "${ARDUINO_FQBN}":"${ARDUINO_OPTIONS//[[:space:]]/,}" \
        --build-path "$OUTPUT" \
        --libraries libraries \
        "${ARDUINO_SOURCE}"
}

# build & sign the bootloader
function _buildBootloader {
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
    cp -p "$OUTPUT_BOOTLOADER"/arm-none-eabi/release/"${BOOTLOADER_NAME}".* "$OUTPUT"
}

# combine hex images to simplify download
function _combineImages {
    _verbose "Combine bootloader and app"

    # all lines but the last, then append the main app
    ARDUINO_SOURCE_BASE="$(basename "${ARDUINO_SOURCE}" .ino)"
    head -n-1 "$OUTPUT"/"${BOOTLOADER_NAME}".hex | cat - "$OUTPUT"/"${ARDUINO_SOURCE_BASE}".ino.hex > "$OUTPUT"/"${ARDUINO_SOURCE_BASE}"-bootloader.hex

    # make a packed DFU variant
    _verbose "Make a packed DFU variant"
    python3 -m pip --disable-pip-version-check -q install IntelHex
    python3 extra/dfu-util/dfuse-pack.py -i "$OUTPUT"/"${BOOTLOADER_NAME}".hex -i "$OUTPUT"/"${ARDUINO_SOURCE_BASE}".ino.hex -D 0x040e:0x00a1 "$OUTPUT"/"${ARDUINO_SOURCE_BASE}"-bootloader.dfu
}

# rename everything
function _renameResults {
    _verbose "Rename output files to include build signature"
    for ext in hex dfu elf bin; do
        for file in "$OUTPUT"/*."${ext}" ; do
            newfile="$OUTPUT"/$(basename "$file" ".${ext}")-${OUTPUT_SIG}.${ext}
            _debug "rename $(basename "$file") => $(basename "$newfile")"
            mv -f "$file" "$newfile"
        done
    done
}

##############################################################################
# Parse options, then change to directory at the top of the source collection
# This is so we can do all the work up to the change of directory using
# paths relative to the user's input
##############################################################################

function _doBuild {
    _setDefaults
    _checkPreconditions
    _setProject
    _checkProject
    _parseOptions "$@"
    cd "$PDIR"
    _checkargs
    _findsrc
    _setarduinooptions
    _setSketchVersion
    _setBuildKeySig
    _makeOutputDir
    _setBspVars

    trap '_cleanup_trap' EXIT
    trap '_errcleanup_trap' ERR

    _setupBsp
    _setupPrivateKey
    _setupOutput
    _removeOldBuilds
    _buildSketchWithCli
    _buildBootloader
    _combineImages
    _renameResults

    # all done
    _verbose "done"
    return 0
}
