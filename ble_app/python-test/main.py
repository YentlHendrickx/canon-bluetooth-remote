import asyncio
import datetime
from bleak import BleakClient, BleakScanner, BleakGATTCharacteristic

CAMERA_ADDR = "DC:FE:23:4A:E0:36"

PAIRING_HANDLE = "00050002-0000-1000-0000-d8492fffa821"  # 0x0017 = handshake/pairing
SHUTTER_HANDLE = (
    "00050003-0000-1000-0000-d8492fffa821"  # 0x0019 = shutter/focus control
)
STATUS_CHAR_HANDLE = "00050004-0000-1000-0000-d8492fffa821"  # 0x001B
STATUS_CCCD_HANDLE = "00050005-0000-1000-0000-d8492fffa821"  # 0x001e = CCCD for status notifications (i think?!)

# Device info handles
MANUFACTURER_NAME = "00002a29-0000-1000-8000-00805f9b34fb"
MODEL_NUMBER = "00002a24-0000-1000-8000-00805f9b34fb"
SERIAL_NUMBER = "00002a26-0000-1000-8000-00805f9b34fb"
SOFTWARE_REVISION = "00002a28-0000-1000-8000-00805f9b34fb"

# Button constants
BUTTON_RELEASE = 0x80  # Sets the "Shutter" bit
IMMEDIATE = 0x0C  # Sets the "Focus" bit
DEVICE_NAME = "LINUX"  # Name sent during handshake


# --- Utilities ---
def timestamp():
    return datetime.datetime.now().isoformat(timespec="milliseconds")


def bytes_to_str(data: bytearray) -> str:
    return "".join(map(chr, data)) if data else "N/A"


# --- Handlers ---
def status_handler(sender: BleakGATTCharacteristic, data: bytearray):
    print(f"{timestamp()}  [NOTIFY] sender=0x{sender.handle:x}  payload={data.hex()}")


# --- BLE Operations ---
async def read_device_info(client: BleakClient):
    manufacturer = await client.read_gatt_char(MANUFACTURER_NAME)
    model = await client.read_gatt_char(MODEL_NUMBER)
    serial = await client.read_gatt_char(SERIAL_NUMBER)
    software = await client.read_gatt_char(SOFTWARE_REVISION)
    print(f"\n--- Device Info ---")
    print(f"Manufacturer: {bytes_to_str(manufacturer)}")
    print(f"Model:        {bytes_to_str(model)}")
    print(f"Serial:       {bytes_to_str(serial)}")
    print(f"Software:     {bytes_to_str(software)}")
    print(f"-------------------\n")


async def handshake(client: BleakClient):
    payload = bytearray([0x03]) + bytearray(map(ord, DEVICE_NAME))
    await client.write_gatt_char(PAIRING_HANDLE, payload, response=True)
    print(f"{timestamp()} Handshake complete.")


async def enable_indications(client: BleakClient):
    await client.write_gatt_char(
        STATUS_CCCD_HANDLE, bytearray([0x02, 0x00]), response=True
    )
    await client.start_notify(STATUS_CHAR_HANDLE, status_handler)
    await asyncio.sleep(0.5)
    print(f"{timestamp()} Indications enabled.")


async def trigger_shutter(client: BleakClient):
    print(f"{timestamp()} --- Triggering Shutter Sequence ---")
    # 1. Half-press (focus)
    await client.write_gatt_char(SHUTTER_HANDLE, bytearray([IMMEDIATE]), response=False)
    await asyncio.sleep(0.3)

    # 2. Full press (shutter)
    await client.write_gatt_char(
        SHUTTER_HANDLE, bytearray([BUTTON_RELEASE | IMMEDIATE]), response=False
    )

    # 3. Release
    await client.write_gatt_char(SHUTTER_HANDLE, bytearray([0x00]), response=False)
    print(f"{timestamp()} Shutter sequence complete.")


# --- Full session-per-shot workflow ---
async def take_photo():
    async with BleakClient(CAMERA_ADDR) as client:
        if not client.is_connected:
            print("Failed to connect to camera.")
            return
        print(f"{timestamp()} Connected to camera!")

        # Uncomment the following line to read device info
        # await read_device_info(client)
        await handshake(client)

        # Uncomment the following line to enable indications (notifications)
        # await enable_indications(client)
        await trigger_shutter(client)

        # Stop notifications before disconnecting (if they were enabled)
        # await client.stop_notify(STATUS_CHAR_HANDLE)
        print(f"{timestamp()} Disconnecting. Physical buttons unlocked.")


# --- Main interactive loop ---
async def main():
    print("Press ENTER to take a photo, or type 'q' to quit.")
    while True:
        user_input = input(">> ").strip().lower()
        if user_input == "q":
            break
        await take_photo()


if __name__ == "__main__":
    asyncio.run(main())
