# Common build script for Arduino-cli projects

## Input from calling script

- `OPTKEYFILE_DEFAULT` is the absolute path to the key file to be used to sign the built image. If not specified, only `--test` builds are possible.

- `OPTLORAWAN_NETWORK_DEFAULT` is the target network for this compile. If not specified, `ttn` is assumed as the default.

- `OPTLORAWAN_REGION_DEFAULT` is the target region for this compile. If not specified, `us915` is assumed as the default.

- `OPTLORAWAN_SUBBAND_DEFAULT` is the target frequency sub-band for this compile. If not specified, `default` is assumed as the default.

- `OPTARDUINO_SOURCE_DEFAULT` is the default target sketch.

- `OPTARDUINO_FQBN_DEFAULT` is the default target board. At present, this must be an MCCI STM32 board. The script chooses `McciBootloader_4801.*` or `McciBootloader_46xx.*` based on the board.

## Input from target sketch

