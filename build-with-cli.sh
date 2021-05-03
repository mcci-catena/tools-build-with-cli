#!/bin/bash

# install arduino-cli from github using:
#  curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh

# if Linux, to set up:
#  sudo dpkg --add-architecture i386
#  sudo apt install libc6-i386

# exit if any errors encountered
set -e

BSP_MCCI=$HOME/.arduino15/packages/mcci
BSP_CORE=$BSP_MCCI/hardware/stm32/
LOCAL_BSP_CORE="$(realpath extra/Arduino_Core_STM32)"
OUTPUT_ROOT="$(realpath build)"
OUTPUT="${OUTPUT_ROOT}/ide"
readonly KEYFILE_DEFAULT=keys/project.pem

function _help {
    less <<.
Build this directory using the arduino-cli tool.

Options:
    --clean does a clean prior to building.

    --verbose causes more info to be displayed.

    --test makes this a test-signing build (no use of private key)

    --key={file} gives the path to the public/private key files.
        The default is ${KEYFILE_DEFAULT}. The public file is
        found by changing "*.pem" to "*.pub.pem".

    --help prints this message.
.
}

typeset -i OPTTESTSIGN=0
typeset -i OPTVERBOSE=0
OPTKEYFILE="${KEYFILE_DEFAULT}"

# make sure everything is clean
for opt in "$@"; do
    case "$opt" in
    "--clean" )
        rm -rf "$OUTPUT_ROOT"
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
        OPTKEYFILE="${opt#--key=}"
        ;;
    "--help" )
        _help
        exit 0
        ;;
    *)
        echo "not recognized: $opt -- use '--help' for help."
        exit 1
        ;;
    esac
done

if [[ ! -d "${OUTPUT}" ]]; then
    # the IDE hammers the specified directory; and we need other things here...
    # so make it a subdir of build.
    mkdir -p "${OUTPUT}"
fi

function _verbose {
    if [[ $OPTVERBOSE -ne 0 ]]; then
        echo "$@"
    fi
}

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
    if [[ ! -z "$SAVE_BSP_CORE" ]] && [[ -d "$SAVE_BSP_CORE" ]]; then
        _verbose "restore BSP"
        mv "$SAVE_BSP_CORE" "$BSP_CORE"/"$SAVE_BSP_VER"
    fi
    rm -f "$LOCAL_BSP_CORE"/platform.local.txt
}

trap '_cleanup' EXIT
trap 'rm -f "$OUTPUT"/*.elf "$OUTPUT"/*.bin "$OUTPUT"/*.hex "$OUTPUT"/*.dfu' ERR

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
    PRIVATE_KEY_LOCKED="$(realpath ${OPTKEYFILE})"
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
    printf "%s\n" mccibootloader_keys.path="$(dirname $PRIVATE_KEY_UNLOCKED)" mccibootloader_keys.test="$(basename $PRIVATE_KEY_UNLOCKED)" > "$LOCAL_BSP_CORE"/platform.local.txt

    # set input key path for signing bootloader 
    KEYFILE="${PRIVATE_KEY_UNLOCKED}"
else
    _verbose "** using test key **"
    rm -rf "$LOCAL_BSP_CORE"/platform.local.txt

    # set input key pay for signing bootloader
    KEYFILE="$(realpath extra/bootloader/tools/mccibootloader_image/test/mcci-test.pem)"
fi

# do a build
_verbose "Building sketch"

ARDUINO_OPTIONS="$(echo '
                    upload_method=STLink
                    xserial=generic
                    sysclk=msi2097k
                    opt=osstd
                    lorawan_region=us915
                    lorawan_network=ttn
                    lorawan_subband=sb1
                    ' | xargs echo)"

_verbose arduino-cli compile $ARDUINO_CLI_FLAGS \
    -b mcci:stm32:mcci_catena_4610:"${ARDUINO_OPTIONS//[[:space:]]/,}" \
    --build-path "$OUTPUT" \
    --libraries libraries \
    libraries/mcci-catena-4430/examples/Catena4430_Sensor/Catena4430_Sensor.ino

arduino-cli compile $ARDUINO_CLI_FLAGS \
    -b mcci:stm32:mcci_catena_4610:"${ARDUINO_OPTIONS//[[:space:]]/,}" \
    --build-path "$OUTPUT" \
    --libraries libraries \
    libraries/mcci-catena-4430/examples/Catena4430_Sensor/Catena4430_Sensor.ino

# build & sign the bootloader
_verbose "Building mccibootloader_image"
make -C extra/bootloader/tools/mccibootloader_image clean all
_verbose "Building and signing bootloader"
_FLAGS=
if [[ $OPTVERBOSE -ne 0 ]]; then
    _FLAGS="MCCIBOOTLOADER_IMAGE_FLAGS=-v"
fi
CROSS_COMPILE="${BSP_CROSS_COMPILE}" make -C extra/bootloader clean all MCCI_BOOTLOADER_KEYFILE="$KEYFILE" ${_FLAGS}

# copy bootloader images to output dir
_verbose "Save bootloader"
cp -p extra/bootloader/build/arm-none-eabi/release/McciBootloader_46xx.* "$OUTPUT"

# combine hex images to simplify download
_verbose "Combine bootloader and app"
# all lines but the last, then append the main app
head -n-1 "$OUTPUT"/McciBootloader_46xx.hex | cat - "$OUTPUT"/Catena4430_Sensor.ino.hex > "$OUTPUT"/Catena4430_Sensor-bootloader.hex

# all done
_verbose "done"
exit 0
