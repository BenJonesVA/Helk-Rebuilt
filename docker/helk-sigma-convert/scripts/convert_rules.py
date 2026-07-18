#!/usr/bin/env python3
"""Converts SigmaHQ/sigma Windows rules to ElastAlert2 query_string rules.

Runs once per container start. For each rule file under
/opt/sigma-rules/windows, converts it to a Lucene query via
pySigma-backend-elasticsearch plus the HELK OSSEM field-mapping pipeline
(pipeline/helk_ossem_pipeline.yml), maps its logsource to a HELK index
pattern (pipeline/logsource_index_map.yml), and writes a matching ElastAlert2
rule YAML into OUTPUT_DIR. Rules pySigma can't convert (unsupported
features, no index mapping, correlation-only rules) are logged and skipped
rather than silently dropped - see the final summary line and any [SKIP]
lines above it.
"""
import glob
import os

import yaml
from sigma.backends.elasticsearch import LuceneBackend
from sigma.collection import SigmaCollection
from sigma.exceptions import SigmaError
from sigma.processing.pipeline import ProcessingPipeline

HERE = os.path.dirname(os.path.abspath(__file__))
RULES_SRC = "/opt/sigma-rules/windows"
OUTPUT_DIR = os.environ.get("SIGMA_OUTPUT_DIR", "/output")
LEVEL_TO_PRIORITY = {"critical": 1, "high": 1, "medium": 2, "low": 3, "informational": 3}

with open(os.path.join(HERE, "..", "pipeline", "helk_ossem_pipeline.yml")) as f:
    PIPELINE = ProcessingPipeline.from_yaml(f.read())

with open(os.path.join(HERE, "..", "pipeline", "logsource_index_map.yml")) as f:
    INDEX_MAP = yaml.safe_load(f)

SYSMON_INDEX = INDEX_MAP["sysmon_category_index"]

BACKEND = LuceneBackend(processing_pipeline=PIPELINE)


def resolve_index(logsource):
    product = (logsource.product or "").lower()
    service = (logsource.service or "").lower()
    category = (logsource.category or "").lower()

    if product != "windows":
        return None  # out of scope for this conversion pass

    key = f"windows/{service}" if service else None
    if key and key in INDEX_MAP:
        return INDEX_MAP[key]["index"]
    if category:
        # Every category-based rule (process_creation, registry_event,
        # network_connection, ...) in the current windows/ tree is Sysmon-sourced.
        return SYSMON_INDEX
    if service:
        return None  # a service HELK doesn't ingest (e.g. taskscheduler, dns_server)
    return INDEX_MAP["windows"]["index"]


def safe_name(rule):
    base = str(rule.title or rule.id or "sigma_rule")
    return "".join(c if c.isalnum() else "_" for c in base).strip("_")


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    rule_files = sorted(glob.glob(os.path.join(RULES_SRC, "**", "*.yml"), recursive=True))
    converted = 0
    skipped = 0

    for path in rule_files:
        try:
            with open(path, encoding="utf-8") as f:
                collection = SigmaCollection.from_yaml(f.read())
        except Exception as exc:
            print(f"[SKIP] {path}: failed to parse - {exc}")
            skipped += 1
            continue

        for rule in collection.rules:
            index = resolve_index(rule.logsource)
            if index is None:
                print(
                    f"[SKIP] {rule.title!r} ({path}): no HELK index mapping for logsource "
                    f"product={rule.logsource.product} service={rule.logsource.service} "
                    f"category={rule.logsource.category}"
                )
                skipped += 1
                continue

            try:
                queries = BACKEND.convert_rule(rule)
            except SigmaError as exc:
                print(f"[SKIP] {rule.title!r} ({path}): pySigma conversion error - {exc}")
                skipped += 1
                continue
            except Exception as exc:
                print(f"[SKIP] {rule.title!r} ({path}): unexpected conversion error - {exc}")
                skipped += 1
                continue

            if not queries:
                print(f"[SKIP] {rule.title!r} ({path}): produced no query (correlation-only rule?)")
                skipped += 1
                continue

            level_name = rule.level.name.lower() if rule.level else "medium"
            priority = LEVEL_TO_PRIORITY.get(level_name, 2)

            for n, query in enumerate(queries):
                suffix = f"_{n}" if len(queries) > 1 else ""
                out_rule = {
                    "name": f"Sigma_{safe_name(rule)}{suffix}",
                    "description": str(rule.description or "")[:1000],
                    "index": index,
                    "priority": priority,
                    "realert": {"minutes": 0},
                    "timestamp_field": "etl_processed_time",
                    "type": "any",
                    "filter": [{"query": {"query_string": {"query": str(query)}}}],
                    "alert": ["debug"],
                }
                out_path = os.path.join(OUTPUT_DIR, f"{out_rule['name']}.yaml")
                with open(out_path, "w") as out_f:
                    yaml.dump(out_rule, out_f, sort_keys=False)
                converted += 1

    print(f"Converted {converted} Sigma rules to ElastAlert2 rules ({skipped} skipped).")
    # Marker file so helk-elastalert can wait for this one-shot pass to finish.
    with open(os.path.join(OUTPUT_DIR, ".ready"), "w") as f:
        f.write(f"converted={converted} skipped={skipped}\n")


if __name__ == "__main__":
    main()
