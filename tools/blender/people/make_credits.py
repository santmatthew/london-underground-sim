"""Generate assets/people/CREDITS.txt from the MPFB pack metadata of every asset used by the specs."""
import os, sys, json, glob
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import people_spec as PS
D = PS.MPFB_DATA
packs = {}
for f in glob.glob(D + "/packs/*.json"):
    packs[os.path.basename(f)[:-5]] = json.load(open(f))
def lookup(name):
    for pk, d in packs.items():
        if name in d:
            return pk, d[name]
    return None, None
used = {}
def use(kind, name):
    if not name:
        return
    used.setdefault((kind, name), None)
for sp in PS.SPECS:
    for it, sl, col in sp["garments"]:
        use("clothes", it)
    use("skin", sp["skin"]); use("hair", sp["hair"]); use("eyebrows", sp["brows"]); use("eyelashes", sp["lashes"])
    use("glasses", sp["glasses"]); use("hats", sp["hat"]); use("eyes", sp["eyes"])
lines = []
lines.append("CREDITS for assets/people (crowd characters)")
lines.append("=" * 60)
lines.append("")
lines.append("Base human mesh, rig weights, targets: MakeHuman / MPFB (Data Collection AB, Joel Palmius, Jonas Hauquier et al.) - CC0.")
lines.append("  https://static.makehumancommunity.org/ , https://github.com/makehumancommunity/mpfb2")
lines.append("Motion capture: Carnegie Mellon University Motion Capture Database (mocap.cs.cmu.edu) - free for all uses;")
lines.append("  BVH conversion by B. Hodgins / cgspeed, distributed at https://github.com/una-dinosauria/cmu-mocap.")
lines.append("  Data used: subjects 02 07 08 12 14 16 35 40 69 77 (walk / stand / sit / turn clips), retargeted by tools/blender/people.")
lines.append("Bags, procedural skin/cloth detail textures, shaders, animation retargeting, scripts: generated in this project (CC0).")
lines.append("")
lines.append("Community assets used (name | author | licence | pack | source)")
lines.append("-" * 60)
ccby = []
for (kind, name) in sorted(used):
    pk, meta = lookup(name)
    if meta is None:
        # system assets (eyes, eyebrows, base hair) -> makehuman_system_assets pack
        lines.append("%s %s | MakeHuman system assets | CC0" % (kind, name))
        continue
    lic = meta.get("license", "?")
    line = "%s %s | %s | %s | pack %s | %s" % (kind, name, meta.get("author", "?"), lic, pk, meta.get("source", ""))
    lines.append(line)
    if "by" in lic.lower():
        ccby.append((kind, name, meta.get("author", "?"), lic))
packs_used = sorted({lookup(n)[0] for (k, n) in used if lookup(n)[0]})
ccby_packs = sorted({lookup(c[1])[0] for c in ccby})
lines.append("")
lines.append("Packs used: " + ", ".join(packs_used))
lines.append("CC-BY packs among them (attribution required): " + ", ".join(ccby_packs))
lines.append("")
lines.append("CC-BY assets require attribution (Creative Commons Attribution 4.0/3.0): %d used, authors:" % len(ccby))
for a in sorted({c[2] for c in ccby}):
    lines.append("  - " + a)
out = os.path.join(PS.PROJECT, "assets", "people", "CREDITS.txt")
open(out, "w").write("\n".join(lines) + "\n")
print("wrote", out, len(used), "assets,", len(ccby), "CC-BY")
