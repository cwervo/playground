import sys, os, time
import cv2
import yt_dlp
import wave
import numpy as np
import traceback

def scan(image_path):
    img = cv2.imread(image_path)
    if img is None: return "NO_QR"
    try:
        detector = cv2.QRCodeDetector()
        data, bbox, _ = detector.detectAndDecode(img)
        if data and "soundcloud.com" in data:
            if bbox is not None and len(bbox) > 0:
                pts = bbox[0]
                cx = sum(p[0] for p in pts) / 4.0
                cy = sum(p[1] for p in pts) / 4.0
                return f"QR_FOUND {data} {cx} {cy}"
            return f"QR_FOUND {data} 0 0"
    except Exception as e:
        pass
    return "NO_QR"

def fetch(url, out_dir):
    try:
        ydl_opts = {
            'outtmpl': os.path.join(out_dir, '%(id)s.%(ext)s'),
            'format': 'bestaudio/best',
            'postprocessors': [{'key': 'FFmpegExtractAudio', 'preferredcodec': 'wav'}],
            'writethumbnail': True,
            'quiet': True
        }
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            vid_id = info['id']
            wav_path = os.path.join(out_dir, f"{vid_id}.wav")
            thumb_path = "none"
            for ext in ['jpg', 'webp', 'png']:
                if os.path.exists(os.path.join(out_dir, f"{vid_id}.{ext}")):
                    thumb_path = os.path.join(out_dir, f"{vid_id}.{ext}")
                    break
            
            sparkline = []
            if os.path.exists(wav_path):
                with wave.open(wav_path, 'rb') as wf:
                    nframes = wf.getnframes()
                    framerate = wf.getframerate()
                    duration = nframes / float(framerate) if framerate > 0 else 0
                    nchannels = wf.getnchannels()
                    sampwidth = wf.getsampwidth()
                    frames = wf.readframes(nframes)
                    dtype = np.int16 if sampwidth == 2 else np.uint8
                    sig = np.frombuffer(frames, dtype=dtype)
                    if nchannels > 1:
                        sig = sig.reshape(-1, nchannels).mean(axis=1)
                    
                    chunks = np.array_split(sig, 100)
                    sparkline = [float(np.max(np.abs(c))) for c in chunks]
                    max_val = max(sparkline) if sparkline else 1
                    if max_val == 0: max_val = 1
                    sparkline = [round(x / max_val, 3) for x in sparkline]
            
            sparkline_str = "{" + " ".join(str(x) for x in sparkline) + "}"
            tcl_dict = f"wav {{{wav_path}}} thumb {{{thumb_path}}} duration {duration} sparkline {sparkline_str}"
            return f"FETCHED {url} {{{tcl_dict}}}"
    except Exception as e:
        print(f"Error fetching {url}: {e}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        return f"FETCH_FAILED {url}"

def daemon():
    while True:
        line = sys.stdin.readline()
        if not line: break
        line = line.strip()
        if not line: continue
        parts = line.split(" ")
        cmd = parts[0]
        if cmd == "SCAN":
            print(scan(parts[1]), flush=True)
        elif cmd == "FETCH":
            print(fetch(parts[1], parts[2]), flush=True)

if __name__ == "__main__":
    if sys.argv[1] == "daemon":
        daemon()
