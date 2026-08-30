#!/usr/bin/env python3
"""An emulated AppSocket/JetDirect printer NIC (the thing behind port 9100).

Real network printers expose a raw TCP port that swallows whatever job bytes
you send and prints them. This emulates exactly that, so the watchdog can be
tested against socket:// queues without any of the system under test being
faked: CUPS really connects, really transfers a job, and the bytes really land
somewhere we can look at.

  --listen IP --port 9100 --spool DIR   accept jobs, write each to DIR
  --offline                             accept nothing (printer powered off)

Each received job is written to DIR/job-N.prn and a line describing it is
appended to DIR/received.log so a test can assert what arrived and from where.
"""
import argparse, os, socket, sys, threading, time

def serve(sock, spool):
    n = 0
    while True:
        conn, peer = sock.accept()
        n += 1
        path = os.path.join(spool, "job-%d.prn" % n)
        total = 0
        with open(path, "wb") as out:
            conn.settimeout(10)
            try:
                while True:
                    chunk = conn.recv(65536)
                    if not chunk:
                        break
                    out.write(chunk)
                    total += len(chunk)
            except socket.timeout:
                pass
        conn.close()
        with open(os.path.join(spool, "received.log"), "a") as log:
            log.write("%s from=%s bytes=%d file=%s\n"
                      % (time.strftime("%Y-%m-%d %H:%M:%S"), peer[0], total, path))
        print("job %d: %d bytes from %s" % (n, total, peer[0]), flush=True)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=9100)
    ap.add_argument("--spool", default=".")
    ap.add_argument("--offline", action="store_true")
    args = ap.parse_args()

    if args.offline:
        print("device is offline; not listening", flush=True)
        while True:
            time.sleep(3600)

    os.makedirs(args.spool, exist_ok=True)
    sock = socket.socket()
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((args.listen, args.port))
    sock.listen(8)
    print("JetDirect device listening on %s:%d" % (args.listen, args.port), flush=True)
    serve(sock, args.spool)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
