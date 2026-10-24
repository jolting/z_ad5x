# Flashforge Adventurer 5X - MCU Firmware Flashing Guide

This document describes how to flash and recover all three microcontrollers (MCUs) on the **Flashforge Adventurer 5X** directly from the Linux host **without rebooting the machine**.

---

## 1. Hardware Architecture & Serial Mappings

| MCU | Target Hardware | Serial Port | Baud Rate | Flashing Tool | Firmware Path | Reset / Boot Control |
|---|---|---|---|---|---|---|
| **Mainboard** | Nations N32G45x | `/dev/ttyS2` | 230400 | `NationsCommand` | `/usr/data/zmod/klipper/mcu/ad5x/Mainboard.bin` (K13)<br>`/usr/prog/PROGRAM/control/1.1.1/AD5X.bin` (Stock) | **BOOT0**: GPIO 50<br>**NRST**: GPIO 49 |
| **IFS Unit** | Nations N32G45x | `/dev/ttyS4` | 115200 (RS-485 TDD) | `IFSCommand` / `ifsF37` | `/usr/data/zmod/klipper/mcu/ifs/klipper_ifs.hex` (Open)<br>`/usr/prog/PROGRAM/control/1.1.1/ifs.hex` (Stock) | **NRST**: GPIO 34 |
| **Toolhead Eboard** | STM32 | `/dev/ttyS5` | 230400 | `IAPCommand` | `/usr/data/zmod/klipper/mcu/ad5x/Eboard.hex` (K13)<br>`/usr/prog/PROGRAM/control/1.1.1/ADM_App.hex` (Stock) | No dedicated host GPIO reset on AD5X (GPIO 34 reassigned to IFS); requires cold boot window at reboot |

---

## 2. Fundamental Rule: Stop Klipper First

Whenever flashing any MCU, **Klipper (`klippy.py`) must be stopped first**.

If Klipper is running while you run a flashing tool (`IAPCommand`, `NationsCommand`, or `IFSCommand`), Klipper continues streaming packets over the shared serial port (`/dev/ttyS2`, `/dev/ttyS4`, or `/dev/ttyS5`), causing:
```text
Can not connect to board, timed-out.
IAPCommand: Can not connect to board.
```
or `NationsCommand: Connect device ...` hanging.

### Stop Klipper (Leaves Moonraker & Display Online)
```bash
start-stop-daemon -K -p /run/klipper.pid 2>/dev/null || true
rm -f /run/klipper.pid /var/run/klipper.pid
for pid in $(pgrep -f "klippy\.py" 2>/dev/null); do
    kill -9 "$pid" 2>/dev/null || true
done
```

---

## 3. Flashing Instructions (No Reboot Required)

### A. Mainboard MCU

#### Flash Klipper 13:
```bash
# 1. Stop Klipper
start-stop-daemon -K -p /run/klipper.pid 2>/dev/null || true
for pid in $(pgrep -f "klippy\.py"); do kill -9 "$pid" 2>/dev/null || true; done

# 2. Flash Klipper 13 binary
/usr/prog/PROGRAM/control/1.1.1/NationsCommand -c -d --fn /usr/data/zmod/klipper/mcu/ad5x/Mainboard.bin --v -r

# 3. CRITICAL: Ensure BOOT0 (GPIO 50) is driven LOW so MCU runs user application
echo 50 > /sys/class/gpio/export 2>/dev/null || true
echo out > /sys/class/gpio/gpio50/direction 2>/dev/null || true
echo 0 > /sys/class/gpio/gpio50/value 2>/dev/null || true

# 4. Pulse NRST (GPIO 49) to ensure clean reset into Klipper
echo 49 > /sys/class/gpio/export 2>/dev/null || true
echo out > /sys/class/gpio/gpio49/direction 2>/dev/null || true
echo 0 > /sys/class/gpio/gpio49/value 2>/dev/null || true
usleep 100000
echo 1 > /sys/class/gpio/gpio49/value 2>/dev/null || true
sleep 1

# 5. Restart Klipper
/usr/data/zmod/zmod/.shell/klipper13.sh &
```

#### Revert Mainboard to Factory Stock Firmware:
```bash
start-stop-daemon -K -p /run/klipper.pid 2>/dev/null || true
for pid in $(pgrep -f "klippy\.py"); do kill -9 "$pid" 2>/dev/null || true; done

/usr/prog/PROGRAM/control/1.1.1/NationsCommand -c -d --fn /usr/prog/PROGRAM/control/1.1.1/AD5X.bin --v -r

echo 50 > /sys/class/gpio/export 2>/dev/null || true
echo out > /sys/class/gpio/gpio50/direction 2>/dev/null || true
echo 0 > /sys/class/gpio/gpio50/value 2>/dev/null || true

/usr/prog/klipper/start.sh &
```

---

### B. IFS (Intelligent Filament System) MCU

#### Automated via `zflash_ifs.sh`:
The updated script detaches itself into the background, stops Klipper safely, flashes the firmware, updates `printer.cfg` and `variables.cfg`, and restarts Klipper automatically:
```bash
# Install Open Klipper IFS Firmware:
/usr/data/zmod/zmod/.shell/zflash_ifs.sh open

# Revert to Stock Flashforge IFS Firmware:
/usr/data/zmod/zmod/.shell/zflash_ifs.sh stock
```

#### Manual Flash Sequence:
```bash
# 1. Stop Klipper
start-stop-daemon -K -p /run/klipper.pid 2>/dev/null || true
for pid in $(pgrep -f "klippy\.py"); do kill -9 "$pid" 2>/dev/null || true; done

# 2. Put IFS into bootloader mode
/usr/prog/PROGRAM/control/1.1.1/ifsF37 /dev/ttyS4
sleep 1

# 3. Flash target hex (klipper_ifs.hex or ifs.hex)
/usr/prog/PROGRAM/control/1.1.1/IFSCommand /usr/data/zmod/klipper/mcu/ifs/klipper_ifs.hex /dev/ttyS4

# 4. Restart Klipper
/usr/data/zmod/zmod/.shell/klipper13.sh &
```

---

### C. Toolhead Eboard MCU

#### The Root Cause: Why `IAPCommand` Fails Online on AD5X
Disassembling the `IAPCommand` binary (`stm32Reboot` at `0x401e48`) reveals hardcoded GPIO 34 toggling:
```mips
addiu $a0, $zero, 0x22    # 0x22 = GPIO 34
jal   gpio_set_value      # Drives GPIO 34 LOW
jal   usleep              # Waits
jal   gpio_set_value      # Drives GPIO 34 HIGH
```
- **On the AD5M:** GPIO 34 was wired directly to the toolhead STM32 MCU reset line.
- **On the AD5X:** Flashforge reassigned GPIO 34 to the **IFS MCU NRST line**.

When `IAPCommand` runs on an AD5X, it pulses reset on the **IFS MCU**, not the toolhead eboard. Because the toolhead STM32 is never reset, it remains running its normal Klipper application, never enters the bootloader window to respond to `0x43` (`'C'`), and `IAPCommand` reports:
```text
Can not connect to board,  timed-out.
IAPCommand: Can not connect to board.
```

#### Why Flashforge / ZMod Require a System Reboot for Eboard Reflashing:
Because Flashforge did not give the AD5X a dedicated host GPIO line to reset the eboard, their updater architecture relies entirely on the cold power-up bootloader window:
1. **Cold Power-On Bootloader Window:** When the printer boots or reboots, the 24V/3.3V power rails initialize simultaneously. The toolhead STM32 MCU boots and waits in its factory IAP bootloader for ~2–3 seconds before launching the application.
2. **Early-Boot Execution:** Early in the Linux boot sequence, `/usr/data/zmod/zmod/.shell/app_startup_mcu.sh` runs before Klipper, Moonraker, or `firmwareExe` ever start.
3. **No Serial Contention:** Because `/dev/ttyS5` is completely untouched by Klipper at early boot, `IAPCommand` catches the toolhead STM32 in its 2-second bootloader window without needing a hardware reset pin.

#### How to Trigger an Eboard Flash via the Early-Boot Flag Method:
```bash
# 1. Create the update flag file in the control directory
touch /usr/prog/PROGRAM/control/1.1.1/Update

# 2. Ensure klipper13 = 1 is set in variables.cfg so it flashes Klipper 13 (or 0 for stock)
grep -q "^klipper13 = 1" /usr/data/config/mod_data/variables.cfg || echo "klipper13 = 1" >> /usr/data/config/mod_data/variables.cfg

# 3. Reboot the printer
reboot
```
During boot, `app_startup_mcu.sh` detects `Update`, invokes `update_mcu.sh`, flashes the eboard in the cold bootloader window, deletes the flag, and boots into Klipper.

> **Important Note:**  
> The factory eboard firmware (`?-20241122_134741-ubuntu`) is fully supported by our patched Klipper 13 host. Due to the dual-compatible `serialhdl.py` and `lis2dw.py` implementations, Klipper 13 works seamlessly with the factory eboard firmware without requiring an eboard reflash.

---

## 4. Boot Behavior & Avoiding Stock Overwrites

### Why Did the Board Flash Back to Stock Previously?
1. The factory startup script `/usr/data/zmod/zmod/.shell/app_startup_mcu.sh` checks for flag files:
   - `/usr/prog/PROGRAM/control/1.1.1/Update`
   - `/usr/prog/PROGRAM/control/1.1.1/UpdateM`
2. If those flag files exist, it executes `run.sh`.
3. If `klipper13 = 0` in `/usr/data/config/mod_data/variables.cfg`, `run.sh` is Flashforge's factory flasher, which automatically overwrites the mainboard and IFS with stock binaries.
4. When `klipper13 = 1` is set in `variables.cfg`, `app_startup_mcu.sh` binds `/usr/data/zmod/zmod/.shell/update_mcu.sh` over `run.sh`, which flashes Klipper 13 binaries instead.

### Verifying `klipper13` Setting:
```bash
grep "klipper13" /usr/data/config/mod_data/variables.cfg
# Ensure: klipper13 = 1
```

### Removing Stale Update Flags (If Triggered Accidentally):
```bash
rm -f /usr/prog/PROGRAM/control/1.1.1/Update /usr/prog/PROGRAM/control/1.1.1/UpdateM
```

