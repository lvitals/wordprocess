import sys
import subprocess
import shutil

def get_bytes(path):
    try:
        from PIL import Image
        return Image.open(path).resize((128, 128)).convert("RGBA").tobytes()
    except ImportError:
        pass

    for cmd in (
        ["magick", path, "-resize", "128x128!", "rgba:-"] if shutil.which("magick") else None,
        ["convert", path, "-resize", "128x128!", "rgba:-"] if shutil.which("convert") else None,
        ["ffmpeg", "-v", "error", "-i", path, "-s", "128x128", "-f", "rawvideo", "-pix_fmt", "rgba", "-"] if shutil.which("ffmpeg") else None,
    ):
        if cmd:
            try:
                res = subprocess.run(cmd, stdout=subprocess.PIPE, check=True)
                if len(res.stdout) == 128 * 128 * 4:
                    return res.stdout
            except Exception:
                continue

    raise RuntimeError("Could not process icon: neither PIL (Pillow), ImageMagick (magick/convert), nor ffmpeg found.")

raw_bytes = get_bytes(sys.argv[1])
print("extern const unsigned char icon_data[];")
print("const unsigned char icon_data[] = {")
print(", ".join([str(b) for b in raw_bytes]))
print("};")
