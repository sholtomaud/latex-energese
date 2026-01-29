import sys
import math
from PIL import Image, ImageChops

def calculate_rmse(im1, im2):
    # If sizes differ, resize im2 to match im1
    if im1.size != im2.size:
        print(f"Warning: resizing second image from {im2.size} to {im1.size}")
        im2 = im2.resize(im1.size, Image.Resampling.LANCZOS)

    # Convert to RGB if needed
    if im1.mode != 'RGB':
        im1 = im1.convert('RGB')
    if im2.mode != 'RGB':
        im2 = im2.convert('RGB')

    diff = ImageChops.difference(im1, im2)

    # Calculate RMSE
    # We sum the squares of differences for each pixel/channel
    # but ImageChops.difference gives absolute difference.
    # A more accurate way with Pillow:
    h = diff.histogram()
    # histogram returns counts for each of 0-255 for R, then G, then B
    sum_of_squares = 0
    for i in range(len(h)):
        # i % 256 is the pixel difference value (0-255)
        # h[i] is the number of pixels with that difference
        sum_of_squares += h[i] * ((i % 256) ** 2)

    # Total samples = width * height * 3 channels
    rms = math.sqrt(sum_of_squares / float(im1.size[0] * im1.size[1] * 3))
    return rms / 255.0

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 compare_images.py image1.png image2.png [diff.png]")
        sys.exit(1)

    path1 = sys.argv[1]
    path2 = sys.argv[2]

    try:
        im1 = Image.open(path1)
        im2 = Image.open(path2)
    except Exception as e:
        print(f"Error opening images: {e}")
        sys.exit(1)

    rmse = calculate_rmse(im1, im2)
    print(f"RMSE: {rmse:.6f}")

    if len(sys.argv) >= 4:
        # Create a visual diff
        diff = ImageChops.difference(im1.convert('RGB'), im2.resize(im1.size).convert('RGB'))
        diff.save(sys.argv[3])

    if rmse < 0.05:
        print("Result: PASS")
        sys.exit(0)
    else:
        print("Result: FAIL")
        sys.exit(1)

if __name__ == "__main__":
    main()
