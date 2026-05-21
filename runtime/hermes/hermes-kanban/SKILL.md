---
name: hermes-kanban
description: "Hermes Kanban: SQLite multi-agent work-queue. CLI para líderes/orquestadores, toolset para workers."
version: 1.0.0
author: Hermes Agent
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [kanban, multi-agent, task-queue, sqlite, collaboration]
    homepage: https://hermes-agent.nousresearch.com/docs/user-guide/features/kanban
---

# Hermes Kanban

SQLite shared board for multi-profile/multi-worker collaboration. Workers acceden via `kanban_*` toolset (gated). Leaders/orchestrators usan CLI via `terminal()`.

## Arquitectura

```
┌─────────────────────────────────────────────┐
│  Leader/Orquestador (yo)                    │
│  → hermes kanban CLI via terminal()         │
└─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────┐
│  Hermes Gateway (dispatcher cada 60s)       │
│  → Reclama stale, promueve ready,          │
│    lanza workers automaticamente             │
└─────────────────────────────────────────────┘
                    │
          ┌─────────┼─────────┐
          ▼         ▼         ▼
      [worker]  [worker]  [worker]
      coder     researcher reviewer
      → kanban_* toolset
```

## Rutas importantes

- DB: `~/.hermes/kanban.db`
- Perfiles disponibles: `assistant, coder, default, leader, researcher, reviewer`

## Comandos CLI (para líder/orchestrator)

### Inicialización

```bash
hermes kanban init          # Crear kanban.db si no existe
hermes kanban boards        # Listar/gestionar tableros
```

### Tareas

```bash
# Crear tarea en triage
hermes kanban create "Descripción de la tarea"

# Listar tareas (todos los estados)
hermes kanban list

# Ver detalle completo
hermes kanban show <id>

# Reclamar atomicamente (para workers)
hermes kanban claim <id>

# Asignar tarea a un profile
hermes kanban assign <id> <profile>

# Reasignar tarea
hermes kanban reassign <id> <profile>

# Liberar claim activo (desbloquear worker)
hermes kanban reclaim <id>

# Marcar como completada
hermes kanban complete <id>

# Bloquear/desbloquear
hermes kanban block <id>
hermes kanban unblock <id>

# Archivar tarea
hermes kanban archive <id>

# Editar campos de tarea
hermes kanban edit <id>
```

### Dependencias

```bash
hermes kanban link <parent_id> <child_id>    # Añadir dependencia
hermes kanban unlink <parent_id> <child_id>  # Remover dependencia
```

### Comunicación

```bash
hermes kanban comment <id> <texto>   # Añadir comentario
hermes kanban tail <id>              # Seguir evento stream en vivo
```

### Monitoreo

```bash
hermes kanban stats           # Estadísticas por estado y asignado
hermes kanban assignees       # Listar profiles y sus cuentas
hermes kanban context <id>    # Ver contexto completo que ve un worker
```

### Workflow

```bash
hermes kanban specify <id>    # Detallar tarea triage en spec concreto
hermes kanban decompose <id>  # Descomponer tarea triage en sub-tareas
hermes kanban dispatch        # Una pasada del dispatcher: reclamar stale, promover ready, spawn workers
hermes kanban watch           # Live-stream de eventos al terminal (Ctrl+C)
hermes kanban gc              # Limpiar workspaces archivados, eventos y logs antiguos
```

## Estados de tarea

```
triage → todo → ready → running → blocked → done
              ↑__________↑ (puede volver a ready si se desbloquea)
```

| Estado | Significado |
|--------|-------------|
| `triage` | Nueva, sin clasificar |
| `todo` | Clasificada, lista para planificar |
| `ready` | Lista para ser reclamada |
| `running` | En ejecución (claim activo) |
| `blocked` | Bloqueada por dependencia u otro motivo |
| `done` | Completada |

## Worker toolset (para subagentes workers)

Cuando un worker reclama una tarea (`hermes kanban claim <id>`), tiene acceso a:

- `kanban_show` — Ver detalle de tarea
- `kanban_complete` — Marcar como completada
- `kanban_block` — Bloquear tarea
- `kanban_heartbeat` — Señalar que sigue activo
- `kanban_comment` — Añadir comentario
- `kanban_create` — Crear subtarea
- `kanban_link` — Crear dependencia

## Ejemplo de uso en sesión

### Líder crea tarea y la asigna

```bash
# Crear tarea
hermes kanban create "Implementar endpoint /api/users"

# Asignar a coder
hermes kanban assign <task_id> coder

# Ver estado
hermes kanban list
```

### Worker reclama tarea

```bash
# El worker (subagente) reclama
hermes kanban claim <task_id>

# Trabaja...

# Marca como completada
hermes kanban complete <task_id>

# O bloquea si hay impedimento
hermes kanban block <task_id>
hermes kanban comment <task_id> "Bloqueado: esperando API key"
```

## Integración con delegate_task

Para delegar a un subagente que use el Kanban:

1. Crear tarea con `hermes kanban create`
2. Asignar con `hermes kanban assign <id> <profile>`
3. Incluir en el context del subagente: `task_id: <id>`
4. El subagente puede usar `hermes kanban claim <id>` si tiene el toolset `kanban`
5. Marcar completada con `hermes kanban complete <id>`

## Tableros múltiples

```bash
# Operar en tablero específico
hermes kanban --board <slug> list
hermes kanban --board <slug> create "Nueva tarea"
```

## Notas importantes

- El gateway debe estar corriendo (`hermes gateway start`) para que el dispatcher funcione
- El dispatcher corre cada 60s por defecto
- Si un worker no marca heartbeat, el dispatcher reclama la tarea automáticamente
- Las tareas bloqueadas no se promocionan a ready automáticamente