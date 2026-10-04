#!/usr/bin/env python3
"""Package a macOS App without AppleDouble files or extended attributes."""
import argparse
import os
from pathlib import Path
import tempfile
import zipfile

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    output = args.output.resolve()
    if not app.is_dir() or app.suffix != ".app":
        parser.error("app must be an existing .app directory")
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=output.parent, suffix=".zip.tmp")
    os.close(descriptor)
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED,
                             compresslevel=9) as archive:
            for path in [app, *sorted(app.rglob("*"))]:
                relative = path.relative_to(app)
                if any(part == "__MACOSX" or part == ".DS_Store" or
                       part.startswith("._") for part in relative.parts):
                    continue
                if path.is_symlink():
                    raise ValueError("symbolic links are not supported by this package")
                # zipfile writes contents and Unix modes, not filesystem xattrs.
                archive.write(path, (Path(app.name) / relative).as_posix())
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None:
                raise ValueError("archive integrity check failed")
            if archive.comment or any(info.extra or info.comment or
               "__MACOSX" in info.filename.split("/") or
               Path(info.filename).name.startswith("._")
               for info in archive.infolist()):
                raise ValueError("unexpected archive metadata")
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print("Packaged: " + output.name)

if __name__ == "__main__":
    main()
