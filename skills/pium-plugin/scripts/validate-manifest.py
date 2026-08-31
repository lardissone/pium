#!/usr/bin/env python3
"""Check a plugin manifest against the schema Pium ships.

The schema is read from the installed application, not copied into this skill,
so the answer is what the Pium on this machine accepts rather than what some
version of the documentation said. Pass one or more manifests:

    ./validate-manifest.py ~/.config/pium/plugins/*.pium.json

Only the JSON Schema keywords that manifest schema actually uses are
implemented. Some of Pium's rules live in the app rather than in the schema —
uniqueness of configuration keys and environment variables, a secret reaching
`arguments`, an alias two plugins claim — so a manifest this accepts can still
be reported in Settings > Plugins. That list is the last word.
"""

import json
import os
import re
import sys

SCHEMA_LOCATIONS = [
    os.environ.get("PIUM_SCHEMA", ""),
    "/Applications/Pium.app/Contents/Resources/PluginManifest.schema.json",
    os.path.expanduser("~/Applications/Pium.app/Contents/Resources/PluginManifest.schema.json"),
    "Pium/Resources/PluginManifest.schema.json",
]


def find_schema():
    for path in SCHEMA_LOCATIONS:
        if path and os.path.isfile(path):
            return path
    sys.exit(
        "No schema found. Install Pium, run this from the repository root, or "
        "point PIUM_SCHEMA at PluginManifest.schema.json."
    )


def type_name(value):
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    if value is None:
        return "null"
    return "number"


def validate(value, schema, path, errors):
    expected = schema.get("type")
    if expected and type_name(value) != expected:
        errors.append(f"{path}: expected {expected}, got {type_name(value)}")
        return

    if "const" in schema and value != schema["const"]:
        errors.append(f"{path}: must be {json.dumps(schema['const'])}")
    if "enum" in schema and value not in schema["enum"]:
        allowed = ", ".join(json.dumps(v) for v in schema["enum"])
        errors.append(f"{path}: must be one of {allowed}")

    if isinstance(value, str):
        pattern = schema.get("pattern")
        if pattern and not re.search(pattern, value):
            errors.append(f"{path}: {json.dumps(value)} does not match {pattern}")
        if len(value) < schema.get("minLength", 0):
            errors.append(f"{path}: must not be empty")

    if isinstance(value, int) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{path}: must be at least {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{path}: must be at most {schema['maximum']}")

    if isinstance(value, dict):
        properties = schema.get("properties", {})
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path or 'manifest'}: missing required key `{key}`")
        for key, child in value.items():
            child_path = f"{path}.{key}" if path else key
            if key in properties:
                validate(child, properties[key], child_path, errors)
            elif schema.get("additionalProperties") is False:
                errors.append(f"{child_path}: unknown key `{key}`")

    if isinstance(value, list) and "items" in schema:
        for index, item in enumerate(value):
            validate(item, schema["items"], f"{path}[{index}]", errors)


def main(paths):
    schema_path = find_schema()
    with open(schema_path) as handle:
        schema = json.load(handle)

    failed = False
    for path in paths:
        try:
            with open(path) as handle:
                manifest = json.load(handle)
        except (OSError, json.JSONDecodeError) as error:
            print(f"{path}: {error}")
            failed = True
            continue

        errors = []
        validate(manifest, schema, "", errors)
        if errors:
            failed = True
            print(path)
            for error in errors:
                print(f"  {error}")
        else:
            print(f"{path}: ok")

    print(f"\nSchema: {schema_path}")
    return 1 if failed else 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1:]))
