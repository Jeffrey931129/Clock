import argparse
import socket
import threading

import sounddevice as sd

SAMPLE_RATE = 48000
BYTES_PER_FRAME = 2
MAX_BUFFER = SAMPLE_RATE * BYTES_PER_FRAME * 200 // 1000
KEEP_BUFFER = SAMPLE_RATE * BYTES_PER_FRAME * 60 // 1000


class AudioBuffer:
    def __init__(self):
        self.data = bytearray()
        self.lock = threading.Lock()

    def push(self, chunk):
        with self.lock:
            self.data.extend(chunk)
            if len(self.data) > MAX_BUFFER:
                del self.data[: len(self.data) - KEEP_BUFFER]

    def pull(self, size):
        with self.lock:
            out = bytes(self.data[:size])
            del self.data[:size]
        return out + bytes(size - len(out))

    def clear(self):
        with self.lock:
            self.data.clear()


def find_device(name):
    candidates = []
    for index, device in enumerate(sd.query_devices()):
        if device["max_output_channels"] == 0:
            continue
        if name.lower() not in device["name"].lower():
            continue
        if "16ch" in device["name"]:
            continue
        api = sd.query_hostapis(device["hostapi"])["name"]
        rank = 0 if "WASAPI" in api else 1 if "DirectSound" in api else 2
        candidates.append((rank, index, api))
    if not candidates:
        raise SystemExit(f"Output device containing '{name}' was not found")
    candidates.sort()
    return candidates[0]


def open_stream(buffer, device_name):
    _, index, api = find_device(device_name)
    channels = min(2, sd.query_devices(index)["max_output_channels"])

    def callback(outdata, frames, time, status):
        mono = buffer.pull(frames * BYTES_PER_FRAME)
        if channels == 1:
            outdata[:] = mono
            return
        stereo = bytearray(frames * BYTES_PER_FRAME * channels)
        for c in range(channels):
            stereo[c * 2 :: channels * 2] = mono[0::2]
            stereo[c * 2 + 1 :: channels * 2] = mono[1::2]
        outdata[:] = stereo

    extra = sd.WasapiSettings(auto_convert=True) if "WASAPI" in api else None
    stream = sd.RawOutputStream(
        samplerate=SAMPLE_RATE,
        blocksize=480,
        device=index,
        channels=channels,
        dtype="int16",
        latency="low",
        callback=callback,
        extra_settings=extra,
    )
    stream.start()
    print(f"Output -> {sd.query_devices(index)['name']} ({api})")
    return stream


def serve(port, buffer):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", port))
    server.listen(1)
    print(f"Listening on port {port}")
    while True:
        conn, addr = server.accept()
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        print(f"Connected {addr[0]}")
        buffer.clear()
        pending = b""
        try:
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                chunk = pending + chunk
                usable = len(chunk) - len(chunk) % BYTES_PER_FRAME
                pending = chunk[usable:]
                buffer.push(chunk[:usable])
        except OSError:
            pass
        finally:
            conn.close()
            buffer.clear()
            print(f"Disconnected {addr[0]}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=7700)
    parser.add_argument("--device", default="CABLE Input")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if args.list:
        print(sd.query_devices())
        return
    buffer = AudioBuffer()
    stream = open_stream(buffer, args.device)
    try:
        serve(args.port, buffer)
    except KeyboardInterrupt:
        pass
    finally:
        stream.stop()
        stream.close()


if __name__ == "__main__":
    main()
