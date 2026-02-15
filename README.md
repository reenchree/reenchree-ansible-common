# reenchree.common

Shared Ansible collection for common roles used across the reenchree homelab infrastructure.

## Roles

### `reenchree.common.node_exporter`

Installs and configures Prometheus node_exporter via apt.

**Default variables:**
- `node_exporter_listen_address`: `0.0.0.0:9100`

### `reenchree.common.zfs_exporter`

Downloads, installs, and configures the ZFS exporter from GitHub releases.

**Default variables:**
- `zfs_exporter_version`: `2.3.11`
- `zfs_exporter_listen_address`: `0.0.0.0:9134`

## Installation

Add to your `requirements.yml`:

```yaml
collections:
  - name: https://github.com/reenchree/reenchree-ansible-common.git
    type: git
    version: main
```

Then install:

```bash
ansible-galaxy collection install -r requirements.yml
```

## Usage

```yaml
roles:
  - role: reenchree.common.node_exporter
  - role: reenchree.common.zfs_exporter
```
