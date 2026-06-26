#!/usr/bin/env python3
"""Convert docker-compose files from Compose to Swarm-compatible format.

Changes applied to ALL compose files:
1. Remove container_name: (Swarm manages naming)
2. Remove depends_on: blocks (Swarm uses healthcheck + restart_policy)
3. Add deploy: section with restart_policy and resource limits
4. Remove bottom-level networks: {external: true} blocks (defined in root)
5. Keep secrets as-is (file: works for single-node Swarm)

Special handling:
- cadvisor: deploy.mode: global + cap_add
- hermes-agent: placement constraint [node.role == manager]
"""

import re
import sys
import os

def remove_container_name(content):
    """Remove container_name: lines."""
    return re.sub(r'^\s+container_name:.*$\n?', '', content, flags=re.MULTILINE)

def remove_depends_on(content):
    """Remove depends_on: blocks (including their children)."""
    # Match depends_on: and all indented children
    return re.sub(
        r'^(\s+)depends_on:\n((?:\s{3,}.+\n?)*)',
        '',
        content,
        flags=re.MULTILINE
    )

def add_deploy_section(content):
    """Add deploy: section after restart: unless-stopped."""
    # Only add if not already present
    if 'deploy:' in content:
        return content
    
    # Find restart: unless-stopped and add deploy after it
    def add_after_restart(match):
        indent = match.group(1)
        return match.group(0) + f'\n{indent}deploy:\n{indent}  restart_policy:\n{indent}    condition: on-failure\n{indent}    delay: 10s\n{indent}    max_attempts: 3\n{indent}    window: 120s\n{indent}  resources:\n{indent}    limits:\n{indent}      cpus: "2.0"\n{indent}      memory: 1G'
    
    return re.sub(
        r'^(\s+)restart: unless-stopped$',
        add_after_restart,
        content,
        flags=re.MULTILINE
    )

def remove_external_networks(content):
    """Remove bottom-level networks: {external: true} blocks.
    
    These networks will be defined in the root docker-compose.yml.
    """
    # Match patterns like:
    # networks:
    #   proxy:
    #     external: true
    #   ai-ml:
    #     external: true
    # (possibly with more networks)
    pattern = r'\nnetworks:\n(?:\s+\w[\w-]*:\n\s+external: true\n)+'
    return re.sub(pattern, '\n', content)

def remove_volumes_section(content):
    """Remove bottom-level volumes: blocks (will be defined in root for Swarm)."""
    pattern = r'\nvolumes:\n(?:\s+\w[\w-]*(?::\n(?:\s+.+\n)?|\n))+'
    return re.sub(pattern, '\n', content)

def add_cadvisor_global(content):
    """Special handling for cadvisor: global mode + cap_add."""
    if 'cadvisor' not in content:
        return content
    
    # Replace the deploy section with global mode
    content = re.sub(
        r'(\s+)deploy:\n\1  restart_policy:',
        r'\1deploy:\n\1  mode: global\n\1  restart_policy:',
        content
    )
    
    # Add cap_add after mode: global
    content = re.sub(
        r'(\s+)mode: global\n',
        r'\1mode: global\n\1  placement:\n\1    constraints:\n\1      - node.role == manager\n\1  cap_add:\n\1    - ALL\n',
        content
    )
    
    return content

def add_hermes_placement(content):
    """Special handling for hermes-agent: placement constraint."""
    if 'hermes-agent' not in content:
        return content
    
    # Add placement constraint to the deploy section
    content = re.sub(
        r'(\s+)deploy:\n\1  restart_policy:',
        r'\1deploy:\n\1  placement:\n\1    constraints:\n\1      - node.role == manager\n\1  restart_policy:',
        content
    )
    
    return content

def convert_file(filepath):
    """Convert a single compose file."""
    with open(filepath, 'r') as f:
        content = f.read()
    
    original = content
    
    # Apply all transformations
    content = remove_container_name(content)
    content = remove_depends_on(content)
    content = add_deploy_section(content)
    content = remove_external_networks(content)
    content = remove_volumes_section(content)
    
    # Special handling
    content = add_cadvisor_global(content)
    content = add_hermes_placement(content)
    
    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
        return True
    return False

def main():
    compose_dir = '/mnt/d/docker/compose'
    converted = 0
    skipped = 0
    errors = 0
    
    for root, dirs, files in os.walk(compose_dir):
        for fname in files:
            if fname == 'docker-compose.yml':
                filepath = os.path.join(root, fname)
                try:
                    if convert_file(filepath):
                        print(f"  ✓ {filepath}")
                        converted += 1
                    else:
                        print(f"  - {filepath} (no changes)")
                        skipped += 1
                except Exception as e:
                    print(f"  ✗ {filepath}: {e}")
                    errors += 1
    
    print(f"\nSummary: {converted} converted, {skipped} skipped, {errors} errors")
    return 0 if errors == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
