@echo off
setlocal

REM ============================================================
REM RISC-V Build Script
REM Usage:
REM   comp.bat main.c flash
REM   comp.bat main.c rom
REM ============================================================

if "%~1"=="" (
    echo Usage: comp.bat fichier.c [flash^|rom]
    exit /b 1
)

if "%~2"=="" (
    echo Usage: comp.bat fichier.c [flash^|rom]
    exit /b 1
)

set SOURCE=%~1
set TARGET=%~2

echo.
echo ==========================================
echo        RISC-V BUILD
echo ==========================================
echo Source : %SOURCE%
echo Target : %TARGET%
echo.

REM ============================================================
REM Compilation
REM ============================================================

echo [1/3] Compilation...

riscv-none-elf-gcc ^
    -march=rv32im ^
    -mabi=ilp32 ^
    -O2 ^
    -ffreestanding ^
    -nostartfiles ^
    -T link.ld ^
    start.S ^
    periph.h periph.c lib2d.h lib2d.c ^
    %SOURCE% ^
    -Wl,--start-group -lc -lm -lgcc -Wl,--end-group ^
    -specs=nosys.specs ^
    -o main.elf

if errorlevel 1 (
    echo.
    echo *** ERREUR DE COMPILATION ***
    exit /b 1
)

echo Compilation OK.
echo.

REM ============================================================
REM FLASH
REM ============================================================

if /I "%TARGET%"=="flash" goto FLASH

REM ============================================================
REM ROM
REM ============================================================

if /I "%TARGET%"=="rom" goto ROM

echo *** ERREUR : cible inconnue "%TARGET%" ***
echo Utilisez "flash" ou "rom".
exit /b 1


:FLASH

echo [2/3] Generation du fichier HEX...

riscv-none-elf-objcopy -O ihex main.elf main.hex

if errorlevel 1 (
    echo.
    echo *** ERREUR OBJcopy ***
    exit /b 1
)

echo HEX OK.
echo.

echo [3/3] Programmation de la FLASH...

python ./Flasher3.1/PC_flasher/flasher.py main.hex

if errorlevel 1 (
    echo.
    echo *** ERREUR PROGRAMMATION FLASH ***
    exit /b 1
)

echo.
echo ==========================================
echo        FLASH PROGRAMMEE
echo ==========================================
exit /b 0


:ROM

echo [2/3] Generation de la ROM VHDL...

python elf2rom.py main.elf -o ../RISC-V/src/ROM.vhd --format vhd --depth 1024

if errorlevel 1 (
    echo.
    echo *** ERREUR GENERATION ROM ***
    exit /b 1
)

echo ROM VHDL OK.
echo.

echo [3/3] Generation terminee.

echo.
echo ==========================================
echo        ROM VHDL GENEREE
echo ==========================================
echo Fichier :
echo RISC-V/src/ROM.vhd
echo.
exit /b 0