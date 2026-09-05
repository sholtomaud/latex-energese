"""Ink-mask measurement for energese fidelity testing.

Everything here works on a binarised "ink mask": a PIL mode-'1' image in which
white means ink. Rendered output is black-on-white, so the threshold inverts it.

Pure Pillow, no numpy -- the operations that matter (thresholding, boolean
composition, histograms) all run in C, so a 300 DPI page is fast enough.

Two distinct comparisons live here, and conflating them is the mistake this
harness exists to avoid:

  * exact()  compares our render against our own approved golden. Byte-level.
    Rendering is deterministic, so any difference at all is a real change.

  * iou()    compares our render against a scan of Odum's original. Those are
    144 DPI captures with scanner artifacts and page show-through, so they are
    compared as normalised shapes with a tolerance, never pixel for pixel.
"""

from PIL import Image, ImageChops

IMAGE_MODE = "1"
DEFAULT_THRESHOLD = 128
NORMAL_SIZE = 512


def load_mask(path, threshold=DEFAULT_THRESHOLD):
    """Load an image as an ink mask: white where the source has ink."""
    grey = Image.open(path).convert("L")
    return grey.point(lambda p: 255 if p < threshold else 0).convert(IMAGE_MODE)


def ink_bbox(mask):
    """Bounding box of the ink, or None for a blank image."""
    return mask.getbbox()


def ink_count(mask):
    """Number of ink pixels."""
    # A mode-'1' histogram buckets everything at 0 (background) and 255 (ink).
    return mask.histogram()[255]


def normalise(mask, size=NORMAL_SIZE):
    """Crop to the ink and rescale to a fixed square.

    This is what makes comparison against a reference scan meaningful: it
    discards absolute scale, position and margin, leaving only shape.
    """
    box = ink_bbox(mask)
    if box is None:
        return Image.new(IMAGE_MODE, (size, size), 0)
    cropped = mask.crop(box)
    # Resize in 'L' -- mode '1' has no resampling filters -- then re-threshold.
    resized = cropped.convert("L").resize((size, size), Image.LANCZOS)
    return resized.point(lambda p: 255 if p > DEFAULT_THRESHOLD else 0).convert(IMAGE_MODE)


def iou(mask_a, mask_b, size=NORMAL_SIZE):
    """Intersection over union of two normalised ink masks, in [0, 1].

    1.0 means the shapes coincide exactly after scaling. Thresholds for this
    must be calibrated against measured agreement, never guessed.
    """
    a = normalise(mask_a, size)
    b = normalise(mask_b, size)
    union = ink_count(ImageChops.logical_or(a, b))
    if union == 0:
        return 1.0
    return ink_count(ImageChops.logical_and(a, b)) / union


def solid(mask):
    """Fill a closed outline, returning the region it encloses.

    Comparing outlines directly is misleading: two identical shapes offset by a
    single pixel share almost no ink, because the ink is a thin ring. Filling
    first makes the comparison about shape rather than stroke registration.

    Implemented by flooding the background inward from the border and inverting,
    so any pixel the background cannot reach is interior.
    """
    from PIL import ImageDraw
    box = ink_bbox(mask)
    if box is None:
        return mask
    # One pixel of margin guarantees the flood has a border to start from.
    work = Image.new("L", (mask.width + 2, mask.height + 2), 255)
    work.paste(mask.convert("L").point(lambda p: 0 if p else 255), (1, 1))
    ImageDraw.floodfill(work, (0, 0), 128)
    return work.crop((1, 1, mask.width + 1, mask.height + 1)) \
               .point(lambda p: 0 if p == 128 else 255).convert(IMAGE_MODE)


def interior(mask):
    """The region a closed outline encloses, excluding the outline itself.

    Comparing interiors rather than filled shapes keeps the measure independent
    of stroke weight, which differs between a 144 dpi capture and a vector
    render and is not what conformance is asking about.
    """
    return ImageChops.logical_and(solid(mask),
                                  ImageChops.invert(mask.convert("L")).convert(IMAGE_MODE))


def shape_iou(mask_a, mask_b, size=NORMAL_SIZE):
    """Overlap of two shapes after filling and normalising, in [0, 1]."""
    return iou(solid(mask_a), solid(mask_b), size)


def geometry(mask):
    """Scale-independent descriptors of a symbol's ink.

    `aspect` is width over height of the ink bounding box. `coverage` is the
    fraction of that box which is ink, which distinguishes an outline from a
    filled shape and catches a shape that has lost an edge.
    """
    box = ink_bbox(mask)
    if box is None:
        return {"aspect": 0.0, "coverage": 0.0, "width": 0, "height": 0}
    left, top, right, bottom = box
    width, height = right - left, bottom - top
    return {
        "aspect": width / height if height else 0.0,
        "coverage": ink_count(mask) / (width * height) if width and height else 0.0,
        "width": width,
        "height": height,
    }


def exact(path_a, path_b):
    """True when two rendered PNGs are pixel-identical."""
    with open(path_a, "rb") as fa, open(path_b, "rb") as fb:
        return fa.read() == fb.read()


def diff_image(path_actual, path_golden, path_out):
    """Write a three-panel diff: golden, actual, and changed pixels in red.

    Returns the number of differing pixels.
    """
    golden = Image.open(path_golden).convert("RGB")
    actual = Image.open(path_actual).convert("RGB")

    # Sizes can differ when a change alters the bounding box; pad both to the
    # union so the panels line up and the size change is itself visible.
    width = max(golden.width, actual.width)
    height = max(golden.height, actual.height)
    canvas_g = Image.new("RGB", (width, height), "white")
    canvas_a = Image.new("RGB", (width, height), "white")
    canvas_g.paste(golden, (0, 0))
    canvas_a.paste(actual, (0, 0))

    delta = ImageChops.difference(canvas_g, canvas_a).convert("L")
    changed = delta.point(lambda p: 255 if p > 16 else 0).convert(IMAGE_MODE)
    changed_count = ink_count(changed)

    # Overlay the changes on the actual render so they can be located.
    highlight = canvas_a.copy()
    highlight.paste(Image.new("RGB", (width, height), (220, 20, 60)), (0, 0), changed)

    gap = 8
    sheet = Image.new("RGB", (width * 3 + gap * 2, height), "white")
    sheet.paste(canvas_g, (0, 0))
    sheet.paste(canvas_a, (width + gap, 0))
    sheet.paste(highlight, (width * 2 + gap * 2, 0))
    sheet.save(path_out)
    return changed_count
