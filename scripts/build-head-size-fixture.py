#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Matthew Williams

"""Build or check actual desktop views/panels with isolated sample agents."""
from pathlib import Path
import argparse
import platform
import plistlib
import subprocess

parser=argparse.ArgumentParser()
parser.add_argument("--check",action="store_true")
parser.add_argument("--menu-check",action="store_true")
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
subprocess.run(["swift","build"],cwd=root,check=True)
binary_dir=Path(subprocess.check_output(["swift","build","--show-bin-path"],cwd=root,text=True).strip())
objects=[*binary_dir.joinpath("Antille.build").glob("*.o"),
         *(p for p in binary_dir.joinpath("PikminionsApp.build").glob("*.o") if p.name!="PikminionsApplication.swift.o")]
bundle=root/"dist/PikminionsSizeFixture.app"
executable=bundle/"Contents/MacOS/HeadSizeFixture"
executable.parent.mkdir(parents=True,exist_ok=True)
subprocess.run(["swiftc","-parse-as-library","-swift-version","6","-target",f"{platform.machine()}-apple-macosx14.0",
                "-I",str(binary_dir/"Modules"),"-I",str(root/"Sources/CSQLite"),
                str(root/"Tests/NativeFixtures/HeadSizeFixture.swift"),*map(str,objects),"-lsqlite3","-o",str(executable)],check=True)
info={"CFBundleIdentifier":"dev.upsided.pikminions.size.fixture","CFBundleName":"Pikminions Size Fixture",
      "CFBundleExecutable":"HeadSizeFixture","CFBundlePackageType":"APPL","LSMinimumSystemVersion":"14.0",
      "NSHighResolutionCapable":True,"LSUIElement":True}
with (bundle/"Contents/Info.plist").open("wb") as output:plistlib.dump(info,output)
subprocess.run(["codesign","--force","--sign","-",str(bundle)],check=True)
if args.check:subprocess.run([str(executable),"--check"],check=True,timeout=15)
if args.menu_check:subprocess.run([str(executable),"--menu-check"],check=True,timeout=15)
print(bundle)
