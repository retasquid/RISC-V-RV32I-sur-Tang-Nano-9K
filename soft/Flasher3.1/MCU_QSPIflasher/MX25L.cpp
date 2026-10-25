#include "MX25L.h"

// Afficher des données en hexadécimal avec formatage amélioré
void printHexData(const uint8_t *data, uint16_t length, uint32_t offset) {
  for(uint32_t i = offset; i < length+offset; i++) {
    if(i % 16 == 0) {
      Serial.print("0x");
      if(i < 0x10) Serial.print("0");
      if(i < 0x100) Serial.print("0");
      Serial.print(i, HEX);
      Serial.print(": ");
    }
    if(data[i] < 0x10) Serial.print("0");
    Serial.print(data[i], HEX);
    Serial.print(" ");
    if((i + 1) % 16 == 0) {
      Serial.println();
    } else if((i + 1) % 4 == 0) {
      Serial.print(" ");
    }
  }
  if(length % 16 != 0) Serial.println();
}

bool verifyData(const uint8_t *expected, const uint8_t *actual, uint16_t length) {
  for(uint16_t i = 0; i < length; i++) {
    if(expected[i] != actual[i]) {
      Serial.print("ERREUR à l'offset ");
      Serial.print(i);
      Serial.print(": attendu 0x");
      if(expected[i] < 0x10) Serial.print("0");
      Serial.print(expected[i], HEX);
      Serial.print(", lu 0x");
      if(actual[i] < 0x10) Serial.print("0");
      Serial.println(actual[i], HEX);
      return false;
    }
  }
  return true;
}

void writeMultiplePages(uint32_t address, const uint8_t *data, uint16_t length) {
  uint16_t bytesWritten = 0;
  Serial.println("Début écriture multi-pages:");
  while(bytesWritten < length) {
    uint32_t currentAddress = address + bytesWritten;
    uint16_t pageOffset  = currentAddress & 0xFF;
    uint16_t bytesInPage = 256 - pageOffset;
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

// ---------------------------------------------------------------------------
void EEPROMsetup() {
  Serial.println("Initialisation de l'EEPROM MX25L...");

  // Forcer WP# et HOLD# inactifs (HIGH) dès le départ
  pinMode(SIO2, OUTPUT);
  pinMode(SIO3, OUTPUT);
  digitalWrite(SIO2, HIGH);
  digitalWrite(SIO3, HIGH);

  // Reset de la puce pour s'assurer qu'elle est dans un état connu
  resetDevice();

  uint8_t status = readStatus1();
  Serial.print("Status1 initial = 0x"); Serial.println(status, HEX);
  if(status & 0x01) Serial.println("  - BUSY");
  if(status & 0x02) Serial.println("  - WEL actif");
  if(status & 0x3C) Serial.println("  - Protection active");

  if(status & 0x3C) {
    Serial.println("Désactivation de la protection...");
    writeEnable();
    writeStatus1(0x00);
    Serial.println("Protection désactivée");
  }
  status = readStatus2();
  Serial.print("Status2 initial = 0x"); Serial.println(status, HEX);

  // QE déjà actif ? (non-volatile → survit au reset)
  if(status & 0x02) {
    Serial.println("QE déjà actif, rien à faire.");
    return;
  }

  Serial.println("Activation de QE...");
  writeEnable();

  // FIX : conserver les bits BP en place, juste ajouter QE
  uint8_t sr2_current = (readStatus2() & 0x01)| 0x02;
  writeStatus2(sr2_current);   // QE=1, SRP1 préservés

  // FIX : laisser WIP se lever avant de tester
  delay(5);
  uint8_t sr_after = readStatus2();
  Serial.print("Status2 après écriture = 0x"); Serial.println(sr_after, HEX);

  if(sr_after & 0x02) {
    Serial.println("QE Actif !");
  } else {
    Serial.print("Erreur QE Non Actif : status = 0x");
    Serial.println(sr_after, HEX);
  }
}

// ---------------------------------------------------------------------------
void resetDevice() {
  digitalWrite(CSn, LOW);
  sendByte(RESET_ENABLE);
  digitalWrite(CSn, HIGH);
  delayMicroseconds(10);

  digitalWrite(CSn, LOW);
  sendByte(RESET_DEVICE);
  digitalWrite(CSn, HIGH);

  delay(30);
  Serial.println("Reset terminé");
}

// ---------------------------------------------------------------------------
uint8_t readStatus1() {
  uint8_t status;
  digitalWrite(CSn, LOW);
  sendByte(READ_STATUS_REG);
  status = receiveByte();
  digitalWrite(CSn, HIGH);
  return status;
}

uint8_t readStatus2() {
  uint8_t status;
  digitalWrite(CSn, LOW);
  sendByte(READ_STATUS_REG2);
  status = receiveByte();
  digitalWrite(CSn, HIGH);
  return status;
}

// ---------------------------------------------------------------------------
void writeEnable() {
  // S'assurer que WP# et HOLD# sont inactifs
  pinMode(SIO2, OUTPUT); digitalWrite(SIO2, HIGH);
  pinMode(SIO3, OUTPUT); digitalWrite(SIO3, HIGH);

  digitalWrite(CSn, LOW);
  sendByte(WRITE_ENABLE);
  digitalWrite(CSn, HIGH);

  uint8_t status = readStatus1();
  if(!(status & 0x02)) {
    Serial.println("ERREUR: Write Enable a échoué!");
  }
}

// ---------------------------------------------------------------------------
void writeDisable() {
  digitalWrite(CSn, LOW);
  sendByte(WRITE_DISABLE);
  digitalWrite(CSn, HIGH);
}

// ---------------------------------------------------------------------------
void writeStatus1(uint8_t status1) {
  // S'assurer que WP# et HOLD# sont inactifs pendant toute l'opération
  pinMode(SIO2, OUTPUT); digitalWrite(SIO2, HIGH);
  pinMode(SIO3, OUTPUT); digitalWrite(SIO3, HIGH);

  digitalWrite(CSn, LOW);
  sendByte(WRITE_STATUS_REG);
  sendByte(status1);
  digitalWrite(CSn, HIGH);

  // FIX : do/while pour ne pas rater le front montant de WIP
  // Si WIP est lu à 0 trop vite, on attendra au moins 1ms
  delayMicroseconds(50);                          // Laisser WIP monter
  do { delay(1); } while(readStatus1() & 0x01);    // Attendre fin d'écriture
}

void writeStatus2(uint8_t status2) {
  // S'assurer que WP# et HOLD# sont inactifs pendant toute l'opération
  pinMode(SIO2, OUTPUT); digitalWrite(SIO2, HIGH);
  pinMode(SIO3, OUTPUT); digitalWrite(SIO3, HIGH);

  digitalWrite(CSn, LOW);
  sendByte(WRITE_STATUS_REG2);
  sendByte(status2);
  digitalWrite(CSn, HIGH);

  // FIX : do/while pour ne pas rater le front montant de WIP
  // Si WIP est lu à 0 trop vite, on attendra au moins 1ms
  delayMicroseconds(50);                          // Laisser WIP monter
  do { delay(1); } while(readStatus2() & 0x01);    // Attendre fin d'écriture
}

// ---------------------------------------------------------------------------
void readID(uint8_t *id) {
  digitalWrite(CSn, LOW);
  sendByte(READ_ID);
  id[0] = receiveByte();   // 0xC2 = Macronix
  id[1] = receiveByte();   // Type
  id[2] = receiveByte();   // Capacité (0x16 = 32Mbit)
  digitalWrite(CSn, HIGH);
}

// ---------------------------------------------------------------------------
void EEPROMread(uint32_t address, uint8_t *buffer, uint16_t length) {
  digitalWrite(CSn, LOW);
  sendByte(FAST_READ);
  sendByte((address >> 16) & 0xFF);
  sendByte((address >> 8)  & 0xFF);
  sendByte( address        & 0xFF);
  sendByte(0xFF);
  for(uint16_t i = 0; i < length; i++) {
    buffer[i] = receiveByte();
  }
  digitalWrite(CSn, HIGH);
}

// ---------------------------------------------------------------------------
void EEPROMQread(uint32_t address, uint8_t *buffer, uint16_t length) {
  // FIX : Maintenir SIO2 et SIO3 HIGH jusqu'à ce qu'on passe en réception
  //       pour éviter que HOLD# soit vu comme actif si QE=0

  digitalWrite(CSn, LOW);

  // Commande 0x3B en mode 1-bit (SIO0 uniquement)
  sendByte(FOUR_READ);

  // Adresse 24 bits en Quad (SIO0-3)
  sendQByte((address >> 16) & 0xFF);
  sendQByte((address >> 8)  & 0xFF);
  sendQByte( address        & 0xFF);
  sendQByte(0x00);
  sendQByte(0x00);
  sendQByte(0x00);

  pinMode(SIO0, INPUT);
  pinMode(SIO1, INPUT);
  pinMode(SIO2, INPUT);
  pinMode(SIO3, INPUT);
  // Réception des données
  for(uint16_t i = 0; i < length; i++) {
    buffer[i] = receiveQByte();
  }

  digitalWrite(CSn, HIGH);
}

// ---------------------------------------------------------------------------
void EEPROMwrite(uint32_t address, const uint8_t *buffer, uint16_t length) {
  if((address & 0xFF) + length > 256) {
    Serial.println("ERREUR: L'écriture traverse une limite de page");
    return;
  }
  writeEnable();
  digitalWrite(CSn, LOW);
  sendByte(PAGE_PROGRAM);
  sendByte((address >> 16) & 0xFF);
  sendByte((address >> 8)  & 0xFF);
  sendByte( address        & 0xFF);
  for(uint16_t i = 0; i < length; i++) {
    sendByte(buffer[i]);
  }
  digitalWrite(CSn, HIGH);
  delayMicroseconds(50);
  do { delay(1); } while(readStatus1() & 0x01);
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
  while(readStatus1() & 0x01) {
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
  while(readStatus1() & 0x01) {
    delay(100);
  }
  writeDisable();
}

// ---------------------------------------------------------------------------
// sendByte : mode SPI 1-bit, SIO0=MOSI, SIO2=WP#=HIGH, SIO3=HOLD#=HIGH
void sendByte(uint8_t byte) {
  pinMode(SIO0, OUTPUT);
  pinMode(SIO1, INPUT);
  // FIX : maintenir WP# et HOLD# HIGH à chaque appel
  pinMode(SIO2, OUTPUT); digitalWrite(SIO2, HIGH);
  pinMode(SIO3, OUTPUT); digitalWrite(SIO3, HIGH);

  for(int i = 7; i >= 0; i--) {
    digitalWrite(SIO0, (byte >> i) & 0x01);
    digitalWrite(SCLK, HIGH);
    delayMicroseconds(5);
    digitalWrite(SCLK, LOW);
    delayMicroseconds(5);
  }
}

// ---------------------------------------------------------------------------
// sendQByte : mode Quad, 2 cycles d'horloge par octet
// Cycle 1 : nibble haut (bits 7..4) → SIO3=b7, SIO2=b6, SIO1=b5, SIO0=b4
// Cycle 2 : nibble bas  (bits 3..0) → SIO3=b3, SIO2=b2, SIO1=b1, SIO0=b0
void sendQByte(uint8_t byte) {
  pinMode(SIO0, OUTPUT);
  pinMode(SIO1, OUTPUT);
  pinMode(SIO2, OUTPUT);
  pinMode(SIO3, OUTPUT);

  // Nibble haut
  digitalWrite(SIO0, (byte >> 4) & 0x01);
  digitalWrite(SIO1, (byte >> 5) & 0x01);
  digitalWrite(SIO2, (byte >> 6) & 0x01);
  digitalWrite(SIO3, byte >> 7 & 0x01);
  digitalWrite(SCLK, HIGH);
  delayMicroseconds(5);
  digitalWrite(SCLK, LOW);
  delayMicroseconds(5);

  // Nibble bas
  digitalWrite(SIO0, byte & 0x01);
  digitalWrite(SIO1, (byte >> 1) & 0x01);
  digitalWrite(SIO2, (byte >> 2) & 0x01);
  digitalWrite(SIO3, (byte >> 3) & 0x01);
  digitalWrite(SCLK, HIGH);
  delayMicroseconds(5);
  digitalWrite(SCLK, LOW);
  delayMicroseconds(5);
}

// ---------------------------------------------------------------------------
// receiveByte : mode SPI 1-bit, lecture sur SIO1 (MISO)
void receiveByte_setup() {
  // Helper séparé pour la configuration des pins
  pinMode(SIO0, INPUT);       // Libérer MOSI
  pinMode(SIO1, INPUT);       // MISO
  // FIX : maintenir WP# et HOLD# HIGH
  pinMode(SIO2, OUTPUT); digitalWrite(SIO2, HIGH);
  pinMode(SIO3, OUTPUT); digitalWrite(SIO3, HIGH);
}

uint8_t receiveByte() {
  pinMode(SIO0, INPUT);
  pinMode(SIO1, INPUT);
  pinMode(SIO2, OUTPUT); digitalWrite(SIO2, HIGH);   // WP#   = HIGH
  pinMode(SIO3, OUTPUT); digitalWrite(SIO3, HIGH);   // HOLD# = HIGH

  uint8_t byte = 0;
  for(int i = 7; i >= 0; i--) {
    digitalWrite(SCLK, HIGH);
    delayMicroseconds(5);
    byte |= (digitalRead(SIO1) << i);
    digitalWrite(SCLK, LOW);
    delayMicroseconds(5);
  }
  return byte;
}

// ---------------------------------------------------------------------------
// receiveQByte : mode Quad, lecture sur SIO0-3
// FIX : SIO2 et SIO3 passent en INPUT seulement ici (QE doit être actif)
//       Si QE=0, utiliser INPUT_PULLUP pour éviter que HOLD# soit vu LOW
uint8_t receiveQByte() {
  uint8_t byte = 0;

  // Nibble haut
  digitalWrite(SCLK, HIGH);
  delayMicroseconds(5);
  byte  = ((digitalRead(SIO0)&1) << 4)
        | ((digitalRead(SIO1)&1) << 5)
        | ((digitalRead(SIO2)&1) << 6)
        |  (digitalRead(SIO3)&1) << 7;
  digitalWrite(SCLK, LOW);
  delayMicroseconds(5);
  // Nibble bas moy
  digitalWrite(SCLK, HIGH);
  delayMicroseconds(5);
  byte |= (digitalRead(SIO0)&1)
        | ((digitalRead(SIO1)&1) << 1)
        | ((digitalRead(SIO2)&1) << 2)
        |  (digitalRead(SIO3)&1) << 3;
  digitalWrite(SCLK, LOW);
  delayMicroseconds(5);

  return byte;
}
