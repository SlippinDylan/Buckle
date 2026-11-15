"""Exercise .strings format contracts without reading user data."""
import importlib.util
from pathlib import Path
import sys
import unittest
import warnings

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location(
    "check_localizations", Path(__file__).resolve().parents[1] / "Scripts/check-localizations.py")
localizations = importlib.util.module_from_spec(spec)
spec.loader.exec_module(localizations)


class LocalizationFormatTests(unittest.TestCase):
    def test_rejects_added_removed_and_changed_argument_types(self):
        for source, target in [("%@", "%@ %d"), ("%d", "%@"), ("%ld", "%d"),
                               ("%*.*f", "%f"), ("%@", "plain text"), ("plain text", "%n")]:
            with self.subTest(source=source, target=target), self.assertRaises(ValueError):
                localizations.validate_formats(source, target, "test")

    def test_allows_positional_reordering_and_repeated_references(self):
        localizations.validate_formats("%@ %d", "%2$d %1$@ %1$@", "test")
        localizations.validate_formats("%*.*f", "%3$*1$.*2$f", "test")
        localizations.validate_formats("%x %.2f", "%u %g", "test")

    def test_literal_percent_has_no_argument(self):
        self.assertEqual(localizations.format_arguments("100%% · %@"), {1: "@"})
        localizations.validate_formats("100%%", "100%", "test")
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            localizations.validate_formats("100%% free", "100%% frei", "test")
        self.assertEqual(caught, [])

    def test_ambiguous_prose_warns_for_manual_review(self):
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            localizations.validate_formats("100% complete", "100 % fertig", "test")
        self.assertEqual(len(caught), 1)
        self.assertIn("manual review", str(caught[0].message))

    def test_rejects_mixed_positions_conflicting_types_and_named_substitutions(self):
        for text in ["%1$@ %d", "%1$@ %1$d", "%#@items@"]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                localizations.format_arguments(text)


if __name__ == "__main__":
    unittest.main()
