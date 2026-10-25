#include "MX25L.h"

// Afficher des données en hexadécimal avec formatage amélioré
void printHexData(const uint8_t *data, uint16_t length, uint32_t offset) {
  for (uint32_t i = offset; i < length + offset; i++) {
    if (i % 16 == 0) {
      Serial.print("0x");
      if (i < 0x10) Serial.print("0");
      if (i < 0x100) Serial.print("0");
      Serial.print(i, HEX);
      Serial.print(": ");
    }

    if (data[i] < 0x10) Serial.print("0");
    Serial.print(data[i], HEX);
    Serial.print(" ");

    if ((i + 1) % 16 == 0) {
      Serial.println();
    } else if ((i + 1) % 4 == 0) {
      Serial.print(" ");
    }
  }
  if (length % 16 != 0) Serial.println();
}

// Vérifier que les données lues correspondent aux données écrites
bool verifyData(const uint8_t *expected, const uint8_t *actual, uint16_t length) {
  for (uint16_t i = 0; i < length; i++) {
    if (expected[i] != actual[i]) {
      Serial.print("ERREUR à l'offset ");
      Serial.print(i);
      Serial.print(": attendu 0x");
      if (expected[i] < 0x10) Serial.print("0");
      Serial.print(expected[i], HEX);
      Serial.print(", lu 0x");
      if (actual[i] < 0x10) Serial.print("0");
      Serial.println(actual[i], HEX);
      return false;
    }
  }
  return true;
}

// Écriture sur plusieurs pages (gère automatiquement les limites)
void writeMultiplePages(uint32_t address, const uint8_t *data, uint16_t length) {
  uint16_t bytesWritten = 0;

  Serial.println("Début écriture multi-pages:");

  while (bytesWritten < length) {
    uint32_t currentAddress = address + bytesWritten;
    uint16_t pageOffset = currentAddress & 0xFF;  // Position dans la page courante
    uint16_t bytesInPage = 256 - pageOffset;      // Octets restants dans la page
    uint16_t bytesToWrite = (bytesInPage < (length - bytesWritten)) ? bytesInPage : (length - bytesWritten);
    Serial.print("  Écriture page: ");
    Serial.print(bytesToWrite);
    Serial.print(" octets à 0x");
    Serial.print(currentAddress, HEX);

    EEPROMwrite(currentAddress, data + bytesWritten, bytesToWrite);

    Serial.println(" - OK");
    bytesWritten += bytesToWrite;
  }
  Serial.print("Total écrit: ");
  Serial.print(bytesWritten);
  Serial.println(" octets");
}

void EEPROMsetup() {
  Serial.println("Initialisation de l'EEPROM MX25L...");

  // Reset de la puce pour s'assurer qu'elle est dans un état connu
  resetDevice();

  // Vérifier que la puce est prête
  uint8_t status = readStatus();

  // Interpréter le statut
  if (status & 0x01) Serial.println("  - Opération en cours (BUSY)");
  if (status & 0x02) Serial.println("  - Écriture activée (WEL)");
  if (status & 0x3C) Serial.println("  - Protection active");

  // Si nécessaire, déverrouiller la protection en écriture
  if (status & 0x3C) {
    Serial.println("Désactivation de la protection...");
    writeEnable();
    writeStatus(0x00);
    Serial.println("Protection désactivée");
  }
}

void resetDevice() {
  digitalWrite(CSn, LOW);
  sendByte(RESET_ENABLE);
  digitalWrite(CSn, HIGH);
  delayMicroseconds(10);

  digitalWrite(CSn, LOW);
  sendByte(RESET_DEVICE);
  digitalWrite(CSn, HIGH);

  delay(30);  // Attendre que le reset soit terminé
  Serial.println("Reset terminé");
}

uint8_t readStatus() {
  uint8_t status;

  digitalWrite(CSn, LOW);
  sendByte(READ_STATUS_REG);
  status = receiveByte();
  digitalWrite(CSn, HIGH);

  return status;
}

void writeEnable() {
  digitalWrite(CSn, LOW);
  sendByte(WRITE_ENABLE);
  digitalWrite(CSn, HIGH);
  // Vérifier que le WEL bit est mis à 1
  uint8_t status = readStatus();
  if (!(status & 0x02)) {
    Serial.write(0x15);  //send NAK, no commande
    Serial.print("ERREUR: Write Enable a échoué : ");
    Serial.println(status);
  }
}

void writeDisable() {
  digitalWrite(CSn, LOW);
  sendByte(WRITE_DISABLE);
  digitalWrite(CSn, HIGH);
}

void writeStatus(uint8_t status) {
  digitalWrite(CSn, LOW);
  sendByte(WRITE_STATUS_REG);
  sendByte(status);
  digitalWrite(CSn, HIGH);

  // Attendre que l'opération soit terminée
  while (readStatus() & 0x01) {
    delay(1);
  }
}

void readID(uint8_t *id) {
  digitalWrite(CSn, LOW);
  sendByte(READ_ID);
  id[0] = receiveByte();  // ID fabricant (0xC2 pour Macronix)
  id[1] = receiveByte();  // Type
  id[2] = receiveByte();  // Capacité (0x16 pour 32Mbit)
  digitalWrite(CSn, HIGH);
}

void EEPROMread(uint32_t address, uint8_t *buffer, uint16_t length) {
  digitalWrite(CSn, LOW);
  sendByte(FAST_READ);
  sendByte((address >> 16) & 0xFF);
  sendByte((address >> 8) & 0xFF);
  sendByte(address & 0xFF);
  sendByte(0xFF);
  for (uint16_t i = 0; i < length; i++) {
    buffer[i] = receiveByte();
  }
  digitalWrite(CSn, HIGH);
}

void EEPROMwrite(uint32_t address, const uint8_t *buffer, uint16_t length) {
  // Vérifier si l'adresse + longueur dépasse une page
  if ((address & 0xFF) + length > 256) {
    Serial.println("ERREUR: L'écriture traverse une limite de page");
    return;
  }

  writeEnable();

  digitalWrite(CSn, LOW);
  sendByte(PAGE_PROGRAM);
  sendByte((address >> 16) & 0xFF);  // MSB
  sendByte((address >> 8) & 0xFF);   // Milieu
  sendByte(address & 0xFF);          // LSB

  for (uint16_t i = 0; i < length; i++) {
    sendByte(buffer[i]);
  }

  digitalWrite(CSn, HIGH);

  // Attendre que l'opération d'écriture soit terminée
  while (readStatus() & 0x01) {
    delay(1);
  }

  writeDisable();
}

// Effacer un secteur (64KB)
void sectorErase(uint32_t address) {
  writeEnable();

  digitalWrite(CSn, LOW);
  sendByte(BLOCK_ERASE);
  sendByte((address >> 16) & 0xFF);  // MSB
  sendByte((address >> 8) & 0xFF);   // Milieu
  sendByte(address & 0xFF);          // LSB
  digitalWrite(CSn, HIGH);

  // Attendre que l'opération d'effacement soit terminée
  while (readStatus() & 0x01) {
    delay(100);
  }
  writeDisable();
}

// Effacer un secteur (4KB)
void sectorErase4k(uint32_t address) {
  writeEnable();

  digitalWrite(CSn, LOW);
  sendByte(SECTOR_ERASE);
  sendByte((address >> 16) & 0xFF);  // MSB
  sendByte((address >> 8) & 0xFF);   // Milieu
  sendByte(address & 0xFF);          // LSB
  digitalWrite(CSn, HIGH);

  // Attendre que l'opération d'effacement soit terminée
  while (readStatus() & 0x01) {
    delay(100);
  }
  writeDisable();
}

void sendByte(uint8_t byte) {
  for (int i = 7; i >= 0; i--) {
    digitalWrite(SI, (byte >> i) & 0x01);
    digitalWrite(SCLK, HIGH);
    digitalWrite(SCLK, LOW);
  }
}

uint8_t receiveByte() {
  uint8_t byte = 0;

  for (int i = 7; i >= 0; i--) {
    digitalWrite(SCLK, HIGH);
    byte |= (digitalRead(SO) << i);
    digitalWrite(SCLK, LOW);
  }

  return byte;
}