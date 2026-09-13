import pathlib
import plistlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class LinkRegistrationChecks(unittest.TestCase):
    def test_production_and_dev_have_exact_disjoint_url_contracts(self):
        for file, identity, scheme in [
            ("Openlist-Info.plist", "solimanali.openlist.item", "openlist"),
            ("OpenlistDev-Info.plist", "solimanali.openlist.dev.item", "openlist-dev"),
        ]:
            with self.subTest(file=file):
                with (ROOT / "Config" / file).open("rb") as source:
                    info = plistlib.load(source)
                self.assertEqual(info["CFBundleURLTypes"], [{"CFBundleTypeRole": "Viewer", "CFBundleURLName": identity, "CFBundleURLSchemes": [scheme]}])

    def test_widgets_do_not_claim_item_links(self):
        with (ROOT / "Config/OpenlistWidget-Info.plist").open("rb") as source:
            self.assertNotIn("CFBundleURLTypes", plistlib.load(source))


if __name__ == "__main__":
    unittest.main()
