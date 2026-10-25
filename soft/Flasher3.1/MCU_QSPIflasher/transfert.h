#ifndef TRANSFERT_H
#define TRANSFERT_H

#include "Arduino.h"
#include <Wire.h> 
#include "MX25L.h"

/*
 * This function look at the UART buffer 
 * and return the Byte of commande when it appear 
 */
uint8_t decodeCmd(void);

/*
 * This function look at the UART buffer 
 * and return 'len' Bytes of data in the passed array
 */
void getCmdData(uint8_t* data, uint16_t len);

/*
 * This function send 'len' Bytes from the passed array through UART
 */
void sendCmdData(uint8_t* data, uint16_t len);

/*
 * This function read the flash chip ID and send it through UART
 */
void getId(uint8_t *id);

/*
 * This function set the working address with data transfered from UART
 */
void setAddr(uint8_t *addr);

/*
 * This function erase the sector at set address
 */
void secErase(void);

/*
 * This function erase the 4k sector at set address
 */
void secErase4k(void);


/*
 * This function read the flash chip page at the set address and send it through UART
 */
void getPage(uint8_t *buffer);

/*
 * This function write the flash chip page at the set address with data transfered from UART
 */
void setPage(uint8_t *buffer);

/*
 * This function decode the commande and call the right flash function
 */
void execCmd(void);

#endif