#!/usr/bin/env python3
"""One-time migration helper: converts HELK's legacy ES `_template` JSON files
(order/index_patterns/settings/mappings) into composable-template-compatible
component templates. Run once against docker/helk-logstash/output_templates/,
writing results into output_templates/components/. Not invoked at container
runtime — the entrypoint ships the already-converted output.
"""
import json
import os

SRC = "output_templates"
DST = "output_templates/components"

# component template name -> source legacy filename (digit prefix stripped)
COLLIDING_FILES = [
    "10-helk-logs-all-default.json",
    "12-helk-logs-all-other_ecs_fields.json",
    "20-helk-logs-all.json",
    "90-helk-logs-not-ip.json",
    "91-helk-logs-network-fields.json",
    "92-helk-logs-ips.json",
    "99-helk-logs-all-dynamic_templates.json",
    "99-helk-logs-any-fields.json",
    "88-helk-logs-meta-enrichment-for-endpoints.json",
    "89-helk-logs-fingerprints-for-endpoints.json",
    "50-helk-logs-winevent-all.json",
    "51-helk-logs-winevent-winlogbeat-param-fields.json",
    "60-helk-winevent-sysmon.json",
    "60-helk-winevent-security.json",
    "60-helk-winevent-system.json",
    "60-helk-winevent-application.json",
    "60-helk-winevent-wmiactivity.json",
    "60-helk-winevent-powershell.json",
    "88-helk-logs-meta-enrichment-for-powershell.json",
    "89-helk-logs-fingerprints-powershell.json",
    "60-helk-powershell-direct.json",
    "71-helk-network-zeek.json",
]


def component_name(filename):
    stem = filename[:-len(".json")]
    parts = stem.split("-", 1)
    return parts[1] if len(parts) == 2 and parts[0].isdigit() else stem


def convert(filename):
    with open(os.path.join(SRC, filename)) as f:
        legacy = json.load(f)
    template = {}
    if "settings" in legacy:
        template["settings"] = legacy["settings"]
    if "mappings" in legacy:
        template["mappings"] = legacy["mappings"]
    component = {"template": template}
    if "version" in legacy:
        component["version"] = legacy["version"]
    return component


def main():
    os.makedirs(DST, exist_ok=True)
    for filename in COLLIDING_FILES:
        name = component_name(filename)
        component = convert(filename)
        out_path = os.path.join(DST, f"{name}.json")
        with open(out_path, "w") as f:
            json.dump(component, f, indent=2)
        print(f"{filename} -> components/{name}.json")


if __name__ == "__main__":
    main()
