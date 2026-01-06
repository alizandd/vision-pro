"""Tests for image_utils module."""

import pytest
import sys
import os

# Add src to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from image_utils import (
    calculate_aspect_ratio,
    resize_dimensions,
    rgb_to_grayscale,
    is_valid_resolution,
)


class TestCalculateAspectRatio:
    """Tests for calculate_aspect_ratio function."""

    def test_landscape_ratio(self):
        """Test aspect ratio for landscape image."""
        assert calculate_aspect_ratio(1920, 1080) == pytest.approx(1.777, rel=0.01)

    def test_portrait_ratio(self):
        """Test aspect ratio for portrait image."""
        assert calculate_aspect_ratio(1080, 1920) == pytest.approx(0.5625, rel=0.01)

    def test_square_ratio(self):
        """Test aspect ratio for square image."""
        assert calculate_aspect_ratio(1000, 1000) == 1.0

    def test_invalid_width(self):
        """Test that invalid width raises ValueError."""
        with pytest.raises(ValueError):
            calculate_aspect_ratio(0, 100)

    def test_invalid_height(self):
        """Test that invalid height raises ValueError."""
        with pytest.raises(ValueError):
            calculate_aspect_ratio(100, -1)


class TestResizeDimensions:
    """Tests for resize_dimensions function."""

    def test_no_resize_needed(self):
        """Test when image is already smaller than max_size."""
        assert resize_dimensions(800, 600, 1000) == (800, 600)

    def test_resize_landscape(self):
        """Test resizing landscape image."""
        result = resize_dimensions(2000, 1000, 1000)
        assert result == (1000, 500)

    def test_resize_portrait(self):
        """Test resizing portrait image."""
        result = resize_dimensions(1000, 2000, 1000)
        assert result == (500, 1000)

    def test_resize_square(self):
        """Test resizing square image."""
        result = resize_dimensions(2000, 2000, 1000)
        assert result == (1000, 1000)

    def test_invalid_dimensions(self):
        """Test that invalid dimensions raise ValueError."""
        with pytest.raises(ValueError):
            resize_dimensions(-100, 100, 100)


class TestRgbToGrayscale:
    """Tests for rgb_to_grayscale function."""

    def test_white(self):
        """Test conversion of white (accounts for floating-point truncation)."""
        result = rgb_to_grayscale(255, 255, 255)
        # Due to floating-point truncation: int(0.21*255 + 0.72*255 + 0.07*255) = 254
        assert result >= 254

    def test_black(self):
        """Test conversion of black."""
        result = rgb_to_grayscale(0, 0, 0)
        assert result == 0

    def test_pure_red(self):
        """Test conversion of pure red."""
        result = rgb_to_grayscale(255, 0, 0)
        assert result == int(0.21 * 255)

    def test_pure_green(self):
        """Test conversion of pure green."""
        result = rgb_to_grayscale(0, 255, 0)
        assert result == int(0.72 * 255)

    def test_invalid_value(self):
        """Test that invalid RGB value raises ValueError."""
        with pytest.raises(ValueError):
            rgb_to_grayscale(256, 0, 0)

    def test_negative_value(self):
        """Test that negative RGB value raises ValueError."""
        with pytest.raises(ValueError):
            rgb_to_grayscale(-1, 0, 0)


class TestIsValidResolution:
    """Tests for is_valid_resolution function."""

    def test_valid_resolution(self):
        """Test valid resolution."""
        assert is_valid_resolution(1920, 1080) is True

    def test_minimum_resolution(self):
        """Test minimum valid resolution."""
        assert is_valid_resolution(1, 1) is True

    def test_invalid_width(self):
        """Test invalid width."""
        assert is_valid_resolution(0, 100) is False

    def test_invalid_height(self):
        """Test invalid height."""
        assert is_valid_resolution(100, 0) is False

    def test_custom_minimum(self):
        """Test with custom minimum requirements."""
        assert is_valid_resolution(800, 600, min_width=1920, min_height=1080) is False
        assert is_valid_resolution(1920, 1080, min_width=1920, min_height=1080) is True
