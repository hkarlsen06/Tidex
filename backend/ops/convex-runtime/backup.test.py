import base64
import hashlib
import json
import pathlib
import tempfile
import unittest
import zipfile
from backup import verify_export


class ExportTests(unittest.TestCase):
    def test_detects_corrupt_content_even_when_zip_crc_is_valid(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = pathlib.Path(directory) / 'export.zip'
            expected = b'private attachment'
            metadata = {'_id': 'file-id', 'size': len(expected),
                        'sha256': base64.b64encode(hashlib.sha256(expected).digest()).decode()}
            for actual, valid in [(expected, True), (b'altered attachment', False)]:
                with zipfile.ZipFile(archive, 'w') as zipped:
                    zipped.writestr('README.md', 'snapshot')
                    zipped.writestr('users/documents.jsonl', '{}\n')
                    zipped.writestr('_storage/documents.jsonl', json.dumps(metadata))
                    zipped.writestr('_storage/file-id.bin', actual)
                if valid:
                    self.assertEqual(verify_export(archive), 1)
                else:
                    with self.assertRaisesRegex(RuntimeError, 'contents differ'):
                        verify_export(archive)


if __name__ == '__main__':
    unittest.main()
