"""Shared tileable detail textures: skin pores (normal), cloth weave (normal) and a bag fabric (colour)."""
import os, sys, numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import people_spec as PS
OUT = os.path.join(PS.PROJECT, "assets", "people", "tex")
os.makedirs(OUT, exist_ok=True)

def fbm(n, beta, seed):
    rng = np.random.RandomState(seed)
    F = np.fft.fft2(rng.randn(n, n))
    fx = np.fft.fftfreq(n)[:, None]; fy = np.fft.fftfreq(n)[None, :]
    f = np.sqrt(fx * fx + fy * fy); f[0, 0] = 1.0
    F = F / f ** beta; F[0, 0] = 0
    h = np.real(np.fft.ifft2(F))
    return (h - h.mean()) / (h.std() + 1e-9)

def worley(n, cells, seed):
    rng = np.random.RandomState(seed)
    pts = rng.rand(cells, cells, 2)
    yy, xx = np.mgrid[0:n, 0:n] / n * cells
    d = np.full((n, n), 9.0)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            cy = (np.floor(yy) + dy); cx = (np.floor(xx) + dx)
            p = pts[(cy % cells).astype(int), (cx % cells).astype(int)]
            px = cx + p[..., 0]; py = cy + p[..., 1]
            d = np.minimum(d, np.sqrt((xx - px) ** 2 + (yy - py) ** 2))
    return d

def normal_from_height(h, strength):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx = -gx * strength; ny = gy * strength; nz = np.ones_like(h)   # OpenGL: +Y up in texture space
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / l, ny / l, nz / l], -1) * 0.5 + 0.5
    return (n * 255 + 0.5).astype(np.uint8)

N = 256
skin_h = 0.6 * fbm(N, 1.6, 1) + 0.5 * fbm(N, 0.9, 2) + 0.8 * (1.0 - np.clip(worley(N, 48, 3) * 2.2, 0, 1))
Image.fromarray(normal_from_height(skin_h, 2.2)).save(os.path.join(OUT, "skin_detail_n.png"))
M = 128
yy, xx = np.mgrid[0:M, 0:M]
weave = np.sin(xx / M * 2 * np.pi * 16) * np.sin(yy / M * 2 * np.pi * 16) + 0.5 * np.sin((xx + yy) / M * 2 * np.pi * 8)
cloth_h = weave * 0.6 + 0.5 * fbm(M, 1.0, 5)
Image.fromarray(normal_from_height(cloth_h, 1.4)).save(os.path.join(OUT, "cloth_detail_n.png"))
bag = 0.5 + 0.12 * cloth_h
bag = np.clip(bag, 0, 1)
Image.fromarray((np.stack([bag] * 3, -1) * 255).astype(np.uint8)).save(os.path.join(OUT, "bag_detail.png"))
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/people/tex/%s"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.8
compress/hdr_compression=1
compress/normal_map=%d
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""
for name, nm in (("skin_detail_n.png", 1), ("cloth_detail_n.png", 1), ("bag_detail.png", 0)):
    open(os.path.join(OUT, name + ".import"), "w").write(IMPORT % (name, nm))
print("shared textures ok")
