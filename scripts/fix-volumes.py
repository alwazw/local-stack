#!/usr/bin/env python3
"""Add missing named volume definitions to compose files."""

import re
import os
import sys

# Map of compose files to their named volumes
VOLUME_DEFS = {
    'compose/ci/gitea/docker-compose.yml': ['gitea_data'],
    'compose/ci/n8n/docker-compose.yml': ['n8n_data'],
    'compose/ai/qdrant/docker-compose.yml': ['qdrant_data'],
    'compose/management/portainer/docker-compose.yml': ['portainer_data'],
    'compose/management/dockge/docker-compose.yml': ['dockge_data'],
    'compose/productivity/affine/docker-compose.yml': ['affine_data'],
    'compose/monitoring/uptime-kuma/docker-compose.yml': ['uptime_kuma_data'],
    'compose/monitoring/loki/docker-compose.yml': ['loki_data'],
    'compose/productivity/guacd/docker-compose.yml': ['guacd_drive', 'guacd_record'],
    'compose/monitoring/grafana/docker-compose.yml': ['grafana_data'],
    'compose/security/authentik-server/docker-compose.yml': [],  # uses bind mounts
    'compose/security/authentik-worker/docker-compose.yml': [],  # uses bind mounts
    'compose/security/vaultwarden/docker-compose.yml': [],  # uses bind mount
}

BASE = '/mnt/d/docker'

def add_volumes(filepath, volumes):
    if not volumes:
        return False
    
    with open(filepath, 'r') as f:
        content = f.read()
    
    # Check if volumes section already exists
    if re.search(r'\nvolumes:\n', content):
        return False
    
    # Remove trailing whitespace
    content = content.rstrip() + '\n'
    
    # Add volumes section
    vol_section = '\nvolumes:\n'
    for v in volumes:
        vol_section += f'  {v}:\n'
    
    with open(filepath, 'w') as f:
        f.write(content + vol_section)
    
    return True

def main():
    added = 0
    for rel_path, volumes in VOLUME_DEFS.items():
        filepath = os.path.join(BASE, rel_path)
        if os.path.exists(filepath):
            if add_volumes(filepath, volumes):
                print(f"  ✓ {rel_path}: added {volumes}")
                added += 1
            else:
                print(f"  - {rel_path}: skipped (already has volumes or no volumes needed)")
        else:
            print(f"  ✗ {rel_path}: file not found")
    
    print(f"\nAdded volume definitions to {added} files")

if __name__ == '__main__':
    main()
