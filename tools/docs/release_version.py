# SPDX-License-Identifier: Apache-2.0
#
# MkDocs hook: replace the placeholder <version> in every page with the release
# tag vX.Y.Z from DOCS_RELEASE_TAG, set by the Makefile from the tag of a release
# build or the highest published release. Without a release the placeholder stays.

import os
import re

from mkdocs.exceptions import PluginError

PLACEHOLDER = "<version>"
RELEASE_TAG = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+$")

_tag = ""


def on_config(config):
    global _tag
    tag = os.environ.get("DOCS_RELEASE_TAG", "")
    if tag and not RELEASE_TAG.match(tag):
        raise PluginError(f"DOCS_RELEASE_TAG={tag} is not a release tag vX.Y.Z")
    _tag = tag
    return config


def on_page_markdown(markdown, **kwargs):
    if not _tag:
        return markdown
    return markdown.replace(PLACEHOLDER, _tag)
