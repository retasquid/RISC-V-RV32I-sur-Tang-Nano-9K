from time import sleep

import serial
import serial.tools.list_ports
import sys
import os


# ============================================================
# Constants
# ============================================================

PORT = "COM9"

GET_ID          = 0x30
GET_PAGE        = 0x31
SET_PAGE        = 0x32
SET_ADDR        = 0x33
SEC_ERASE       = 0x34       # 64 KiB
SEC_ERASE_4k    = 0x35       # 4 KiB

ACK             = 0x06
NACK            = 0x15

VERBOSITY = 0

PAGE_SIZE       = 256
SECTOR_SIZE     = 0x10000    # 64 KiB
SECTOR_4K_SIZE  = 0x1000     # 4 KiB


# ============================================================
# Intel HEX
# ============================================================

def load_intel_hex(path):
    """
    Charge un fichier Intel HEX.

    Retourne une liste de zones :

        [
            (start_address, bytes_data),
            (start_address, bytes_data),
            ...
        ]

    Les zones séparées dans le HEX restent séparées.
    Les adresses sont reconstruites sur 32 bits.
    """

    zones = []

    current_upper = 0

    with open(path, "r") as f:

        for line_number, line in enumerate(f, 1):

            line = line.strip()

            if not line:
                continue

            if not line.startswith(":"):
                raise ValueError(
                    f"Intel HEX invalide ligne {line_number}: "
                    "absence de ':'"
                )

            try:
                record = bytes.fromhex(line[1:])
            except ValueError:
                raise ValueError(
                    f"Intel HEX invalide ligne {line_number}: "
                    "caractères hexadécimaux invalides"
                )

            if len(record) < 5:
                raise ValueError(
                    f"Intel HEX invalide ligne {line_number}: "
                    "record trop court"
                )

            byte_count = record[0]
            address = (record[1] << 8) | record[2]
            record_type = record[3]

            if len(record) != byte_count + 5:
                raise ValueError(
                    f"Intel HEX invalide ligne {line_number}: "
                    "longueur incorrecte"
                )

            # ------------------------------------------------
            # Checksum
            # ------------------------------------------------

            checksum = sum(record) & 0xFF

            if checksum != 0:
                raise ValueError(
                    f"Intel HEX invalide ligne {line_number}: "
                    "checksum incorrect"
                )

            data = record[4:4 + byte_count]

            # ------------------------------------------------
            # Data record
            # ------------------------------------------------

            if record_type == 0x00:

                real_address = (current_upper << 16) | address

                zones.append(
                    (real_address, bytes(data))
                )

            # ------------------------------------------------
            # End Of File
            # ------------------------------------------------

            elif record_type == 0x01:

                break

            # ------------------------------------------------
            # Extended Linear Address
            # ------------------------------------------------

            elif record_type == 0x04:

                if byte_count != 2:
                    raise ValueError(
                        f"Intel HEX invalide ligne {line_number}: "
                        "record type 04 incorrect"
                    )

                current_upper = (data[0] << 8) | data[1]

                if VERBOSITY:
                    print(
                        f"HEX address upper = "
                        f"0x{current_upper:04X}"
                    )

            # ------------------------------------------------
            # Extended Segment Address
            # ------------------------------------------------

            elif record_type == 0x02:

                raise ValueError(
                    f"Record Intel HEX type 02 non supporté "
                    f"(ligne {line_number}). "
                    "Utilise un HEX avec Extended Linear Address "
                    "(type 04)."
                )

            # ------------------------------------------------
            # Start Segment Address
            # ------------------------------------------------

            elif record_type == 0x03:

                # Pas nécessaire pour programmer la Flash.
                if VERBOSITY:
                    print(
                        f"Warning: record type 03 ignoré "
                        f"(ligne {line_number})"
                    )

            # ------------------------------------------------
            # Start Linear Address
            # ------------------------------------------------

            elif record_type == 0x05:

                # Contient normalement l'adresse de démarrage.
                if VERBOSITY:
                    start_address = (
                        (data[0] << 24) |
                        (data[1] << 16) |
                        (data[2] << 8) |
                        data[3]
                    )

                    print(
                        f"Start address HEX : "
                        f"0x{start_address:08X}"
                    )

            else:

                raise ValueError(
                    f"Record Intel HEX type "
                    f"0x{record_type:02X} non supporté "
                    f"(ligne {line_number})"
                )

    if not zones:
        raise ValueError("Aucune donnée trouvée dans le fichier HEX.")

    return merge_zones(zones)


def merge_zones(zones):
    """
    Fusionne les records Intel HEX qui sont contigus.

    Exemple :

        0x60000000 + 16 octets
        0x60000010 + 16 octets

    devient :

        0x60000000 + 32 octets

    Les trous restent des zones séparées.
    """

    zones.sort(key=lambda x: x[0])

    merged = []

    for address, data in zones:

        if not data:
            continue

        if not merged:

            merged.append(
                [address, bytearray(data)]
            )

            continue

        last_address = merged[-1][0]
        last_data = merged[-1][1]

        last_end = last_address + len(last_data)

        if address == last_end:

            last_data.extend(data)

        elif address > last_end:

            merged.append(
                [address, bytearray(data)]
            )

        else:

            raise ValueError(
                f"Chevauchement de zones HEX à "
                f"0x{address:08X}"
            )

    return [
        (address, bytes(data))
        for address, data in merged
    ]


# ============================================================
# Utility
# ============================================================

def read_exact(ser, size):

    data = b""

    while len(data) < size:

        chunk = ser.read(size - len(data))

        if not chunk:
            break

        data += chunk

    return data


def printData(data, length, address):

    if data is None:
        print("No data to print.")
        return

    for offset in range(0, length, 16):

        line = data[offset:offset + 16]

        addr = address + offset

        print(
            f"0x{addr:08X} : "
            + " ".join(f"{b:02X}" for b in line)
        )


# ============================================================
# Arduino Commands
# ============================================================

def getId(ser):

    ser.reset_input_buffer()

    ser.write(bytes([GET_ID]))

    ack = ser.read(1)

    if ack == bytes([NACK]):

        print("ERROR: GET_ID -> NACK")
        return None

    if ack != bytes([ACK]):

        print(
            "ERROR: GET_ID -> Timeout / Invalid ACK:",
            ack
        )

        return None

    data = read_exact(ser, 3)

    if len(data) != 3:

        print("ERROR: GET_ID -> Missing data")

        return None

    if VERBOSITY:

        print(
            "ID:",
            [f"{b:02X}" for b in data]
        )

    print(
        f"Flash memory : {data[2]} Mbits"
    )

    return data


def setAddr(ser, addr):

    ser.reset_input_buffer()

    ser.write(bytes([SET_ADDR]))

    ack = ser.read(1)

    if ack == bytes([NACK]):

        print("ERROR: SET_ADDR -> NACK")
        return False

    if ack != bytes([ACK]):

        print(
            "ERROR: SET_ADDR -> Timeout / Invalid ACK:",
            ack
        )

        return False

    # Adresse 32 bits
    ser.write(addr.to_bytes(4, "big"))

    return True


def secErase(ser, addr):

    # Alignement secteur 64 KiB
    sector_addr = addr & 0xFFFF0000

    if not setAddr(ser, sector_addr):
        return False

    ser.write(bytes([SEC_ERASE]))

    ack = ser.read(1)

    if ack == bytes([NACK]):

        print("ERROR: SEC_ERASE -> NACK")
        return False

    if ack != bytes([ACK]):

        print(
            "ERROR: SEC_ERASE -> Timeout / Invalid ACK:",
            ack
        )

        return False

    if VERBOSITY:

        print(
            f"Sector erased: 0x{sector_addr:08X}"
        )

    return True


def secErase4k(ser, addr):

    # Alignement secteur 4 KiB
    sector_addr = addr & 0xFFFFF000

    if not setAddr(ser, sector_addr):
        return False

    ser.write(bytes([SEC_ERASE_4k]))

    ack = ser.read(1)

    if ack == bytes([NACK]):

        print("ERROR: SEC_ERASE_4k -> NACK")
        return False

    if ack != bytes([ACK]):

        print(
            "ERROR: SEC_ERASE_4k -> "
            "Timeout / Invalid ACK:",
            ack
        )

        return False

    if VERBOSITY:

        print(
            f"Sector 4k erased: 0x{sector_addr:08X}"
        )

    return True


def getPage(ser):

    ser.reset_input_buffer()

    ser.write(bytes([GET_PAGE]))

    ack = ser.read(1)

    if ack == bytes([NACK]):

        print("ERROR: GET_PAGE -> NACK")
        return None

    if ack != bytes([ACK]):

        print(
            "ERROR: GET_PAGE -> "
            "Timeout / Invalid ACK:",
            ack
        )

        return None

    data = read_exact(ser, PAGE_SIZE)

    if len(data) != PAGE_SIZE:

        print(
            "ERROR: GET_PAGE -> Missing data"
        )

        return None

    return data


def setPage(ser, page_data):

    if len(page_data) != PAGE_SIZE:

        raise ValueError(
            "setPage() nécessite exactement "
            "256 octets"
        )

    ser.reset_input_buffer()

    ser.write(bytes([SET_PAGE]))

    ack = ser.read(1)

    if ack == bytes([NACK]):

        print("ERROR: SET_PAGE -> NACK")
        return False

    if ack != bytes([ACK]):

        print(
            "ERROR: SET_PAGE -> "
            "Timeout / Invalid ACK:",
            ack
        )

        return False

    ser.write(page_data)

    return True


# ============================================================
# Erase management
# ============================================================

def erase_sectors_for_zone(
    ser,
    address,
    length,
    sector_size
):

    if length == 0:
        return True

    first_sector = address & ~(sector_size - 1)

    last_address = address + length - 1

    last_sector = last_address & ~(sector_size - 1)

    sector = first_sector

    while sector <= last_sector:

        if sector_size == SECTOR_SIZE:

            if not secErase(ser, sector):
                return False

        else:

            if not secErase4k(ser, sector):
                return False

        sleep(0.5)

        sector += sector_size

    return True


# ============================================================
# Write one zone
# ============================================================

def writeZone(
    ser,
    address,
    data,
    use_4k_erase=False
):

    length = len(data)

    if length == 0:
        return True

    print(
        f"\nWriting zone : "
        f"0x{address:08X} - "
        f"0x{address + length - 1:08X}"
    )

    print(
        f"Size         : {length} bytes"
    )

    # --------------------------------------------------------
    # Erase
    # --------------------------------------------------------

    if use_4k_erase:

        sector_size = SECTOR_4K_SIZE

    else:

        sector_size = SECTOR_SIZE

    print("Erasing...")

    if not erase_sectors_for_zone(
        ser,
        address,
        length,
        sector_size
    ):

        print("ERROR: Erase failed!")
        return False

    # --------------------------------------------------------
    # Page programming
    # --------------------------------------------------------

    written = 0

    while written < length:

        curr = address + written

        # Nombre d'octets disponibles jusqu'à la fin
        # de la page QSPI.
        page_offset = curr & (PAGE_SIZE - 1)

        space = PAGE_SIZE - page_offset

        chunk = min(
            space,
            length - written
        )

        page_data = data[
            written:
            written + chunk
        ]

        # ----------------------------------------------------
        # IMPORTANT :
        #
        # Si la page n'est pas complète, on complète avec FF.
        #
        # Après erase, une Flash contient FF.
        # ----------------------------------------------------

        page_data = page_data.ljust(PAGE_SIZE, b"\xFF")

        if VERBOSITY:

            print(
                f"  Page: "
                f"{chunk} bytes @ "
                f"0x{curr:08X}"
            )

        else:

            percent = (
                written * 100 / length
            )

            bar = int(
                written * 50 / length
            )

            print(
                f"Uploading "
                f"{percent:5.1f}% "
                f"[{'#' * bar}"
                f"{'.' * (50 - bar)}]",
                end="\r"
            )

        # ----------------------------------------------------
        # Set address
        # ----------------------------------------------------

        if not setAddr(ser, curr):

            print(
                "ERROR: SET_ADDR failed!"
            )

            return False

        sleep(0.05)

        # ----------------------------------------------------
        # Write page
        # ----------------------------------------------------

        if not setPage(ser, page_data):

            print(
                "ERROR: SET_PAGE failed!"
            )

            return False

        # ----------------------------------------------------
        # Verification
        # ----------------------------------------------------

        read_back = getPage(ser)
        
        if read_back is None:

            print(
                "ERROR: GET_PAGE failed!"
            )

            return False

        if read_back != page_data:

            print(
                "ERROR: Verification failed!"
            )

            print("Expected:")

            printData(
                page_data,
                PAGE_SIZE,
                curr
            )

            print("Read back:")

            printData(
                read_back,
                PAGE_SIZE,
                curr
            )

            return False

        written += chunk

    if not VERBOSITY:

        print()

    print(
        f"Zone complete: "
        f"{written} bytes"
    )

    return True


# ============================================================
# Main
# ============================================================

def main():

    global PORT

    # --------------------------------------------------------
    # Argument
    # --------------------------------------------------------

    if len(sys.argv) < 2:

        print(
            "Usage: programmer.py <firmware.hex>"
        )

        return

    hex_path = sys.argv[1]

    if not os.path.isfile(hex_path):

        print(
            f"ERROR: File not found: {hex_path}"
        )

        return

    if not hex_path.lower().endswith(".hex"):

        print(
            "WARNING: file extension is not .hex"
        )

    # --------------------------------------------------------
    # Load Intel HEX
    # --------------------------------------------------------

    print(
        f"Loading HEX: {hex_path}"
    )

    try:

        zones = load_intel_hex(hex_path)

    except Exception as e:

        print(
            f"ERROR while reading HEX: {e}"
        )

        return

    print(
        f"\nHEX contains {len(zones)} zone(s):"
    )

    total_size = 0

    for address, data in zones:

        end_address = (
            address + len(data) - 1
        )

        print(
            f"  "
            f"0x{address:08X} -> "
            f"0x{end_address:08X} "
            f"({len(data)} bytes)"
        )

        total_size += len(data)

    print(
        f"Total data: {total_size} bytes"
    )

    # --------------------------------------------------------
    # Serial connection
    # --------------------------------------------------------

    while True:

        try:

            ser = serial.Serial(
                PORT,
                baudrate=115200,
                timeout=2
            )

            break

        except Exception:

            ports = list(
                serial.tools.list_ports.comports()
            )

            if not ports:

                print("NO COM port found.")

            else:

                print("COM port found:")

                for p in ports:

                    print(f"  {p.device}")

            PORT = input("Select your COM port > ")

    print("Port selected:", ser.portstr)

    sleep(2)

    # --------------------------------------------------------
    # Flash ID
    # --------------------------------------------------------

    if getId(ser) is None:
        ser.close()
        return

    sleep(1)

    # --------------------------------------------------------
    # Program every HEX zone
    # --------------------------------------------------------

    for address, data in zones:

        # ----------------------------------------------------
        # Detect vector table
        #
        # Ta vector table étant à la fin de la Flash :
        #
        # 0x603FFF00
        #
        # On utilise les secteurs 4 KiB.
        # ----------------------------------------------------

        if (address >= 0x603FF000 and address < 0x60400000):
            use_4k = True
            if VERBOSITY:
                print("\nVector table zone detected.")
        else:
            use_4k = False

        # ----------------------------------------------------
        # Write zone
        # ----------------------------------------------------

        if not writeZone(ser, address, data, use_4k_erase=use_4k):
            print("\nERROR: Programming failed!")
            ser.close()
            return
        
        sleep(0.2)

    # --------------------------------------------------------
    # Finished
    # --------------------------------------------------------

    print("\nFlashing finished successfully.")
    ser.close()

# ============================================================
# Entry point
# ============================================================

if __name__ == "__main__":

    main()
