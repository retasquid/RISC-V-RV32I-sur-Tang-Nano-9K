#include "transfert.h"
#include <Wire.h>

#define GET_ID 0x30
#define GET_PAGE 0x31
#define SET_PAGE 0x32
#define SET_ADDR 0x33
#define SEC_ERASE 0x34
#define SEC_ERASE_4k 0x35

uint8_t data_buf[256];
uint32_t pageAddr = WRITE_ADDRESS;

uint8_t decodeCmd() {
  while (Serial.available() == 0) {}
  return Serial.read();
}

void getCmdData(uint8_t *data, uint16_t len) {
  if (len <= 256) {
    Serial.write(0x06);  //send ACK
  } else {
    Serial.write(0x15);  //send NAK
  }
  uint16_t i = 0;
  while (i < len) {
    if (Serial.available()) {
      data[i] = Serial.read();
      i++;
    }
  }
}

void sendCmdData(uint8_t *data, uint16_t len) {
  if (len <= 256) {
    Serial.write(0x06);  //send ACK
  } else {
    Serial.write(0x15);  //send NAK
  }
  uint16_t i = 0;
  while (i < len) {
    Serial.write(data[i]);
    i++;
  }
}

void getId(uint8_t *id) {
  readID(id);
  id[2] = 1 << (id[2] - 17);  //Convert in Mbits
  sendCmdData(id, 3);
}

void setAddr(uint8_t *addr) {
  getCmdData(addr, 4);
  pageAddr = (((uint32_t)addr[0] << 24) | ((uint32_t)addr[1] << 16) | ((uint32_t)addr[2] << 8) | (uint32_t)addr[3]);
  pageAddr &= 0xFFFFFF00;
}

void secErase() {
  sectorErase(pageAddr);
  sendCmdData(nullptr, 0);
}

void secErase4k() {
  sectorErase4k(pageAddr);
  sendCmdData(nullptr, 0);
}

void getPage(uint8_t *buffer) {
  EEPROMread(pageAddr, buffer, 256);
  sendCmdData(buffer, 256);
}

void setPage(uint8_t *buffer) {
  getCmdData(buffer, 256);
  EEPROMwrite(pageAddr, buffer, 256);
}

void execCmd() {
  uint8_t cmd = decodeCmd();
  switch (cmd) {
    case GET_ID:
      getId(data_buf);
      break;
    case GET_PAGE:
      getPage(data_buf);
      break;
    case SET_PAGE:
      setPage(data_buf);
      break;
    case SET_ADDR:
      setAddr(data_buf);
      break;
    case SEC_ERASE:
      secErase();
      break;
    case SEC_ERASE_4k:
      secErase4k();
      break;
    default:
      Serial.write(0x15);  //send NAK, no commande
      break;
  }
}