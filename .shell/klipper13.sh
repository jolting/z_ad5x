#!/bin/sh
# (C) 2024-2026 ghzserg https://github.com/ghzserg/zmod

. /usr/data/zmod/zmod/.shell/0.sh

if [ ${C5PRO} -eq 1 ] ||[ ${AD5X} -eq 1 ]; then
    /usr/data/zmod/zmod/.shell/fix_config.sh start

    if [ ${AD5X} -eq 1 ]; then
        # Reset UART4 termios (115200 8N1 raw) before Klipper opens the port
        stty -F /dev/ttyS4 115200 raw -echo -parenb 2>/dev/null || true

        # Initialize and pulse IFS MCU reset (GPIO 34, active low NRST)
        if [ ! -d /sys/class/gpio/gpio34 ]; then
            echo 34 > /sys/class/gpio/export 2>/dev/null || true
        fi
        if [ -d /sys/class/gpio/gpio34 ]; then
            echo out > /sys/class/gpio/gpio34/direction 2>/dev/null || true
            echo 0 > /sys/class/gpio/gpio34/value 2>/dev/null || true
            usleep 200000
            echo 1 > /sys/class/gpio/gpio34/value 2>/dev/null || true
        fi

        # Ensure mainboard BOOT0 (GPIO 50) is 0 so it runs application instead of bootloader
        if [ ! -d /sys/class/gpio/gpio50 ]; then
            echo 50 > /sys/class/gpio/export 2>/dev/null || true
        fi
        if [ -d /sys/class/gpio/gpio50 ]; then
            echo out > /sys/class/gpio/gpio50/direction 2>/dev/null || true
            echo 0 > /sys/class/gpio/gpio50/value 2>/dev/null || true
        fi
    fi

    find /usr/prog/PROGRAM/control/ -name NationsCommand| while read a; do $a -r ; done;

    if [ ${AD5X} -eq 1 ]; then
        # Allow IFS factory bootloader (~1.2s timeout) to exit to application
        sleep 2
    fi

    export PATH=$PATH:/usr/prog/Python-3.8.2/bin
    export LD_LIBRARY_PATH=/usr/prog/Python-3.8.2/lib:$LD_LIBRARY_PATH
    export LD_LIBRARY_PATH=/usr/prog/openssl-1.0.2d/lib:$LD_LIBRARY_PATH
    export LD_LIBRARY_PATH=/usr/prog/libffi-3.4.4/lib:$LD_LIBRARY_PATH

    PYTHON=/usr/prog/Python-3.8.2/bin/python3
    KLIPPER=/usr/data/zmod/klipper/klippy/klippy.py
    KLIPPER_CONF=/usr/data/config/printer.cfg
    KLIPPER_LOG=/usr/data/logs/printer.log
    PID_FILE=/run/klipper.pid
    KLIPPER_UDS=/tmp/uds
    mkdir -p $(dirname $KLIPPER_LOG) # make sure the log directory exists
    start-stop-daemon -S -b -m -p $PID_FILE --exec $PYTHON -- $KLIPPER $KLIPPER_CONF -l $KLIPPER_LOG -a $KLIPPER_UDS
fi
if [ ${AD5M} -eq 1 ]; then
    find /opt/PROGRAM/control/ -name NationsCommand| while read a; do $a -r ; done;
fi

exit 0
