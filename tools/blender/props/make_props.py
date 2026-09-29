"""Headless generator for the station props.

  blender -b --factory-startup -P tools/blender/props/make_props.py -- [prop names...]     (no names = all)

Textures are produced beforehand by proptex_tiles.py / proptex_decals.py / posters.py (build/venv/bin/python).
One function per prop lives in props_*.py and registers itself via @prop(...). Shared helpers: propmesh.py (bevelled boxes,
lathe, tubes, prisms, decals), propmats.py (material library), propcore.py (build context, export).
"""
import os, sys, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib
import propcore
for m in ('props_gates', 'props_furniture', 'props_wall', 'props_adverts', 'props_retail'):
    try:
        importlib.import_module(m)
    except ModuleNotFoundError as e:
        if e.name != m:
            raise
        print('(skipping missing module %s)' % m)


def main():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    names = [a for a in args if a in propcore.REGISTRY] or list(propcore.ORDER)
    bad = [a for a in args if a not in propcore.REGISTRY]
    if bad:
        print('unknown props:', bad, 'known:', list(propcore.ORDER))
    allstats = {}
    for n in names:
        allstats[n] = propcore.build_prop(n)
    print('DONE', len(names), 'props; total tris', sum(s['tris'] for s in allstats.values()))


main()
