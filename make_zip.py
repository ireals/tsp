"""Create a Magisk/KernelSU compatible module zip."""
import zipfile
import os

MODULE_DIR = os.path.join(os.path.dirname(__file__), "module")
OUTPUT_ZIP = os.path.join(os.path.dirname(__file__), "tee-simulator-plus-v1.0.0.zip")

EXCLUDE_DIRS = {"native"}
EXCLUDE_FILES = {".gitkeep"}


def main():
    if os.path.exists(OUTPUT_ZIP):
        os.remove(OUTPUT_ZIP)

    with zipfile.ZipFile(OUTPUT_ZIP, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(MODULE_DIR):
            # Skip excluded directories
            dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]

            for filename in files:
                if filename in EXCLUDE_FILES:
                    continue

                filepath = os.path.join(root, filename)
                arcname = os.path.relpath(filepath, MODULE_DIR).replace("\\", "/")
                zf.write(filepath, arcname)

    # Print contents
    with zipfile.ZipFile(OUTPUT_ZIP, "r") as zf:
        print(f"Created: {OUTPUT_ZIP}")
        print(f"Size: {os.path.getsize(OUTPUT_ZIP)} bytes")
        print(f"Entries: {len(zf.namelist())}")
        print("---")
        for name in sorted(zf.namelist()):
            info = zf.getinfo(name)
            print(f"  {name} ({info.file_size} bytes)")


if __name__ == "__main__":
    main()
