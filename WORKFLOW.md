# Hermes Harness — Workflow Reference

> Documento estructurado para interpretación directa por modelos de lenguaje.
> Cada agente debe consultar este archivo como referencia única del workflow.

---

## State Machine — Kanban Board

```
┌─────────────────────────────────────────────────────────────────┐
│  INBOX  │  TODO  │ IN_PROGRESS │  REVIEW  │   DONE   │ BLOCKED  │
└─────────┴────────┴─────────────┴──────────┴──────────┴──────────┘
```

| Estado | Entrada | Salida | Acción |
|--------|---------|--------|--------|
| INBOX | subagentes (reportes) | ARCHIVE | Leader procesa → archiva |
| TODO | Leader crea | IN_PROGRESS | Leader asigna a subagente |
| IN_PROGRESS | TODO (claim) | REVIEW / DONE / BLOCKED | Subagente trabaja → reporta |
| REVIEW | IN_PROGRESS | DONE / TODO | Reviewer aprueba o pide correcciones |
| DONE | REVIEW / IN_PROGRESS | ARCHIVE | Validado → archivar |
| BLOCKED | cualquier | TODO | Leader resuelve → reabre |

---

## Perfiles y sus Estados

| Perfil | Estado interno | Envía a Leader | Comando reporting |
|--------|---------------|----------------|-------------------|
| **leader** | receiving | - | - |
| **coder** | DONE, BLOCKED | INBOX | create → assign → complete/block |
| **reviewer** | APPROVED, CHANGES_REQUESTED, BLOCKED | INBOX | create → assign → complete/unblock |
| **researcher** | DONE, BLOCKED | INBOX | create → assign → complete/block |
| **assistant** | DONE, BLOCKED | INBOX | create → assign → complete/block |

---

## Command Protocol — Reportar al Leader

### Paso 1: Crear tarea de reporte
```bash
hermes kanban create "<ESTADO> -> TASK-<XXX>: <resumen>"
```

### Paso 2: Asignar al leader (tarea va a INBOX)
```bash
hermes kanban assign <nuevo_id> leader
```

### Paso 3: Cerrar tarea original
```bash
hermes kanban complete <id_original>      # si DONE/APPROVED
hermes kanban block <id_original>         # si BLOCKED
hermes kanban unblock <id_original>       # si CHANGES_REQUESTED (vuelve a TODO)
```

---

## Estados de Mensaje por Perfil

### coder
| Mi estado | Título tarea reporte | Acción original |
|-----------|---------------------|-----------------|
| DONE | `DONE -> TASK-XXX: resumen` | `hermes kanban complete` |
| BLOCKED | `BLOCKED -> TASK-XXX: causa` | `hermes kanban block` |

### reviewer
| Mi estado | Título tarea reporte | Acción original |
|-----------|---------------------|-----------------|
| APPROVED | `APPROVED -> TASK-XXX: resumen` | `hermes kanban complete` |
| CHANGES_REQUESTED | `CHANGES_REQUESTED -> TASK-XXX: feedback` | `hermes kanban unblock` |
| BLOCKED | `BLOCKED -> TASK-XXX: causa` | `hermes kanban block` |

### researcher
| Mi estado | Título tarea reporte | Acción original |
|-----------|---------------------|-----------------|
| DONE | `DONE -> TASK-XXX: resumen` | `hermes kanban complete` |
| BLOCKED | `BLOCKED -> TASK-XXX: causa` | `hermes kanban block` |

### assistant
| Mi estado | Título tarea reporte | Acción original |
|-----------|---------------------|-----------------|
| DONE | `DONE -> TASK-XXX: resumen` | `hermes kanban complete` |
| BLOCKED | `BLOCKED -> TASK-XXX: causa` | `hermes kanban block` |

---

## Flujo Completo de una Tarea

```
1. Leader crea tarea
   hermes kanban create "Implementar feature X"
   hermes kanban assign <id> coder

2. Coder reclama
   hermes kanban claim <id>
   → La tarea pasa a IN_PROGRESS

3. Coder trabaja y reporta
   hermes kanban create "DONE -> TASK-XXX: feature X completada"
   hermes kanban assign <nuevo_id> leader
   hermes kanban complete <id_original>
   → Tarea original pasa a DONE, reporte va a INBOX del leader

4. Leader procesa INBOX
   hermes kanban list | grep leader
   hermes kanban show <id_reporte>
   hermes kanban archive <id_reporte>
```

---

## Query Rápidas

```bash
# Ver tareas en INBOX del leader
hermes kanban list | grep leader

# Ver todas mis tareas (reemplazar coder por el perfil)
hermes kanban list | grep coder

# Ver tareas en REVIEW
hermes kanban list | grep REVIEW

# Ver tareas bloqueadas
hermes kanban list | grep BLOCKED

# Ver estadísticas del board
hermes kanban stats
```

---

## Reglas de WIP Limit

| Perfil | WIP Limit |
|--------|-----------|
| coder | 3 |
| reviewer | 2 |
| researcher | 2 |
| assistant | 2 |
| leader | 5 |

---

## Flags del Leader

- `DONE -> TASK-XXX` — Aprobar, archivar reporte
- `APPROVED -> TASK-XXX` — Aprobar, archivar reporte
- `CHANGES_REQUESTED -> TASK-XXX` — Revisar feedback, reasignar a coder
- `BLOCKED -> TASK-XXX` — Resolver impedimento, reabrir tarea

---

*Este documento es la referencia autoritativa del workflow. Los SOUL.md de cada perfil derivan de estas reglas.*