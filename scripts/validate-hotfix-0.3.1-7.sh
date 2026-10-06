#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX_0317_CREATOR_QT_CALLBACK_GUARD_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 -m py_compile "$ROOT/src/mechos_ui/creator_shell.py"
bash -n "$ROOT/scripts/build-hotfix-0.3.1-7.sh"

grep -Fq 'MECHOS_CREATOR_QT_CALLBACK_GUARD_V27'   "$ROOT/src/mechos_ui/creator_shell.py"
grep -Fq 'CREATOR_RUNTIME_LOG' "$ROOT/src/mechos_ui/creator_shell.py"
grep -Fq 'def _run_guarded' "$ROOT/src/mechos_ui/creator_shell.py"

for callback in   '_timer_refresh_metrics'   '_timer_refresh_apps'   '_timer_refresh_projects'   '_timer_refresh_updates'   '_safe_read_update_output'   '_safe_update_finished'   '_safe_update_error'; do
  grep -Fq "$callback" "$ROOT/src/mechos_ui/creator_shell.py"
done

# Timer callbacks must not be connected directly to unguarded refresh methods.
! grep -Fq 'metric_timer.timeout.connect(self.refresh_metrics)'   "$ROOT/src/mechos_ui/creator_shell.py"
! grep -Fq 'app_timer.timeout.connect(self.refresh_apps)'   "$ROOT/src/mechos_ui/creator_shell.py"
! grep -Fq 'project_timer.timeout.connect(self.refresh_projects)'   "$ROOT/src/mechos_ui/creator_shell.py"
! grep -Fq 'update_timer.timeout.connect(self.refresh_updates)'   "$ROOT/src/mechos_ui/creator_shell.py"
! grep -Fq 'QTimer.singleShot(600, self.refresh_updates)'   "$ROOT/src/mechos_ui/creator_shell.py"

# Verify the guarded function actually swallows a callback exception without
# depending on a real Qt display. Extract the method body structurally.
python3 - "$ROOT/src/mechos_ui/creator_shell.py" <<'PY'
from pathlib import Path
import ast,sys
p=Path(sys.argv[1]); src=p.read_text(); tree=ast.parse(src)
cls=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='LiveCreatorHome')
guard=next(n for n in cls.body if isinstance(n,ast.FunctionDef) and n.name=='_run_guarded')
text=ast.get_source_segment(src,guard)
assert 'except Exception' in text
assert '_creator_log' in text
assert 'return None' in text
init=next(n for n in cls.body if isinstance(n,ast.FunctionDef) and n.name=='__init__')
init_text=ast.get_source_segment(src,init)
assert 'startup_update_timer = QTimer(self)' in init_text
assert 'setSingleShot(True)' in init_text
finished=next(n for n in cls.body if isinstance(n,ast.FunctionDef) and n.name=='_update_finished')
finished_text=ast.get_source_segment(src,finished)
assert 'self._update_proc = None' in finished_text
assert 'proc.deleteLater()' in finished_text
PY

grep -Fq 'mechos-strip-updater-from-stage-v1.sh'   "$ROOT/scripts/build-hotfix-0.3.1-7.sh"
grep -Fq 'validate-payload-only-hotfix-v1.sh'   "$ROOT/scripts/build-hotfix-0.3.1-7.sh"

echo 'MechOS 0.3.1 Hotfix 7 Creator Qt callback guard contracts validated.'
