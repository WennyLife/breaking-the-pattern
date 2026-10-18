#!/usr/bin/env python3
"""Evaluate bundled compatibility knowledge without executing code from rules."""
import argparse
import hashlib
import json
from pathlib import Path

CATALOG = Path(__file__).resolve().with_name('compatibility-rules.json')
PREDICATES = {'arch_in', 'uses_any', 'year_min', 'year_max_exclusive'}
VALUES = {'renderer': ('', 'd3d9=mtld3d', 'dxgi=dxmt', 'dxgi=gptk'),
          'windows': ('win7',), 'x87': (True, False)}


def load_catalog():
    raw = CATALOG.read_bytes()
    catalog = json.loads(raw)
    if catalog.get('schema') != 1 or type(catalog.get('revision')) is not int or catalog['revision'] < 1:
        raise ValueError('Unsupported compatibility knowledge format')
    seen = set()
    for rule in catalog['rules']:
        if not isinstance(rule['id'], str) or not rule['id'] or rule['id'] in seen:
            raise ValueError('Duplicate or invalid rule identity')
        seen.add(rule['id'])
        when, actions = rule['when'], rule['set']
        if not when or not set(when) <= PREDICATES or not actions or not set(actions) <= VALUES.keys():
            raise ValueError('Unsupported compatibility predicate or action')
        for key, value in when.items():
            if key in ('arch_in', 'uses_any'):
                if not isinstance(value, list) or not value or not all(isinstance(v, str) and v for v in value):
                    raise ValueError('Invalid compatibility list')
            elif type(value) is not int or value < 0:
                raise ValueError('Invalid compatibility year')
        for key, value in actions.items():
            if key == 'x87' and type(value) is not bool:
                raise ValueError('x87 action must be boolean')
            if value not in VALUES[key]:
                raise ValueError('Unsupported compatibility value')
    return catalog, hashlib.sha256(raw).hexdigest()


def evaluate(arch, year, imports, strings=()):
    catalog, checksum = load_catalog()
    uses = {v.lower() for v in imports}
    uses.update(v.decode('ascii').lower() if isinstance(v, bytes) else v.lower() for v in strings)
    chosen, matched = {}, []
    for rule in catalog['rules']:
        when = rule['when']
        if 'arch_in' in when and arch not in when['arch_in']:
            continue
        if 'uses_any' in when and not uses.intersection(when['uses_any']):
            continue
        if year < when.get('year_min', 0) or year >= when.get('year_max_exclusive', 10000):
            continue
        # Catalog order is precedence. A later rule never overrides an earlier
        # choice for the same field (D3D12 before D3D11 before D3D9).
        applied = {k: v for k, v in rule['set'].items() if k not in chosen}
        if applied:
            chosen.update(applied)
            matched.append({'id': rule['id'], 'set': applied, 'evidence': rule['evidence']})
    return dict(schema=1, catalog_revision=catalog['revision'], catalog_sha256=checksum,
                renderer=chosen.get('renderer', ''), windows=chosen.get('windows', ''),
                x87=chosen.get('x87', False), applied_rules=matched,
                gameplay_validated=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--record', type=Path, required=True)
    parser.add_argument('--analysis', required=True)
    parser.add_argument('--renderer', required=True)
    parser.add_argument('--windows', required=True)
    parser.add_argument('--profile', default='')
    args = parser.parse_args()
    analysis = json.loads(args.analysis)
    record = {'schema': 1, 'analysis': analysis,
              'effective': {'renderer': args.renderer or 'wined3d', 'windows': args.windows or 'default',
                            'x87': analysis['compatibility']['x87'], 'game_profile': args.profile or None},
              'scope': 'Preparation plan only. Game profile or explicit selection can override generic suggestions. Gameplay is validated separately.'}
    temporary = args.record.with_suffix('.tmp')
    temporary.write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(args.record)


if __name__ == '__main__':
    main()
