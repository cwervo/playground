# Simulating Camera / Capturing Projector Texture

When the physical projector is turned off, the real camera will only see a dark room, making it impossible to see Folk's rendering output on the table or verify programs visually.

Instead of relying on the physical camera, we can directly capture the Vulkan renderer's internal textures (specifically the DRM/KMS scanout plane) using scripts provided in `~/code/folk-debug`.

## The Tool

The script `~/code/folk-debug/capture_projector_renderer.sh` grabs the active frame from a remote Folk machine.

**Command to capture a single still image:**
```bash
~/code/folk-debug/capture_projector_renderer.sh \
  --ssh folk@folk-cwe \
  --still-only \
  --out-dir ~/folk_captures
```

**How it works:**
1. It connects via SSH to the Folk server (`folk-cwe` in our case).
2. It captures the raw output from the DRM/KMS subsystem (the frame that is *supposed* to be sent to the projector).
3. If KMS is unavailable (e.g., HDMI unplugged), it falls back to sampling the Folk web debug surfaces (`/textures`) directly.
4. It saves a `.png` still and a contact sheet `.jpg` to the specified output directory locally.

This is extremely useful for debugging virtual programs and physics simulations like Pong when the physical space isn't perfectly set up!
