#ifndef MX25L_H
#define MX25L_H

#include "Arduino.h"

// Program counter initial value
#define WRITE_ADDRESS 0x1000
//Microcontroller ROM size in bits
#define ROM_SIZE 262144

// You can use every GPIO, it use bitbanging and not the HW SPI
#define SCLK 13  // Serial Clock
#define CSn 10   // Chip Select
#define SO 12    // Serial Output (MISO)
#define SI 11    // Serial Input (MOSI)

// Instructions for  MX25L3233F
#define WRITE_ENABLE 0x06
#define WRITE_DISABLE 0x04
#define READ_STATUS_REG 0x05
#define READ_STATUS_REG2 0x35
#define WRITE_STATUS_REG 0x01
#define READ_DATA 0x03
#define FAST_READ 0x0B
#define PAGE_PROGRAM 0x02
#define SECTOR_ERASE 0x20     // 4KB
#define BLOCK_ERASE_32K 0x52  // 32KB
#define BLOCK_ERASE 0xD8      // 64KB
#define CHIP_ERASE 0xC7
#define READ_ID 0x9F
#define RESET_ENABLE 0x66
#define RESET_DEVICE 0x99


// Afficher des données en hexadécimal avec formatage amélioré
void printHexData(const uint8_t *data, uint16_t length, uint32_t offset);

// Vérifier que les données lues correspondent aux données écrites
bool verifyData(const uint8_t *expected, const uint8_t *actual, uint16_t length);

// Écriture sur plusieurs pages (gère automatiquement les limites)
void writeMultiplePages(uint32_t address, const uint8_t *data, uint16_t length);

void EEPROMsetup();

void resetDevice();

uint8_t readStatus();

void writeEnable();

void writeDisable();

void writeStatus(uint8_t status);

void readID(uint8_t *id);

void EEPROMread(uint32_t address, uint8_t *buffer, uint16_t length);

void EEPROMwrite(uint32_t address, const uint8_t *buffer, uint16_t length);

// Effacer un secteur (64KB)
void sectorErase(uint32_t address);

// Effacer un secteur (4KB)
void sectorErase4k(uint32_t address);

void sendByte(uint8_t byte);

uint8_t receiveByte();

#endif