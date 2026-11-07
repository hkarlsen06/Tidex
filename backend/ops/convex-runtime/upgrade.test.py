import importlib.util
import pathlib
import unittest
import tempfile

spec = importlib.util.spec_from_file_location('upgrade', pathlib.Path(__file__).with_name('upgrade.py'))
upgrade = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upgrade)


class GateTests(unittest.TestCase):
    def test_recovery_cannot_run_during_an_active_upgrade(self):
        previous = upgrade.ROOT
        try:
            with tempfile.TemporaryDirectory() as folder:
                upgrade.ROOT = pathlib.Path(folder)
                with upgrade.upgrade_lock():
                    with self.assertRaises(BlockingIOError):
                        with upgrade.upgrade_lock():
                            self.fail('A second upgrader or recovery acquired the lock')
                with upgrade.upgrade_lock():
                    pass
        finally:
            upgrade.ROOT = previous

    def test_only_selected_proxy_dials_change_and_inverse_restores(self):
        original = {'routes': [{'handler': 'reverse_proxy', 'upstreams': [{'dial': '127.0.0.1:3221'}]},
                               {'handler': 'reverse_proxy', 'upstreams': [{'dial': '127.0.0.1:3210'}]},
                               {'handler': 'static_response', 'body': '127.0.0.1:3221'}]}
        changed, count = upgrade.replace_upstreams(original, upgrade.GATES['tidex'])
        self.assertEqual(count['127.0.0.1:3221'], 1)
        self.assertEqual(changed['routes'][1:], original['routes'][1:])
        self.assertEqual(original['routes'][0]['upstreams'][0]['dial'], '127.0.0.1:3221')
        # A concurrent unrelated route addition must survive recovery.
        changed['new'] = {'handler': 'reverse_proxy', 'upstreams': [{'dial': '127.0.0.1:9999'}]}
        restored, _ = upgrade.replace_upstreams(changed, {v: k for k, v in upgrade.GATES['tidex'].items()})
        self.assertEqual(restored['routes'], original['routes'])
        self.assertEqual(restored['new'], changed['new'])

    def test_rejects_unexpected_compose_and_supports_subsequent_upgrade(self):
        images = {kind: {'image': 'convex-runtime/' + kind + '@sha256:' + 'b'*64} for kind in ['backend', 'dashboard']}
        text = '\n'.join('    image: ghcr.io/convex/convex-' + kind + '@sha256:' + 'a'*64 for kind in images)
        first = upgrade.image_compose(text, images)
        self.assertEqual(upgrade.image_compose(first, images), first)
        with self.assertRaises(RuntimeError):
            upgrade.image_compose('    image: some-other-backend:latest', images)


if __name__ == '__main__':
    unittest.main()
