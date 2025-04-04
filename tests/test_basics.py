"""
Basic tests for ChromaDesk functionality.
"""
import unittest


class TestBasics(unittest.TestCase):
    """Basic test cases."""

    def test_import(self):
        """Test that the package can be imported."""
        import chromadesk

        self.assertIsNotNone(chromadesk)

    def test_version(self):
        """Test that the version is defined."""
        import chromadesk

        self.assertTrue(hasattr(chromadesk, "__version__"))


if __name__ == "__main__":
    unittest.main()
