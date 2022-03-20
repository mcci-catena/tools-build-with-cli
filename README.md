# Common build script for MCCI product collections

## Input from calling script

### `_setProject`

The calling script must define the function `_setProject` after sourcing the script.

`_setProject` must define the following.

- `OPTOUTPUTNAME_DEFAULT` is the name to be used by default for the prefix of the output directory.

- `OPTKEYFILE_DEFAULT` is the absolute path to the key file to be used to sign the built image. If not specified, only `--test` builds are possible.

- `OPTNETWORK_DEFAULT` is the target network for this compile. If not specified, `ttn` is assumed as the default.

- `OPTREGION_DEFAULT` is the target region for this compile. If not specified, `us915` is assumed as the default.

- `OPTSUBBAND_DEFAULT` is the target frequency sub-band for this compile. If not specified, `default` is assumed as the default.

- `OPTARDUINO_SOURCE_DEFAULT` is the default target sketch.

- `OPTARDUINO_BOARD_DEFAULT` is the default target board. At present, this must be an MCCI STM32 board. The script chooses `McciBootloader_4801.*` or `McciBootloader_46xx.*` based on the board.

### `_getVersion`

This function, if present, takes one argument, which is the path to the input sketch. It must scan the sketch and print the semantic version to standard output.

The default `_getVersion` function looks for the pattern `^constexpr std::uint32_t kAppVersion.*makeVersion(.*)` and extracts the 3- or 4-argument serial number from the parameters.

## Meta

### Release History

- v2.0.0 adds `OPTOUTPUTNAME_DEFAULT` as required input from the caller. It's therefore a breaking change.

- v1.0.0 is the initial release.

### Trademarks and copyright

MCCI and MCCI Catena are registered trademarks of MCCI Corporation. LoRa is a registered trademark of Semtech Corporation. LoRaWAN is a registered trademark of the LoRa Alliance.

This document and the contents of this repository are copyright 2021, MCCI Corporation.

### License

This repository is released under the [MIT](./LICENSE.md) license. Commercial licenses are also available from MCCI Corporation.

### Support Open Source Hardware and Software

MCCI invests time and resources providing this open source code, please support MCCI and open-source hardware by purchasing products from MCCI, Adafruit and other open-source hardware/software vendors!

For information about MCCI's products, please visit [store.mcci.com](https://store.mcci.com/).
