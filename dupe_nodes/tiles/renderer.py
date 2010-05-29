#!/usr/bin/env python
# Source is GPL, credit goes to Nicolas Pouillon
# comments goes to sylvain letuffe org (" " are replaced by @ and . )
# fichier execute par mod_python. handle() est le point d'entree.

import os, os.path
from gen_tile import MapMaker

zmax=20

def handle(req):
    from mod_python import apache, util
    path = req.path_info
    renderer = MapMaker("/home/matt/styles/dupe_nodes.xml", zmax)

    # strip .png
    new_path, ext = path[7:].split(".", 1)
    style, z, x, y = new_path.split('/', 4)

    req.status = 200
    req.content_type = 'image/png'
    z = int(z)
    x = int(x)
    y = int(y)
    #req.content_type = 'text/plain'
    #req.write(renderers[style])
    #return apache.OK
    if z<7:
        cache=True
    else:
        cache=False
    req.write(renderer.genTile(x, y, z, ext, cache))
    return apache.OK
