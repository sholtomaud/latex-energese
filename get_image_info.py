import sys
from PIL import Image
import os

def main():
    directory = "reference-images"
    for filename in sorted(os.listdir(directory)):
        if filename.endswith(".png"):
            path = os.path.join(directory, filename)
            with Image.open(path) as img:
                width, height = img.size
                mode = img.mode
                print(f"{filename}: {width}x{height}, {mode}")

if __name__ == "__main__":
    main()
