#!/bin/sh
# (C) 2024-2026 ghzserg https://github.com/ghzserg/zmod

source /usr/data/zmod/zmod/.shell/0.sh

if [ -f /ZMOD ]; then
    /usr/data/zmod/zmod/.shell/zremote.sh /usr/data/zmod/zmod/.shell/restart_klipper.sh
    exit
fi

unset LD_LIBRARY_PATH
unset LD_PRELOAD
export PATH="$PATH:/opt/bin:/opt/sbin"

# This script will restart Klipper on FlashForge Adventurer 5M(Pro)
# like original QT factory application does it.

# This script needs working GDB for operation.

# Copyright (c) 2024, Dark Simpson

pid=$(ps | grep [f]irmwareExe | awk '{print $1}')

if [ -n "$pid" ] && [ "$pid" -gt 0 ] 2>/dev/null && which gdb >/dev/null 2>&1; then

    echo Screen executable PID is $pid, calling GDB to perform manipulations...

    exec gdb -q <<EOF
# All black magic is done in this GDB script.
# Do not modify anything if you don't understand it!!!

# Do not load all symbold from shared libraries, we do not need them all
set auto-solib-add off

# Attach to our process to perform manipulations
attach $pid

# Check that we have instanse of MainWindow
if (_ZN10MainWindow14instMainWindowE != 0)
  # Open Settings screen
  call _ZN10MainWindow19on_settings_clickedEv(_ZN10MainWindow14instMainWindowE)

  # Call saveCfg(), it will also perform Klipper restart (will do it in some seconds)
  if (_ZN8Settings12instSettingsE != 0)
    call _ZN8Settings7saveCfgEv(_ZN8Settings12instSettingsE)
  end

  # Open Home screen afterall
  call _ZN10MainWindow15on_home_clickedEv(_ZN10MainWindow14instMainWindowE)
end

# Detach from our process, leave it run freely
detach

# Quit debugger
quit
EOF

else
    echo "firmwareExe not running, restarting Klipper directly..."
    start-stop-daemon -K -p /run/klipper.pid 2>/dev/null || true
    rm -f /run/klipper.pid /var/run/klipper.pid
    for pid in $(pgrep -f "klippy\.py" 2>/dev/null); do
        kill -9 "$pid" 2>/dev/null || true
    done
    sleep 1
    if [ -x /usr/data/zmod/zmod/.shell/klipper13.sh ]; then
        /usr/data/zmod/zmod/.shell/klipper13.sh &
    elif [ -x /usr/prog/klipper/start.sh ]; then
        /usr/prog/klipper/start.sh &
    fi
fi
