#include "MX25L.h"
#include "transfert.h"

#define HOLDn A3  // Serial Input (MOSI)
#define WPn A0    // Chip Select


void setup() {
  pinMode(CSn, OUTPUT);
  pinMode(SCLK, OUTPUT);
  pinMode(SI, OUTPUT);
  pinMode(SO, INPUT);
  pinMode(HOLDn, OUTPUT);
  pinMode(WPn, OUTPUT);
  digitalWrite(HOLDn, HIGH);
  digitalWrite(WPn, HIGH);

  digitalWrite(CSn, HIGH);  // Disable the flash
  Serial.begin(115200);
  EEPROMsetup();
  while (!Serial) { ; }  // Wait for Serial
}

void loop() {
  execCmd();
}
