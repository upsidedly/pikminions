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
parser.add_argument("--spawn-check",action="store_true")
parser.add_argument("--sleep",action="store_true")
parser.add_argument("--sleep-check",action="store_true")
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
build=["swift","build","--jobs","2"]
module_cache=root.parent/"QOL/Antille/.build/arm64-apple-macosx/debug/ModuleCache"
cache_flags=["-module-cache-path",str(module_cache)] if module_cache.is_dir() else []
for flag in cache_flags:build += ["-Xswiftc",flag]
subprocess.run(build,cwd=root,check=True)
binary_dir=Path(subprocess.check_output(["swift","build","--show-bin-path"],cwd=root,text=True).strip())
objects=[*binary_dir.joinpath("Antille.build").glob("*.o"),
         *(p for p in binary_dir.joinpath("PikminionsApp.build").glob("*.o") if p.name!="PikminionsApplication.swift.o")]
sleep=args.sleep or args.sleep_check
bundle=root/("dist/PikminionsSleepFixture.app" if sleep else "dist/PikminionsSizeFixture.app")
executable=bundle/"Contents/MacOS/HeadSizeFixture"
executable.parent.mkdir(parents=True,exist_ok=True)
subprocess.run(["swiftc","-parse-as-library","-swift-version","6","-target",f"{platform.machine()}-apple-macosx14.0",*cache_flags,
                "-I",str(binary_dir/"Modules"),"-I",str(root/"Sources/CSQLite"),
                str(root/"Tests/NativeFixtures/HeadSizeFixture.swift"),*map(str,objects),"-lsqlite3","-o",str(executable)],check=True)
info={"CFBundleIdentifier":"dev.upsided.pikminions."+("sleep" if sleep else "size")+".fixture","CFBundleName":"Pikminions Sleep Fixture" if sleep else "Pikminions Size Fixture",
      "CFBundleExecutable":"HeadSizeFixture","CFBundlePackageType":"APPL","LSMinimumSystemVersion":"14.0",
      "NSHighResolutionCapable":True,"LSUIElement":True}
with (bundle/"Contents/Info.plist").open("wb") as output:plistlib.dump(info,output)
subprocess.run(["codesign","--force","--sign","-",str(bundle)],check=True)
if args.check:subprocess.run([str(executable),"--check"],check=True,timeout=15)
if args.menu_check:subprocess.run([str(executable),"--menu-check"],check=True,timeout=15)
if args.spawn_check:subprocess.run([str(executable),"--spawn-check"],check=True,timeout=15)
if args.sleep_check:subprocess.run([str(executable),"--sleep-check","--fixture"],check=True,timeout=15)
print(bundle)
