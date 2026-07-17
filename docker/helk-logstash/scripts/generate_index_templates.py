#!/usr/bin/env python3
"""Generates the composable index templates that compose the component
templates produced by convert_templates.py. Run once; output is committed
under output_templates/index_templates/ and applied at container start by
logstash-entrypoint.sh. Priorities are set well above the Elastic-managed
built-in "logs" template (priority 100) so HELK's own regular (non-data-stream)
indices win index template selection instead of falling into a data stream.
"""
import json
import os

DST = "output_templates/index_templates"

BROAD = [
    "helk-logs-all-default",
    "helk-logs-all-other_ecs_fields",
    "helk-logs-all",
    "helk-logs-not-ip",
    "helk-logs-network-fields",
    "helk-logs-ips",
    "helk-logs-all-dynamic_templates",
    "helk-logs-any-fields",
]
ENDPOINT = BROAD + [
    "helk-logs-meta-enrichment-for-endpoints",
    "helk-logs-fingerprints-for-endpoints",
]
WINEVENT = ENDPOINT + [
    "helk-logs-winevent-all",
    "helk-logs-winevent-winlogbeat-param-fields",
]

TEMPLATES = {
    "helk-logs-catchall": {
        "index_patterns": ["logs-*"],
        "priority": 200,
        "composed_of": BROAD,
    },
    "helk-logs-endpoint": {
        "index_patterns": ["logs-endpoint-*"],
        "priority": 300,
        "composed_of": ENDPOINT,
    },
    "helk-logs-network-zeek": {
        "index_patterns": ["logs-network-zeek-*"],
        "priority": 300,
        "composed_of": BROAD + ["helk-network-zeek"],
    },
    "helk-logs-endpoint-winevent": {
        "index_patterns": ["logs-endpoint-winevent-*"],
        "priority": 400,
        "composed_of": WINEVENT,
    },
    "helk-logs-endpoint-powershell-direct": {
        "index_patterns": ["logs-endpoint-powershell-direct-*"],
        "priority": 400,
        "composed_of": ENDPOINT + ["helk-powershell-direct"],
    },
    "helk-logs-endpoint-winevent-sysmon": {
        "index_patterns": ["logs-endpoint-winevent-sysmon-*"],
        "priority": 500,
        "composed_of": WINEVENT + ["helk-winevent-sysmon"],
    },
    "helk-logs-endpoint-winevent-security": {
        "index_patterns": ["logs-endpoint-winevent-security-*"],
        "priority": 500,
        "composed_of": WINEVENT + ["helk-winevent-security"],
    },
    "helk-logs-endpoint-winevent-system": {
        "index_patterns": ["logs-endpoint-winevent-system-*"],
        "priority": 500,
        "composed_of": WINEVENT + ["helk-winevent-system"],
    },
    "helk-logs-endpoint-winevent-application": {
        "index_patterns": ["logs-endpoint-winevent-application-*"],
        "priority": 500,
        "composed_of": WINEVENT + ["helk-winevent-application"],
    },
    "helk-logs-endpoint-winevent-wmiactivity": {
        "index_patterns": ["logs-endpoint-winevent-wmiactivity-*"],
        "priority": 500,
        "composed_of": WINEVENT + ["helk-winevent-wmiactivity"],
    },
    "helk-logs-endpoint-winevent-powershell": {
        "index_patterns": ["logs-endpoint-winevent-powershell-*"],
        "priority": 500,
        "composed_of": WINEVENT + [
            "helk-winevent-powershell",
            "helk-logs-meta-enrichment-for-powershell",
            "helk-logs-fingerprints-powershell",
        ],
    },
}


def main():
    os.makedirs(DST, exist_ok=True)
    for name, body in TEMPLATES.items():
        doc = {
            "index_patterns": body["index_patterns"],
            "priority": body["priority"],
            "composed_of": body["composed_of"],
            "template": {},
        }
        out_path = os.path.join(DST, f"{name}.json")
        with open(out_path, "w") as f:
            json.dump(doc, f, indent=2)
        print(f"-> index_templates/{name}.json (priority {body['priority']}, {len(body['composed_of'])} components)")


if __name__ == "__main__":
    main()
