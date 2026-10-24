#!/bin/sh
# (C) 2026 Hunter Laux <hunterlaux@gmail.com>
# Flash / Revert Flashforge IFS MCU firmware
# Usage: zflash_ifs.sh [open|stock]

source /usr/data/zmod/zmod/.shell/0.sh 2>/dev/null

set -x

MODE="${1:-open}"

# If running attached (e.g. from Klipper gcode_shell_command), detach so stopping Klipper doesn't kill this script
if [ "$1" != "_detached" ]; then
    echo "Detaching IFS flash process to background..."
    nohup /bin/sh "$0" "_detached" "$@" >/tmp/zflash_ifs.log 2>&1 &
    exit 0
fi
shift
MODE="${1:-open}"
sleep 1

CONTROL_DIR="${PROGRAM_DIR}control/"
if [ -d "${CONTROL_DIR}" ]; then
    CONTROL_VERSION=$(ls -d ${CONTROL_DIR}[0-9]*/ 2>/dev/null | sort -Vr | head -n 1)
fi
FLASHER_DIR="${CONTROL_VERSION:-${CONTROL_DIR}}"

# Locate flashing tools
IFSCMD=""
IFSF37=""
for dir in "${FLASHER_DIR}" "${CONTROL_DIR}" /usr/prog/PROGRAM/control/ /usr/prog/PROGRAM/control/1.1.1/; do
    [ -x "${dir}IFSCommand" ] && IFSCMD="${dir}IFSCommand"
    [ -x "${dir}ifsF37" ] && IFSF37="${dir}ifsF37"
    [ -n "$IFSCMD" ] && [ -n "$IFSF37" ] && break
done

if [ -z "$IFSCMD" ]; then
    echo "ERROR: IFSCommand tool not found!"
    exit 1
fi

# Locate firmware files
STOCK_HEX=""
for path in "${FLASHER_DIR}ifs.hex" "${CONTROL_DIR}ifs.hex" /usr/prog/PROGRAM/control/ifs.hex /usr/data/zmod/klipper/mcu/ifs/ifs.hex /usr/data/config/ifs.hex; do
    if [ -f "$path" ]; then
        STOCK_HEX="$path"
        break
    fi
done

OPEN_HEX=""
for path in /usr/data/zmod/zmod/Native_firmware/ifs/klipper_ifs.hex /usr/data/zmod/klipper/mcu/ifs/klipper_ifs.hex /usr/data/config/klipper_ifs.hex /usr/data/klipper_ifs.hex /tmp/klipper_ifs.hex; do
    if [ -f "$path" ]; then
        OPEN_HEX="$path"
        break
    fi
done

case "$MODE" in
    stock|revert|original)
        TARGET_HEX="$STOCK_HEX"
        NEW_OPEN_MODE=0
        echo "Reverting IFS to stock firmware: $TARGET_HEX"
        ;;
    open|klipper|install)
        TARGET_HEX="$OPEN_HEX"
        NEW_OPEN_MODE=1
        echo "Installing open Klipper firmware to IFS: $TARGET_HEX"
        ;;
    *)
        echo "Usage: $0 [open|stock]"
        exit 1
        ;;
esac

if [ -z "$TARGET_HEX" ] || [ ! -f "$TARGET_HEX" ]; then
    echo "ERROR: Target firmware file not found ($TARGET_HEX)!"
    exit 1
fi

# Stop Klipper and any process holding /dev/ttyS4 (do not touch Moonraker)
echo "Stopping Klipper..."
start-stop-daemon -K -p /run/klipper.pid 2>/dev/null || true
rm -f /run/klipper.pid /var/run/klipper.pid
for pid in $(pgrep -f "klippy\.py" 2>/dev/null); do
    kill -9 "$pid" 2>/dev/null || true
done
sleep 1

# Put IFS MCU into bootloader mode
echo "Triggering IFS bootloader..."
if [ -n "$IFSF37" ]; then
    $IFSF37 /dev/ttyS4
fi
sleep 1

# Flash firmware
echo "Flashing $TARGET_HEX via $IFSCMD..."
$IFSCMD "$TARGET_HEX" /dev/ttyS4
FLASH_RET=$?

sync

if [ $FLASH_RET -eq 0 ]; then
    echo "IFS firmware flash successful!"
    if [ -f /usr/data/config/mod_data/variables.cfg ]; then
        if grep -q "^ifs_open_mode" /usr/data/config/mod_data/variables.cfg; then
            sed -i "s/^ifs_open_mode = .*/ifs_open_mode = ${NEW_OPEN_MODE}/" /usr/data/config/mod_data/variables.cfg
        else
            echo "ifs_open_mode = ${NEW_OPEN_MODE}" >> /usr/data/config/mod_data/variables.cfg
        fi
    fi
    for ffconf in /usr/prog/config/Adventurer5M.json /opt/config/Adventurer5M.json; do
        if [ -f "$ffconf" ]; then
            if [ ${NEW_OPEN_MODE} -eq 1 ]; then
                sed -i 's/"ffmEnable"[[:space:]]*:[[:space:]]*true/"ffmEnable" : false/' "$ffconf"
            else
                sed -i 's/"ffmEnable"[[:space:]]*:[[:space:]]*false/"ffmEnable" : true/' "$ffconf"
            fi
        fi
    done
    if [ -f /usr/data/config/printer.cfg ]; then
        if [ ${NEW_OPEN_MODE} -eq 1 ]; then
            if grep -q "ifs_klipper.cfg" /usr/data/config/printer.cfg; then
                sed -i 's/^#[[:space:]]*\[include ifs_klipper.cfg\]/[include ifs_klipper.cfg]/' /usr/data/config/printer.cfg
            else
                sed -i '/^\[include .\/mod_data\/user.cfg\]/a \[include ifs_klipper.cfg\]' /usr/data/config/printer.cfg
            fi
        else
            sed -i 's/^\[include ifs_klipper.cfg\]/# [include ifs_klipper.cfg]/' /usr/data/config/printer.cfg
        fi
    fi
else
    echo "ERROR: IFSCommand failed with exit code $FLASH_RET"
fi

# Play completion chime if available
if [ -x /usr/data/zmod/zmod/.shell/root/audio/audio_midi.sh ]; then
    /usr/data/zmod/zmod/.shell/root/audio/audio_midi.sh For_Elise.mid &
fi

sync
sleep 3

# Restart Klipper
rm -f /run/klipper.pid /var/run/klipper.pid
if [ -x /usr/data/zmod/zmod/.shell/restart_klipper.sh ]; then
    /usr/data/zmod/zmod/.shell/restart_klipper.sh
elif [ -x /usr/data/zmod/zmod/.shell/klipper13.sh ]; then
    /usr/data/zmod/zmod/.shell/klipper13.sh &
fi

# Ensure Moonraker remains alive
if ! pgrep -f "moonraker" >/dev/null 2>&1; then
    rm -f /usr/data/.mod/.zmod/var/run/moonraker.pid
    chroot /usr/data/.mod/.zmod /etc/init.d/S65moonraker start 2>/dev/null || true
fi

exit $FLASH_RET

