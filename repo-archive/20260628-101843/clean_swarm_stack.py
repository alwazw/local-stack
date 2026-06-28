#!/usr/bin/env python3
# save as clean_swarm_stack.py
from ruamel.yaml import YAML
from ruamel.yaml.scalarstring import DoubleQuotedScalarString
import sys

REMOVE_SERVICE_KEYS = {
    "restart",
    "extra_hosts",
    "privileged",
    "cap_add",
    "stdin_open",
    "tty",
    "container_name",
    "depends_on",
    "links",
    "profiles",
}

def clean_service(name, svc):
    for k in list(svc.keys()):
        if k in REMOVE_SERVICE_KEYS:
            del svc[k]

    if "deploy" in svc and isinstance(svc["deploy"], dict):
        deploy = svc["deploy"]
        if "placement" in deploy and isinstance(deploy["placement"], dict):
            if "constraints" in deploy["placement"]:
                del deploy["placement"]["constraints"]
            if not deploy["placement"]:
                del deploy["placement"]

    has_bind = False
    if "volumes" in svc and isinstance(svc["volumes"], list):
        for v in svc["volumes"]:
            if isinstance(v, dict):
                if v.get("type") == "bind" or "bind" in v:
                    has_bind = True
            elif isinstance(v, str):
                if ":" in v:
                    host_part = v.split(":", 1)[0]
                    if host_part.startswith("/") or host_part.startswith("~"):
                        has_bind = True
    if has_bind:
        svc["x_bind_mounts_warning"] = DoubleQuotedScalarString(
            "Ensure host path exists on every node or add placement constraints"
        )
    return svc

def reorder_top_level(doc):
    order = ["services", "networks", "volumes", "secrets"]
    new = {}
    for k in order:
        if k in doc:
            new[k] = doc[k]
    for k in doc:
        if k not in new:
            new[k] = doc[k]
    return new

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 clean_swarm_stack.py input.yml output.yml")
        sys.exit(2)

    infile = sys.argv[1]
    outfile = sys.argv[2]

    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.indent(mapping=2, sequence=4, offset=2)

    with open(infile, "r") as f:
        doc = yaml.load(f)

    if not isinstance(doc, dict):
        print("Input YAML root is not a mapping. Aborting.")
        sys.exit(1)

    services = doc.get("services", {})
    cleaned_services = {}
    for name in sorted(services.keys()):
        svc = services[name]
        cleaned_services[name] = clean_service(name, svc)

    doc["services"] = cleaned_services
    doc = reorder_top_level(doc)

    with open(outfile, "w") as f:
        yaml.dump(doc, f)

    print(f"Cleaned stack written to {outfile}")

if __name__ == "__main__":
    main()
