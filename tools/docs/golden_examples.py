# SPDX-License-Identifier: Apache-2.0
#
# MkDocs hook: replace a line <!-- golden: <case> --> with a collapsed example of
# the golden case internal/ingress/controller/testdata/golden/<case>: its
# annotations, the ConfigMap of the controller it needs and what it changes in
# nginx.conf and in the backends of the Lua balancer against the case without
# annotations. TestGolden keeps the golden files in line with the code.

import difflib
import json
import os
import re

import yaml
from mkdocs.exceptions import PluginError

GOLDEN = os.path.join("internal", "ingress", "controller", "testdata", "golden")
MARKER = re.compile(r"^<!-- golden: ([a-z0-9-]+) -->$", re.MULTILINE)
OUTSIDE = "## outside of the server blocks"
PREFIX = "nginx.ingress.kubernetes.io/"

_golden = ""


def on_config(config):
    global _golden
    _golden = os.path.join(os.path.dirname(config.config_file_path), GOLDEN)
    return config


def on_page_markdown(markdown, page, **kwargs):
    def example(match):
        case = match.group(1)
        if not os.path.isdir(os.path.join(_golden, case)):
            raise PluginError(f"{page.file.src_path}: no golden case {case} in {GOLDEN}")
        return render(case)

    return MARKER.sub(example, markdown)


def read(case, name):
    path = os.path.join(_golden, case, name)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return f.read()


def render(case):
    docs = [d for d in yaml.safe_load_all(read(case, "ingress.yaml")) if d]
    ingresses = [d for d in docs if d["kind"] == "Ingress"]
    base = "default-tls" if any(i["spec"].get("tls") for i in ingresses) else "default"

    parts = []
    for ing in ingresses:
        anns = ing["metadata"].get("annotations") or {}
        title = "Annotations" if len(ingresses) == 1 else f"Annotations of the Ingress `{ing['metadata']['name']}`"
        if anns:
            parts.append((f"{title}:", "yaml", [f"{k}: {json.dumps(v)}" for k, v in anns.items()]))
        else:
            parts.append((f"{title}: none.", None, None))

    configmap = read(case, "configmap.yaml")
    if configmap:
        data = yaml.safe_load(configmap).get("data") or {}
        parts.append(("ConfigMap of the controller:", "yaml", [f"{k}: {json.dumps(v)}" for k, v in data.items()]))

    against = "against an Ingress without annotations" + (" and with the default ConfigMap" if configmap else "")
    server, _, outside = read(case, "server.conf").partition(OUTSIDE)
    servers = changes(read(base, "server.conf"), server)
    outside = outside.splitlines()[1:]
    backends = backend_changes(json.loads(read(base, "backends.json")), json.loads(read(case, "backends.json")))

    if servers:
        parts.append((f"Server blocks of nginx.conf, {against}:", "diff", dedent(servers)))
    if outside:
        parts.append((f"nginx.conf outside of the server blocks, {against}:", "diff", dedent(outside)))
    if backends:
        parts.append((f"Backends of the Lua balancer and of SSL passthrough that differ, {against}:", "json",
                      json.dumps(backends, indent=2).splitlines()))
    if not servers and not outside and not backends:
        parts.append((f"No changes {against}.", None, None))

    out = [f'??? example "What `{case}` changes"', ""]
    for text, lang, lines in parts:
        out += [f"    {text}", ""]
        if lang:
            out += [f"    ```{lang}"] + [f"    {line}" for line in lines] + ["    ```", ""]
    return "\n".join(out)


def changes(base, case):
    """The lines case adds (+) and removes (-) against base, without positions."""
    diff = difflib.unified_diff(base.splitlines(), case.splitlines(), n=0, lineterm="")
    return [line for line in diff if line[:1] in "+-" and not line.startswith(("+++", "---"))]


def backend_changes(base, case):
    """New backends whole and changed backends with their name and changed fields."""
    known = {b["name"]: b for b in base["backends"]}
    backends = []
    for b in case["backends"]:
        old = known.get(b["name"])
        if old is None:
            backends.append(b)
            continue
        changed = {k: v for k, v in b.items() if old.get(k) != v}
        if changed:
            backends.append({"name": b["name"], **changed})

    out = {}
    if backends:
        out["backends"] = backends
    if case.get("passthroughBackends"):
        out["passthroughBackends"] = case["passthroughBackends"]
    return out


def dedent(lines):
    """Drop the common indentation after the +/- sign, tabs as four spaces."""
    lines = [line[0] + line[1:].replace("\t", "    ") for line in lines]
    indent = min((len(line[1:]) - len(line[1:].lstrip(" ")) for line in lines if line[1:].strip()), default=0)
    return [line[0] + line[1 + indent:] for line in lines]
