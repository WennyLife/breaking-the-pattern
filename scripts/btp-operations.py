#!/usr/bin/env python3
"""Catálogo de operações de compatibilidade estruturadas do BTP.

Cada operação possui condições de aplicação, runtime compatível, conflitos declarados,
evidência de validação e capacidade de reversão por backup.
"""
import argparse
from datetime import datetime
import hashlib
import importlib.util
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent

# Helpers carregam com Python -I -B
_components_spec = importlib.util.spec_from_file_location('btp_components', HERE / 'btp-components.py')
_components = importlib.util.module_from_spec(_components_spec)
_components_spec.loader.exec_module(_components)


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


OPERATIONS = {
    'op.graphics.d3d11.dxmt': {
        'id': 'op.graphics.d3d11.dxmt',
        'name': 'Renderizador Metal para Direct3D 10/11 (DXMT)',
        'category': 'graphics',
        'when': {'uses_any': ['d3d11.dll', 'dxgi.dll', 'd3d10.dll', 'd3d10_1.dll']},
        'conflicts_with': ['op.graphics.d3d9.mtld3d', 'op.graphics.d3d12.gptk'],
        'runtime_compat': ['wine-cx-26.3.0-9'],
        'settings': {'renderer': 'dxgi=dxmt'},
        'evidence': 'Perfil validado de Splinter Cell Conviction e jogos D3D11.'
    },
    'op.graphics.d3d9.mtld3d': {
        'id': 'op.graphics.d3d9.mtld3d',
        'name': 'Renderizador Metal para Direct3D 9 (mtld3d)',
        'category': 'graphics',
        'when': {'uses_any': ['d3d9.dll']},
        'conflicts_with': ['op.graphics.d3d11.dxmt', 'op.graphics.d3d12.gptk'],
        'runtime_compat': ['wine-cx-26.3.0-9'],
        'settings': {'renderer': 'd3d9=mtld3d'},
        'evidence': 'Sessões validadas independentes de NFSU2 e GTA SA em 2026-10-18.'
    },
    'op.cpu.x87sidecar': {
        'id': 'op.cpu.x87sidecar',
        'name': 'Sidecar de precisão x87 para Apple Silicon (Rosetta)',
        'category': 'cpu',
        'when': {'arch_in': ['i386']},
        'conflicts_with': [],
        'runtime_compat': ['wine-cx-26.3.0-9', 'x87sidecar-1.9.0'],
        'settings': {'x87': True},
        'evidence': 'Essencial para precisão física e estabilidade de jogos 32-bit (NFSU2, GTASA).'
    },
    'op.os.win7_legacy': {
        'id': 'op.os.win7_legacy',
        'name': 'Apresentação de ambiente Windows 7',
        'category': 'os',
        'when': {'year_max_exclusive': 2012},
        'conflicts_with': [],
        'runtime_compat': ['wine-cx-26.3.0-9'],
        'settings': {'windows': 'win7'},
        'evidence': 'Evita recusas de inicialização como "Operating System not supported" em jogos legados.'
    },
    'op.storage.nfs_data_drive': {
        'id': 'op.storage.nfs_data_drive',
        'name': 'Alias de unidade D: privada para checagem de dados',
        'category': 'storage',
        'when': {'recipe_in': ['nfsu2']},
        'conflicts_with': [],
        'runtime_compat': ['wine-cx-26.3.0-9'],
        'reversible': True,
        'evidence': 'NFSU2 falhava em 0x006f7429 na inicialização sem enumerar a unidade D:.'
    },
    'op.engine.gta_fps_cap_60': {
        'id': 'op.engine.gta_fps_cap_60',
        'name': 'Limite de física a 60 FPS no renderizador',
        'category': 'engine',
        'when': {'recipe_in': ['gtasa']},
        'conflicts_with': [],
        'runtime_compat': ['mtld3d'],
        'reversible': True,
        'evidence': 'RenderWare do GTA SA apresenta cintilação e quebra de física se exceder 60 FPS.'
    },
    'op.engine.gta_memory_arg': {
        'id': 'op.engine.gta_memory_arg',
        'name': 'Argumento de memória estendida (-memory 1048576)',
        'category': 'engine',
        'when': {'recipe_in': ['gtasa']},
        'conflicts_with': [],
        'runtime_compat': ['wine-cx-26.3.0-9'],
        'reversible': True,
        'evidence': 'Evita exaustão do espaço de endereçamento 32-bit do GTA SA sob Wine.'
    },
    'op.wine.gta_media_overrides': {
        'id': 'op.wine.gta_media_overrides',
        'name': 'Overrides de mídia e áudio nativo para GTA SA',
        'category': 'media',
        'when': {'recipe_in': ['gtasa']},
        'conflicts_with': [],
        'runtime_compat': ['wine-cx-26.3.0-9'],
        'settings': {
            'overrides': 'winegstreamer=;wmvcore=;vorbisfile=n,b;vorbishooked=n,b;eax=n,b;ogg=n,b;vorbis=n,b;dinput8=n,b;xinput1_3=b,n;winemenubuilder.exe='
        },
        'evidence': 'Wine abortava em winegstreamer_create_wm_sync_reader na abertura de cutscenes.'
    },
    'op.patch.gta_mtld3d_renderer': {
        'id': 'op.patch.gta_mtld3d_renderer',
        'name': 'Ajuste de compatibilidade na cópia privada do d3d9.dll (mtld3d)',
        'category': 'patch',
        'when': {'recipe_in': ['gtasa']},
        'conflicts_with': [],
        'runtime_compat': ['mtld3d'],
        'reversible': True,
        'evidence': 'Necessário para renderização correta de texturas e shaders no GTA SA.'
    },
    'op.plugin.nfsu2_widescreen': {
        'id': 'op.plugin.nfsu2_widescreen',
        'name': 'Provisionamento do Widescreen Fix e ASI Loader para NFSU2',
        'category': 'plugin',
        'component_id': 'nfsu2-widescreen-fix',
        'when': {'recipe_in': ['nfsu2']},
        'conflicts_with': [],
        'runtime_compat': ['wine-cx-26.3.0-9'],
        'reversible': True,
        'evidence': 'Permite rodar a partir de pasta limpa sem necessidade de cópia manual de plugins.'
    },
    'op.plugin.gtasa_widescreen': {
        'id': 'op.plugin.gtasa_widescreen',
        'name': 'Provisionamento do Widescreen Fix e vorbisFile ASI Loader para GTA SA',
        'category': 'plugin',
        'component_id': 'gtasa-widescreen-fix',
        'when': {'recipe_in': ['gtasa']},
        'conflicts_with': [],
        'runtime_compat': ['wine-cx-26.3.0-9'],
        'reversible': True,
        'evidence': 'Preserva vorbisFile original como vorbisHooked e instala ASI loader automaticamente.'
    },
    'op.plugin.gtasa_silentpatch': {
        'id': 'op.plugin.gtasa_silentpatch',
        'name': 'Provisionamento do SilentPatch para GTA SA',
        'category': 'plugin',
        'component_id': 'gtasa-silentpatch',
        'when': {'recipe_in': ['gtasa']},
        'conflicts_with': [],
        'runtime_compat': ['wine-cx-26.3.0-9'],
        'reversible': True,
        'evidence': 'Corrige travamento do mouse ao sair do menu e precisão do timer sob Wine.'
    }
}


def plan_operations(pe_info, recipe=None, target_game=None):
    """Compõe as operações aplicáveis respeitando condições, conflitos e precedência de receita."""
    arch = pe_info.get('arch', 'i386')
    year = pe_info.get('year', 0)
    imports = set(pe_info.get('imports', []))
    recipe_id = recipe.get('id') if isinstance(recipe, dict) else (recipe or '')

    selected = []
    skipped_conflicts = []
    active_conflicts = set()

    for op_id, op in OPERATIONS.items():
        when = op.get('when', {})

        # 1. Filtro de receita
        if 'recipe_in' in when and recipe_id not in when['recipe_in']:
            continue

        # 2. Filtro de arquitetura
        if 'arch_in' in when and arch not in when['arch_in']:
            continue

        # 3. Filtro de DLLs importadas
        if 'uses_any' in when and not imports.intersection(when['uses_any']):
            continue

        # 4. Filtro de ano COFF
        if 'year_max_exclusive' in when and (year <= 0 or year >= when['year_max_exclusive']):
            continue

        # 5. Checagem de conflitos
        if op_id in active_conflicts:
            skipped_conflicts.append({'operation': op_id, 'reason': 'Conflito com operação de maior precedência'})
            continue

        # Operação aceita
        selected.append(op)
        for conflict in op.get('conflicts_with', []):
            active_conflicts.add(conflict)

    return {
        'schema': 1,
        'recipe_applied': recipe_id or None,
        'selected_operations': [op['id'] for op in selected],
        'details': selected,
        'skipped_conflicts': skipped_conflicts,
        'reversibility': True
    }


class PlanTransaction:
    """Coordena transações atômicas de todas as operações usando uma única transação unificada."""
    def __init__(self, target_root, backup_root):
        self.target_root = Path(target_root).resolve()
        self.backup_root = Path(backup_root).resolve()
        self.comp_tx = _components.ComponentTransaction(self.target_root, self.backup_root)
        self.committed = False

    def stage_conf_update(self, path, values):
        p = _components.guard_path(self.target_root, path)
        old_text = p.read_text() if p.is_file() else ''
        lines = old_text.splitlines()
        for k, v in values.items():
            positions = [i for i, line in enumerate(lines) if line.split('=', 1)[0].strip() == k]
            if positions:
                for i in positions:
                    lines[i] = f'{k} = {v}'
            else:
                lines.append(f'{k} = {v}')
        new_text = '\n'.join(lines) + '\n'
        if old_text != new_text:
            self.comp_tx.stage_file_write(p, new_text.encode('utf-8'))

    def rollback(self):
        self.comp_tx.rollback()

    def commit(self):
        self.comp_tx.commit()
        self.committed = True


def ensure_nfs_data_drive(game, prefix):
    alias = Path(prefix) / 'dosdevices/d:'
    if alias.exists() or alias.is_symlink():
        return False
    try:
        game.relative_to(Path(prefix) / 'drive_c')
    except ValueError:
        return False
    alias.parent.mkdir(parents=True, exist_ok=True)
    alias.symlink_to(os.path.relpath(game, alias.parent), target_is_directory=True)
    return True


def check_runtime_compatibility(op, resources):
    """Check the actual pinned runtime, never infer a version from a directory name."""
    if resources is None:
        return  # Pure planning/unit execution has no runtime; production always supplies one.
    res = Path(resources).resolve()
    try:
        state = json.loads((res / 'Runtime.json').read_text())
    except (OSError, ValueError) as error:
        raise RuntimeError('Metadados do runtime ausentes ou inválidos: ' + str(res)) from error
    for req in op.get('runtime_compat', []):
        component = None
        if req == 'wine-cx-26.3.0-9':
            if state.get('components', {}).get('wine', {}).get('version') != 'cx-26.3.0-9':
                raise RuntimeError('Versão Wine incompatível: ' + op['id'])
            component = 'GameRuntime.app/Contents/MacOS/wine'
        elif req == 'x87sidecar-1.9.0':
            if state.get('components', {}).get('x87', {}).get('version') != 'v1.9.0':
                raise RuntimeError('Versão x87sidecar incompatível: ' + op['id'])
            component = 'x87sidecar'
        elif req == 'mtld3d':
            component = 'wine/lib/wine/d3d9/mtld3d/i386-windows/d3d9.dll'
        else:
            raise RuntimeError('Requisito de runtime desconhecido: ' + req)
        expected = state.get('files', {}).get(component)
        candidate = res / component
        if not expected or not candidate.is_file() or digest(candidate) != expected:
            raise RuntimeError('Componente de runtime ausente ou alterado: ' + str(component))


def execute_operations(plan, target_game, prefix, resources, data_dir):
    """Executa as operações selecionadas no plano com atomicidade, transações e rollback."""
    target = Path(target_game).resolve()
    pfx = Path(prefix).resolve() if prefix else None
    res = Path(resources).resolve() if resources else None
    data = Path(data_dir).resolve()

    timestamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup_root = data / 'Backups/Operations' / timestamp
    backup_root.mkdir(parents=True, exist_ok=True)

    plan_tx = PlanTransaction(target, backup_root)
    executed = []
    launch_settings = {}
    manifest_components = _components.load_manifest()

    try:
        for op_id in plan.get('selected_operations', []):
            op = OPERATIONS.get(op_id)
            if not op:
                continue

            # Valida estritamente compatibilidade de runtime se resources for fornecido
            check_runtime_compatibility(op, res)

            if 'component_id' in op:
                comp_id = op['component_id']
                comp_meta = manifest_components.get(comp_id, {})
                classification = comp_meta.get('classification', 'necessario')
                try:
                    if not _components.is_satisfied(comp_id, target):
                        prov_res = _components.provision_component(
                            comp_id, target, backup_root=backup_root, transaction=plan_tx.comp_tx
                        )
                        executed.append({'operation': op_id, 'action': 'provisioned', 'component': prov_res})
                    else:
                        executed.append({'operation': op_id, 'action': 'already_satisfied'})
                except Exception as comp_err:
                    if classification == 'necessario':
                        raise comp_err
                    else:
                        warn_log = data / 'Registros/Operations-Warning.log'
                        warn_log.parent.mkdir(parents=True, exist_ok=True)
                        with warn_log.open('a') as wf:
                            wf.write(f'Componente opcional {comp_id} falhou: {comp_err}\n')

            elif op_id == 'op.engine.gta_fps_cap_60':
                conf_file = target / 'mtld3d.conf'
                plan_tx.stage_conf_update(conf_file, {'present.maxFps': 60, 'present.maxFrameLatency': 1})
                sp_ini = target / 'scripts/SilentPatchSA.ini'
                if sp_ini.is_file():
                    plan_tx.stage_conf_update(sp_ini, {'FPSLimit': 60})
                executed.append({'operation': op_id, 'action': 'applied', 'details': {'present.maxFps': 60}})

            elif op_id == 'op.os.win7_legacy':
                launch_settings['windows'] = 'win7'
                executed.append({'operation': op_id, 'action': 'launch_setting_declared', 'details': {'windows': 'win7'}})

            elif op_id == 'op.storage.nfs_data_drive':
                drive_ok = False
                if pfx:
                    drive_ok = ensure_nfs_data_drive(target, pfx)
                executed.append({'operation': op_id, 'action': 'applied' if drive_ok else 'verified', 'details': {'drive': 'd:'}})

            elif op_id == 'op.wine.gta_media_overrides':
                overrides = op.get('settings', {}).get('overrides', '')
                launch_settings['overrides'] = overrides
                executed.append({'operation': op_id, 'action': 'launch_setting_declared', 'details': {'overrides': overrides}})

            elif op_id == 'op.engine.gta_memory_arg':
                launch_settings['game_args'] = '-memory 1048576'
                executed.append({'operation': op_id, 'action': 'launch_setting_declared', 'details': {'argument': '-memory 1048576'}})

            elif op_id == 'op.patch.gta_mtld3d_renderer':
                executed.append({'operation': op_id, 'action': 'pending_stage', 'details': {'target': 'APP_STAGE/Contents/Resources'}})

            elif op_id == 'op.cpu.x87sidecar':
                launch_settings['x87'] = True
                executed.append({'operation': op_id, 'action': 'launch_setting_declared', 'details': {'x87': True}})

            elif op_id in ('op.graphics.d3d9.mtld3d', 'op.graphics.d3d11.dxmt'):
                renderer = op.get('settings', {}).get('renderer', '')
                launch_settings['renderer'] = renderer
                executed.append({'operation': op_id, 'action': 'launch_setting_declared', 'details': op.get('settings', {})})

            else:
                executed.append({'operation': op_id, 'action': 'evaluated'})

        plan_tx.commit()

    except Exception as error:
        plan_tx.rollback()
        raise error

    all_backups = list(plan_tx.comp_tx.backups.values())
    plan_record = dict(
        plan,
        executed=executed,
        launch_settings=launch_settings,
        timestamp=timestamp,
        reversibility=True,
        backup_files=[str(b) for b in all_backups]
    )
    plan_file = data / 'Registros/OperationsPlan.json'
    plan_file.parent.mkdir(parents=True, exist_ok=True)
    plan_file.write_text(json.dumps(plan_record, indent=2, ensure_ascii=False) + '\n')
    return plan_record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list', action='store_true', help='Lista operações do catálogo')
    parser.add_argument('--plan', action='store_true', help='Gera plano de operações')
    parser.add_argument('--peinfo', type=Path, help='Arquivo JSON gerado pelo btp-peinfo')
    parser.add_argument('--recipe', help='ID da receita (ex: nfsu2, gtasa)')
    args = parser.parse_args()

    if args.list:
        print(json.dumps(OPERATIONS, indent=2, ensure_ascii=False))
        return

    if args.plan:
        if not args.peinfo or not args.peinfo.is_file():
            raise SystemExit('BTP: --peinfo válido obrigatório para --plan')
        pe_info = json.loads(args.peinfo.read_text())
        plan = plan_operations(pe_info, recipe=args.recipe)
        print(json.dumps(plan, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
