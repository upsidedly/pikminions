#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Matthew Williams

"""Build the isolated native bubble fixture; launch it with Computer Use or Finder."""
from pathlib import Path
import plistlib
import platform
import subprocess

root=Path(__file__).resolve().parents[1]
subprocess.run(["swift","build"],cwd=root,check=True)
binary_dir=Path(subprocess.check_output(["swift","build","--show-bin-path"],cwd=root,text=True).strip())
bundle=root/"dist/PikminionsBubbleFixture.app"
executable=bundle/"Contents/MacOS/BubbleFixture"
executable.parent.mkdir(parents=True,exist_ok=True)
objects=[*binary_dir.joinpath("Antille.build").glob("*.o"),
         *(p for p in binary_dir.joinpath("PikminionsApp.build").glob("*.o") if p.name!="PikminionsApplication.swift.o")]
subprocess.run(["swiftc","-parse-as-library","-swift-version","6",
                "-target",f"{platform.machine()}-apple-macosx14.0",
                "-I",str(binary_dir/"Modules"),"-I",str(root/"Sources/CSQLite"),
                str(root/"Tests/NativeFixtures/BubbleFixture.swift"),
                *map(str,objects),"-lsqlite3","-o",str(executable)],check=True)
info={"CFBundleIdentifier":"dev.upsided.pikminions.bubble.fixture",
      "CFBundleName":"Pikminions Bubble Fixture","CFBundleExecutable":"BubbleFixture",
      "CFBundlePackageType":"APPL","LSMinimumSystemVersion":"14.0","LSUIElement":True,
      "NSHighResolutionCapable":True}
with (bundle/"Contents/Info.plist").open("wb") as output:plistlib.dump(info,output)
subprocess.run(["codesign","--force","--sign","-",str(bundle)],check=True)
print(bundle)
