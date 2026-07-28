"""Monologue hub/gateway — Pi Zero 2 W.

Phase 2 reference skeleton: pulls PCM frames off the sensor node's BLE
characteristic, hands them to a pluggable transcriber, and fans the
result out over whichever transport is configured. This is the shape of
the phase-2 exit criteria in docs/prototype-plan.md, not a finished
gateway — the ASR backend, the mTLS socket, and the IR encoder are each
their own real piece of work, stubbed here so the routing logic has
something to call.

Requires (phase 2): `bleak` for BLE central. The WLAN transport, IR
transport, and ASR backend are separate modules to build out per
architecture.md's transport table — see the TODOs below for where each
one plugs in.
"""

import asyncio
import struct
from dataclasses import dataclass

from bleak import BleakClient, BleakScanner

NODE_NAME = "Monologue-Node"
CHAR_UUID_TX = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
FRAME_SAMPLES = 160
SAMPLE_RATE_HZ = 8000


@dataclass
class AudioFrame:
    samples: list[int]
    sample_rate_hz: int = SAMPLE_RATE_HZ


class Transcriber:
    """Pluggable ASR backend.

    Phase 2: stub — just proves frames flow end to end.
    Phase 7: swap in a whisper.cpp (tiny/base) instance fine-tuned on the
    wearer-specific corpus from prototype-plan.md phase 1, or forward raw
    audio to the Mac/iPhone for on-device transcription instead of running
    ASR on the Pi at all — decide based on the Pi Zero 2's actual spare
    compute once phase 1's model is picked.
    """

    def transcribe(self, frame: AudioFrame) -> str | None:
        raise NotImplementedError(
            "wire up whisper.cpp or a forward-to-phone path here (phase 7)"
        )


class Router:
    """Picks a transport per architecture.md's table.

    Each send_* method is a real subsystem (mTLS socket server, Shortcuts-
    triggered relay, IR UART encoder) that phase 2/6/7 build out
    independently — this class only owns the *choice* of which one to use
    for a given piece of text, not their implementations.
    """

    def __init__(self):
        self.wlan_client_connected = False  # set by the mTLS server once a phone/Mac is attached

    def route_text(self, text: str) -> None:
        if self.wlan_client_connected:
            self.send_wlan(text)
        else:
            self.send_relay_via_paired_phone(text)

    def send_wlan(self, text: str) -> None:
        raise NotImplementedError("phase 2: mTLS WebSocket/TCP server to iOS/macOS client")

    def send_relay_via_paired_phone(self, text: str) -> None:
        raise NotImplementedError(
            "phase 2+: push to paired phone over BLE/WLAN, phone-side Shortcuts "
            "automation sends as iMessage/SMS/RCS -- see docs/architecture.md"
        )

    def send_ir(self, text: str) -> None:
        raise NotImplementedError("phase 6: UART-encode over the IrDA transceiver HAT")


def decode_frame(payload: bytes) -> AudioFrame:
    n = len(payload) // 2
    samples = list(struct.unpack(f"<{n}h", payload))
    return AudioFrame(samples=samples)


async def run():
    transcriber = Transcriber()
    router = Router()

    device = await BleakScanner.find_device_by_name(NODE_NAME)
    if device is None:
        raise RuntimeError(f"no BLE device advertising as {NODE_NAME!r} found")

    def on_notify(_handle, payload: bytearray):
        frame = decode_frame(bytes(payload))
        text = transcriber.transcribe(frame)
        if text:
            router.route_text(text)

    async with BleakClient(device) as client:
        await client.start_notify(CHAR_UUID_TX, on_notify)
        print(f"connected to {NODE_NAME}, streaming...")
        await asyncio.Event().wait()  # run until killed


if __name__ == "__main__":
    asyncio.run(run())
