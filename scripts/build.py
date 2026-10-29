#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Matthew Williams

from pathlib import Path
import argparse, plistlib, shutil, subprocess
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument("--release",action="store_true")
parser.add_argument("--fixture",action="store_true")
args=parser.parse_args()
configuration="release" if args.release else "debug"
subprocess.run(["swift","build","-c",configuration],cwd=root,check=True)
binary_dir=Path(subprocess.check_output(["swift","build","-c",configuration,"--show-bin-path"],cwd=root,text=True).strip())
subprocess.run([str(binary_dir/"PikminionsApp"),"--check","--fixture"],check=True)
art=root/"dist/art"
subprocess.run([str(binary_dir/"PikminionsApp"),"--export-art",str(art),"--fixture"],check=True)
bundle=root/("dist/PikminionsFixture.app" if args.fixture else "dist/Pikminions.app")
(bundle/"Contents/MacOS").mkdir(parents=True,exist_ok=True)
resources=bundle/"Contents/Resources";resources.mkdir(parents=True,exist_ok=True)
temporary=bundle/"Contents/MacOS/Pikminions.new"
shutil.copy2(binary_dir/"PikminionsApp",temporary)
temporary.replace(bundle/"Contents/MacOS/Pikminions")
iconset=root/"dist/Pikminions.iconset";iconset.mkdir(parents=True,exist_ok=True)
for size in (16,32,128,256,512):
    for scale in (1,2):
        suffix="@2x" if scale==2 else ""
        subprocess.run(["sips","-z",str(size*scale),str(size*scale),str(art/"icon-1024.png"),"--out",str(iconset/f"icon_{size}x{size}{suffix}.png")],check=True,stdout=subprocess.DEVNULL)
subprocess.run(["iconutil","-c","icns",str(iconset),"-o",str(resources/"AppIcon.icns")],check=True)
docs_assets=root/"docs/assets";docs_assets.mkdir(parents=True,exist_ok=True)
shutil.copy2(art/"icon-1024.png",docs_assets/"pikminions-icon.png")
shutil.copy2(art/"pikmin-heads.png",docs_assets/"pikmin-heads.png")
info={"CFBundleIdentifier":"dev.upsided.pikminions","CFBundleName":"Pikminions","CFBundleDisplayName":"Pikminions","CFBundleExecutable":"Pikminions","CFBundleIconFile":"AppIcon","CFBundlePackageType":"APPL","CFBundleShortVersionString":"1.0.0","CFBundleVersion":"1","LSMinimumSystemVersion":"14.0","LSUIElement":True,"NSHighResolutionCapable":True}
if args.fixture:
    info["CFBundleIdentifier"]+=".fixture"
    info["CFBundleName"]="Pikminions Fixture"
    info["CFBundleDisplayName"]="Pikminions Fixture"
with (bundle/"Contents/Info.plist").open("wb") as f: plistlib.dump(info,f)
subprocess.run(["codesign","--force","--sign","-",str(bundle)],check=True)
print(bundle)
