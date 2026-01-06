"""Image processing utility functions."""


def calculate_aspect_ratio(width: int, height: int) -> float:
    """Calculate the aspect ratio of an image.

    Args:
        width: Image width in pixels
        height: Image height in pixels

    Returns:
        Aspect ratio as a float (width / height)

    Raises:
        ValueError: If width or height is not positive
    """
    if width <= 0 or height <= 0:
        raise ValueError("Width and height must be positive integers")
    return width / height


def resize_dimensions(width: int, height: int, max_size: int) -> tuple[int, int]:
    """Calculate new dimensions to fit within max_size while preserving aspect ratio.

    Args:
        width: Original width in pixels
        height: Original height in pixels
        max_size: Maximum size for the largest dimension

    Returns:
        Tuple of (new_width, new_height)

    Raises:
        ValueError: If any dimension is not positive
    """
    if width <= 0 or height <= 0 or max_size <= 0:
        raise ValueError("All dimensions must be positive integers")

    if width <= max_size and height <= max_size:
        return (width, height)

    if width > height:
        scale = max_size / width
    else:
        scale = max_size / height

    return (int(width * scale), int(height * scale))


def rgb_to_grayscale(r: int, g: int, b: int) -> int:
    """Convert RGB values to grayscale using luminosity method.

    Args:
        r: Red component (0-255)
        g: Green component (0-255)
        b: Blue component (0-255)

    Returns:
        Grayscale value (0-255)

    Raises:
        ValueError: If any component is outside 0-255 range
    """
    for val, name in [(r, 'r'), (g, 'g'), (b, 'b')]:
        if not 0 <= val <= 255:
            raise ValueError(f"{name} must be between 0 and 255")

    # Luminosity method: 0.21R + 0.72G + 0.07B
    return int(0.21 * r + 0.72 * g + 0.07 * b)


def is_valid_resolution(width: int, height: int, min_width: int = 1, min_height: int = 1) -> bool:
    """Check if resolution meets minimum requirements.

    Args:
        width: Image width in pixels
        height: Image height in pixels
        min_width: Minimum required width (default: 1)
        min_height: Minimum required height (default: 1)

    Returns:
        True if resolution is valid, False otherwise
    """
    return width >= min_width and height >= min_height
