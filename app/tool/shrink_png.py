"""Makes README pictures small enough to keep in the repository (under ~550 KB each).

    python3 tool/shrink_png.py <folder>

Pictures already small are left alone. Bigger ones (photos on the websites) are saved with a
palette of 256 colours chosen for that picture (like pngquant), which keeps them sharp.
Uses pngquant when it is installed, else Pillow.
"""
import os
import shutil
import subprocess
import sys

LIMIT = 550_000


def shrink(path):
    before = os.path.getsize(path)
    if before <= LIMIT:
        return
    if shutil.which('pngquant'):
        subprocess.run(['pngquant', '--force', '--skip-if-larger', '--quality=70-95', '--output', path, path], check=False)
    else:
        from PIL import Image

        img = Image.open(path).convert('RGB')
        for colours in (256, 192, 128):
            img.quantize(colors=colours, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG).save(path, optimize=True)
            if os.path.getsize(path) <= LIMIT:
                break
    print(f'{os.path.basename(path)}: {before // 1024} KB -> {os.path.getsize(path) // 1024} KB')


if __name__ == '__main__':
    folder = sys.argv[1]
    for name in sorted(os.listdir(folder)):
        if name.endswith('.png'):
            shrink(os.path.join(folder, name))
