#include "MX25L.h"
#include "transfert.h"

void setup() {
  pinMode(CSn, OUTPUT);
  pinMode(SCLK, OUTPUT);
  pinMode(SIO0, OUTPUT);
  pinMode(SIO1, OUTPUT);
  pinMode(SIO2, OUTPUT);
  pinMode(SIO3, OUTPUT);
  digitalWrite(CSn, HIGH);    // Disable the flash
  
  Serial.begin(115200);

  EEPROMsetup();
  while (!Serial) { ; }  // Wait for Serial
}

void loop() {
  execCmd();
}

