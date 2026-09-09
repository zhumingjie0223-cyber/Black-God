import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from package_source import validate_alpine


class SourceIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        recipe = self.root / 'recipes/example/APKBUILD'
        recipe.parent.mkdir(parents=True)
        digest = hashlib.sha512(b'source').hexdigest()
        recipe.write_text('sha512sums="\n' + digest + '  sample\n"\n')
        (self.root / 'sample').write_bytes(b'source')
        self.manifest = {'packages': [{'o': 'example', 'c': 'abc'}], 'errors': [],
                         'origins': [{'origin': 'example', 'aports_commit': 'abc',
                                      'sources': [{'file': 'sample', 'sha512': digest}]}]}

    def validate(self):
        (self.root / 'manifest.json').write_text(json.dumps(self.manifest))
        return validate_alpine(self.root)

    def test_valid_source(self):
        self.assertEqual(len(self.validate()['origins']), 1)

    def test_corrupted_archive_input(self):
        (self.root / 'sample').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            self.validate()

    def test_wrong_aports_revision(self):
        self.manifest['origins'][0]['aports_commit'] = 'wrong'
        with self.assertRaisesRegex(ValueError, 'origins do not match'):
            self.validate()

    def test_missing_source_manifest_entry(self):
        self.manifest['origins'][0]['sources'] = []
        with self.assertRaisesRegex(ValueError, 'do not match APKBUILD'):
            self.validate()

    def test_path_escape(self):
        self.manifest['origins'][0]['sources'][0]['file'] = '../sample'
        with self.assertRaisesRegex(ValueError, 'escapes collection'):
            self.validate()


if __name__ == '__main__':
    unittest.main()
