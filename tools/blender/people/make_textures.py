"""Build the per-character texture set (skin, outfit atlas, face atlas, hair) from the MakeHuman asset packs.

    build/people_tmp/venv/bin/python tools/blender/people/make_textures.py [id ...] [--outdir assets/people]

Outputs assets/people/tex/person_NN_{skin,outfit,outfit_n,face,hair}.png + Godot .import stubs (VRAM compressed).
Colour conventions (all in the Godot shaders):
  outfit / hair textures store  detail = linear_albedo / mean_albedo * 0.5  (sRGB encoded) so the shader can do
  albedo = tex * 2 * tint  and tint defaults to the mean colour of the garment (or the palette colour we want).
"""
import sys, os, json, glob, hashlib
import numpy as np
from PIL import Image, PngImagePlugin
PngImagePlugin.MAX_TEXT_CHUNK = 1 << 28
Image.MAX_IMAGE_PIXELS = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import people_spec as PS

OUT = os.path.join(PS.PROJECT, "assets", "people")
ids = []
argv = sys.argv[1:]
i = 0
while i < len(argv):
    if argv[i] == "--outdir":
        OUT = argv[i + 1]; i += 2; continue
    ids.append(argv[i]); i += 1

SKIN_RES = int(os.environ.get("PEOPLE_SKIN_RES", "1024"))
HAIR_RES = int(os.environ.get("PEOPLE_HAIR_RES", "1024"))
D = PS.MPFB_DATA


def to_lin(x):
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)


def to_srgb(x):
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def open_image(path):
    try:
        return Image.open(path)
    except Exception:
        import io
        d = open(path, "rb").read()
        out = bytearray(d[:8])
        i = 8
        while i < len(d):
            ln = int.from_bytes(d[i:i + 4], "big")
            t = d[i + 4:i + 8]
            if t not in (b"zTXt", b"tEXt", b"iTXt", b"iCCP", b"eXIf"):
                out += d[i:i + 12 + ln]
            i += 12 + ln
        return Image.open(io.BytesIO(bytes(out)))


def load_rgba(path, size=None, resample=Image.LANCZOS):
    im = open_image(path)
    if im.mode == "P":
        im = im.convert("RGBA")
    im = im.convert("RGBA")
    if size is not None and im.size != tuple(size):
        # premultiplied resize so transparent black does not bleed into the colour
        a = np.asarray(im).astype(np.float32) / 255.0
        alpha = a[..., 3:4]
        rgb = a[..., :3]
        # colour under transparent pixels -> mean colour of visible pixels
        vis = alpha[..., 0] > 0.5
        if vis.any() and (~vis).any():
            m = rgb[vis].mean(axis=0)
            rgb = np.where(vis[..., None], rgb, m)
        im = Image.fromarray((np.concatenate([rgb, alpha], -1) * 255 + 0.5).astype(np.uint8), "RGBA")
        im = im.resize(tuple(size), resample)
    return np.asarray(im).astype(np.float32) / 255.0


def save_png(arr, path, rgba=False):
    a = np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)
    im = Image.fromarray(a, "RGBA" if rgba else "RGB")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, optimize=False)


IMPORT_TMPL = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/people/tex/%(name)s"

[params]

compress/mode=2
compress/high_quality=%(hq)s
compress/lossy_quality=0.8
compress/hdr_compression=1
compress/normal_map=%(nm)d
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=%(fab)s
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


HQ = os.environ.get("PEOPLE_HQ", "0") == "1"


def write_import(path, normal=False, alpha=False, hq=None):
    hq = HQ if hq is None else hq
    name = os.path.basename(path)
    with open(path + ".import", "w") as f:
        f.write(IMPORT_TMPL % dict(name=name, hq="true" if hq else "false", nm=1 if normal else 0,
                                   fab="true" if alpha else "false"))


def tile_px(tile, size):
    u0, v0, su, sv = tile
    W, H = size
    x0 = int(round(u0 * W))
    w = int(round(su * W))
    h = int(round(sv * H))
    y0 = int(round((1.0 - (v0 + sv)) * H))   # image y down
    return x0, y0, w, h


def thick_alpha(rgba, size, gain):
    """downscale an RGBA strand texture keeping strands visible: max-filter the alpha, resize, boost"""
    from PIL import ImageFilter
    a = Image.fromarray((rgba[..., 3] * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(3))
    a = a.resize(tuple(size), Image.BOX)
    a = np.clip(np.asarray(a).astype(np.float32) / 255.0 * gain, 0, 1)
    vis = rgba[..., 3] > 0.3
    col = rgba[..., :3][vis].mean(axis=0) if vis.any() else np.zeros(3, np.float32)
    rgb = np.broadcast_to(col, tuple(size[::-1]) + (3,)).astype(np.float32)
    return np.concatenate([rgb, a[..., None]], -1)


def garment_files(item):
    d = PS.find_clothes_dir(item)
    mhclo = glob.glob(os.path.join(d, "*.mhclo"))[0]
    mat = PS.parse_mhclo_material(mhclo)
    mhmat = os.path.normpath(os.path.join(d, mat))
    m = PS.parse_mhmat(mhmat)
    mdir = os.path.dirname(mhmat)

    def f(key):
        if key in m:
            p = os.path.join(mdir, m[key])
            if os.path.exists(p):
                return p
        return None
    return dict(diffuse=f("diffuseTexture"), normal=f("normalmapTexture"), ao=f("aomapTexture"), mhmat=m,
                transparent=m.get("transparent", "False").lower() == "true")


def coverage_mask(rgba):
    a = rgba[..., 3]
    if (a < 0.5).mean() > 0.02:
        return a > 0.5
    return rgba[..., :3].max(axis=-1) > 0.03


def garment_tile(item, tw, th, recolor, want_normal=True):
    gf = garment_files(item)
    rgba = load_rgba(gf["diffuse"], (tw, th))
    rgb = rgba[..., :3]
    lin = to_lin(rgb)
    if gf["ao"]:
        ao = load_rgba(gf["ao"], (tw, th))[..., :3].mean(axis=-1, keepdims=True)
        lin = lin * (0.35 + 0.65 * ao)  # bake a soft AO into the albedo
    cov = coverage_mask(rgba)
    if cov.sum() < 50:
        cov = np.ones_like(cov)
    mean = lin[cov].mean(axis=0)
    mean = np.maximum(mean, 1e-4)
    if recolor:
        lum = lin @ np.array([0.2126, 0.7152, 0.0722], np.float32)
        mlum = max(float(lum[cov].mean()), 1e-4)
        ratio = np.repeat((lum / mlum)[..., None], 3, axis=-1)
        stored = to_srgb(np.clip(ratio * 0.5, 0, 1))
    else:
        stored = to_srgb(np.clip(lin * 0.5, 0, 1))
    # fill uncovered texels with neutral value so mips of padding do not go black
    stored = np.where(cov[..., None], stored, to_srgb(np.array(0.5 * 0.5)))
    normal = None
    if gf["normal"] and want_normal:
        n = load_rgba(gf["normal"], (tw, th))[..., :3]
        normal = n
    return stored, normal, to_srgb(mean), gf


def bag_tile(kind, seed, tw, th):
    rng = np.random.RandomState(seed)
    cols = [(0.05, 0.05, 0.06), (0.08, 0.10, 0.18), (0.20, 0.20, 0.22), (0.24, 0.15, 0.08), (0.13, 0.17, 0.10),
            (0.35, 0.10, 0.10), (0.12, 0.12, 0.13), (0.42, 0.30, 0.16)]
    if kind == "briefcase":
        cols = [(0.05, 0.04, 0.04), (0.20, 0.11, 0.06), (0.11, 0.08, 0.06), (0.06, 0.06, 0.08)]
    c = np.array(cols[rng.randint(len(cols))])
    yy, xx = np.mgrid[0:th, 0:tw]
    weave = 0.5 + 0.5 * np.sin(xx * 1.6) * np.sin(yy * 1.6)
    noise = rng.rand(th, tw)
    v = 0.86 + 0.10 * weave + 0.06 * noise
    lin = to_lin(c)[None, None, :] * v[..., None]
    return to_srgb(np.clip(lin * 0.5, 0, 1)), c


def build_char(spec):
    cid = spec["id"]
    tex_dir = os.path.join(OUT, "tex")
    info = dict(id=cid)
    # ------------------------------------------------------------ skin
    skin_dir = os.path.join(D, "skins", spec["skin"])
    mhmat = glob.glob(os.path.join(skin_dir, "*.mhmat"))[0]
    sm = PS.parse_mhmat(mhmat)
    skin_png = os.path.join(skin_dir, sm["diffuseTexture"])
    im = load_rgba(skin_png, (SKIN_RES, SKIN_RES))[..., :3]
    if spec["tone"]:
        lin = to_lin(im) * np.array(spec["tone"])[None, None, :] ** 2.2
        lum = (lin @ np.array([0.2126, 0.7152, 0.0722], np.float32))[..., None]
        lin = lin * 0.8 + lum * 0.2          # slightly desaturate: multiplying a bronze skin gets too orange-red
        im = to_srgb(lin)
    p = os.path.join(tex_dir, cid + "_skin.png")
    save_png(im, p)
    write_import(p)
    info["skin_src"] = spec["skin"]
    mean_skin = to_srgb(to_lin(im).mean(axis=(0, 1)))
    info["skin_mean"] = [float(x) for x in mean_skin]
    # ------------------------------------------------------------ face atlas
    fsz = PS.FACE_ATLAS["size"]
    face = np.zeros((fsz[1], fsz[0], 4), np.float32)
    def put(tile, rgba_arr):
        x0, y0, w, h = tile_px(tile, fsz)
        face[y0:y0 + h, x0:x0 + w] = rgba_arr
    ft = PS.FACE_ATLAS["tiles"]
    ecol = spec.get("eyes", "brown")
    EYE_ALIAS = {"brown": ("brownlight", 0.62), "darkbrown": ("brownlight", 0.45), "hazel": ("brownlight", 1.0)}
    eye_dark = 1.0
    src_col = ecol
    if ecol in EYE_ALIAS:
        src_col, eye_dark = EYE_ALIAS[ecol]
    eye_mat = os.path.join(D, "eyes", "materials", src_col + ".mhmat")
    ep = os.path.join(D, "eyes", "materials", PS.parse_mhmat(eye_mat)["diffuseTexture"])
    x0, y0, w, h = tile_px(ft["eyes"], fsz)
    e = load_rgba(ep, (w, h))
    e[..., 3] = 1.0
    el = to_lin(e[..., :3])
    elum = (el @ np.array([0.2126, 0.7152, 0.0722], np.float32))[..., None]
    sat = np.max(el, -1, keepdims=True) - np.min(el, -1, keepdims=True)
    k = np.clip(sat * 3.0, 0, 1) * 0.42          # only the coloured iris, not the sclera
    el = el * (1 - k) + elum * k
    iris = np.clip(sat * 3.0, 0, 1)
    el = el * (1 - (1 - eye_dark) * iris)                  # darker iris for brown eyes
    el = el * (1 + 0.38 * (1 - iris))                      # brighter sclera
    e[..., :3] = to_srgb(np.clip(el, 0, 1))
    put(ft["eyes"], e)
    lash_dir = os.path.join(D, "eyelashes", spec["lashes"])
    lp = glob.glob(os.path.join(lash_dir, "*.png"))[0]
    x0, y0, w, h = tile_px(ft["lashes"], fsz)
    put(ft["lashes"], thick_alpha(load_rgba(lp), (w, h), 1.6))
    brow_dir = os.path.join(D, "eyebrows", spec["brows"])
    bp = glob.glob(os.path.join(brow_dir, "*.png"))[0]
    x0, y0, w, h = tile_px(ft["brows"], fsz)
    put(ft["brows"], thick_alpha(load_rgba(bp), (w, h), 2.5))
    if spec.get("glasses"):
        gf = garment_files(spec["glasses"])
        x0, y0, w, h = tile_px(ft["glasses"], fsz)
        g = load_rgba(gf["diffuse"], (w, h), resample=Image.NEAREST if open_image(gf["diffuse"]).size[0] <= 64 else Image.LANCZOS)
        put(ft["glasses"], g)
    # face atlas stored as plain sRGB colour + alpha (eyes/brows/lashes/glasses)
    p = os.path.join(tex_dir, cid + "_face.png")
    save_png(face, p, rgba=True)
    write_import(p, alpha=True)
    # ------------------------------------------------------------ hair
    hair_tint = None
    if spec["hair"]:
        hd = os.path.join(D, "hair", spec["hair"])
        hmhclo = glob.glob(os.path.join(hd, "*.mhclo"))[0]
        hm = PS.parse_mhmat(os.path.join(hd, PS.parse_mhclo_material(hmhclo)))
        hp = os.path.join(hd, hm["diffuseTexture"])
        h = load_rgba(hp, (HAIR_RES, HAIR_RES))
        lin = to_lin(h[..., :3])
        lum = lin @ np.array([0.2126, 0.7152, 0.0722], np.float32)
        vis = h[..., 3] > 0.5
        mean = max(float(lum[vis].mean()), 1e-4) if vis.any() else 0.2
        detail = np.clip(lum / mean * 0.5, 0, 1)
        detail = np.where(vis, detail, 0.25)
        d = to_srgb(detail)
        out = np.stack([d, d, d, h[..., 3]], -1)
        p = os.path.join(tex_dir, cid + "_hair.png")
        save_png(out, p, rgba=True)
        write_import(p, alpha=True)
        hair_tint = PS.HAIR_COLOURS[spec["hair_col"]]
    # ------------------------------------------------------------ outfit atlas
    layout = PS.layout_for(spec["garments"])
    W, H = layout["size"]
    atlas = np.full((H, W, 3), to_srgb(np.array(0.25)), np.float32)
    natlas = np.zeros((H, W, 3), np.float32)
    natlas[..., 0] = 0.5; natlas[..., 1] = 0.5; natlas[..., 2] = 1.0
    have_normal = False
    slots = {}
    items = [(it, sl, col) for it, sl, col in spec["garments"]]
    if spec.get("hat"):
        items.append((spec["hat"], "hat", None))
    for item, slot, col in items:
        tile = layout["tiles"][slot]
        x0, y0, tw, th = tile_px(tile, layout["size"])
        recolor = col is not None
        stored, normal, mean_srgb, gf = garment_tile(item, tw, th, recolor)
        atlas[y0:y0 + th, x0:x0 + tw] = stored
        if normal is not None:
            natlas[y0:y0 + th, x0:x0 + tw] = normal
            have_normal = True
        tint = PS.CLOTH_COLOURS[col] if recolor else None
        slots[slot] = dict(item=item, recolor=recolor, default_tint=list(tint) if tint else None,
                           native_mean=[float(x) for x in mean_srgb], normal=bool(normal is not None))
    if spec.get("bag"):
        tile = layout["tiles"]["extra"]
        x0, y0, tw, th = tile_px(tile, layout["size"])
        st, c = bag_tile(spec["bag"], spec["index"] * 7 + 3, tw, th)
        atlas[y0:y0 + th, x0:x0 + tw] = st
        slots["extra"] = dict(item="bag:" + spec["bag"], recolor=False, default_tint=None,
                              native_mean=[float(x) for x in to_srgb(c)])
    p = os.path.join(tex_dir, cid + "_outfit.png")
    save_png(atlas, p)
    write_import(p)
    if have_normal:
        p = os.path.join(tex_dir, cid + "_outfit_n.png")
        save_png(natlas, p)
        write_import(p, normal=True)
    info.update(slots=slots, has_normal=have_normal, atlas_size=[W, H], layout="main" if layout is PS.LAYOUT_MAIN else "split",
                hair_tint=list(hair_tint) if hair_tint else None, eyes=ecol)
    return info


def main():
    specs = PS.SPECS
    if ids:
        sel = set(ids)
        specs = [s for s in specs if s["id"] in sel or str(s["index"]) in sel]
    allinfo = {}
    for sp in specs:
        print("TEX", sp["id"], sp["name"], flush=True)
        allinfo[sp["id"]] = build_char(sp)
        with open(os.path.join(OUT, "tex", sp["id"] + ".tex.json"), "w") as f:
            json.dump(allinfo[sp["id"]], f, indent=1)


main()
