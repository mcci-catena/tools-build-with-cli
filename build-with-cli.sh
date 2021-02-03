#!/bin/bash

# install arduino-cli from github using:
#  curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh

# if Linux, to set up:
#  sudo dpkg --add-architecture i386
#  sudo apt install libc6-i386

# exit if any errors encountered
set -e

OUTPUT=/tmp/build-Catena4430-Sensor

# make sure everything is clean
if [[ "$1" = "--clean" ]]; then
    rm -rf "$OUTPUT"
fi

# do a build
arduino-cli compile \
    -b mcci:stm32:mcci_catena_4610 \
    --build-path "$OUTPUT" \
    --build-property \
xserial=generic,\
sysclk=msi2097k,\
opt=osstd,\
lorawan_region=us915,\
lorawan_network=ttn,\
lorawan_subband=default \
    --libraries libraries \
    libraries/mcci-catena-4430/examples/Catena4430_Sensor/Catena4430_Sensor.ino
