# SPDX-License-Identifier: Apache-2.0
#
# Unit tests of the release_version hook. Run by `make docs-build`.

import os
import sys
import unittest
from unittest import mock

from mkdocs.exceptions import PluginError

sys.path.insert(0, os.path.dirname(__file__))
import release_version  # noqa: E402


def render(markdown, tag):
    with mock.patch.dict(os.environ, {"DOCS_RELEASE_TAG": tag}):
        release_version.on_config({})
    return release_version.on_page_markdown(markdown)


class ReleaseVersionTest(unittest.TestCase):
    def test_substitutes_the_release_tag(self):
        self.assertEqual(
            render("helm install --version <version>\n.../download/<version>/deploy-cloud.yaml", "v1.2.3"),
            "helm install --version v1.2.3\n.../download/v1.2.3/deploy-cloud.yaml",
        )

    def test_keeps_the_placeholder_without_a_release(self):
        self.assertEqual(render("--version <version>", ""), "--version <version>")

    def test_keeps_other_braces(self):
        self.assertEqual(render("--format '{{ json .SBOM }}'", "v1.2.3"), "--format '{{ json .SBOM }}'")

    def test_rejects_a_tag_that_is_not_a_release(self):
        for tag in ("1.2.3", "v1.2", "v1.2.3-rc.1", "latest"):
            with self.subTest(tag=tag), self.assertRaises(PluginError):
                render("<version>", tag)


if __name__ == "__main__":
    unittest.main()
