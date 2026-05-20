# Hermes Agent — Configuración Personal

Configuración de Hermes Agent para orquestación multi-agente. Este repositorio contiene la configuración, memorias y skills que definen el comportamiento del agente.

## Estructura

```
.hermes/
├── SOUL.md              # Definición del agente líder (orquestador)
├── MEMORY.md            # Memorias persistentes del proyecto actual
├── USER.md              # Preferencias y contexto del usuario
├── config.yaml          # Configuración principal de Hermes
├── .env                 # Variables de entorno (API keys)
├── hermes-agent/         # Código fuente de Hermes Agent
├── skills/              # Skills activos
│   ├── browser-use -> ~/.agents/skills/browser-use
│   ├── prisma-cli -> ~/.agents/skills/prisma-cli
│   ├── prisma-client-api -> ~/.agents/skills/prisma-client-api
│   └── ... otros skills
├── memories/            # Memorias de sesión
├── sessions/            # Historial de conversaciones
├── checkpoints/         # Snapshots de estado
├── logs/                # Logs del agente
├── bin/tirith           # Binario ejecutable
└── images/              # Recursos multimedia
```

## Agentes y Orquestación

El sistema usa **4 perfiles** definidos en `.hermes/profiles/`:

### Leader (`SOUL.md`)

- **Rol**: Orquestador
- **Responsabilidad**: Descompone tareas, lanza sub-agentes, nunca escribe código
- **Delegación**: Asigna features a `coder`, `reviewer` o `researcher`

### Coder (`profiles/coder/SOUL.md`)

- **Rol**: Implementador
- **Responsabilidad**: Implementa UNA feature por sesión, escribe tests, se autoverifica
- **Scope**: Solo código dentro del `acceptance` criteria de la feature
- **Flujo**: pending → in_progress → review → done

### Reviewer (`profiles/reviewer/SOUL.md`)

- **Rol**: Revisor automático
- **Responsabilidad**: Aprueba o rechaza contra `docs/*.md` y `CHECKPOINTS.md`
- **Veredicto**: `APPROVED` o `CHANGES_REQUESTED` en `.hermes/progress/review.md`
- **Regla**: Nunca aprueba con tests rojos o errores de lint/typecheck

### Researcher (`profiles/researcher/SOUL.md`)

- **Rol**: Investigador
- **Responsabilidad**: Explora codebases, analiza arquitectura, responde preguntas técnicas
- **Salida**: Reporte estructurado en `.hermes/progress/research.md`
- **Regla**: Solo lee e investiga, nunca edita código

### Flujo de Orquestación

```
Leader recibe tarea
    ↓
Divide en features (feature_list.json)
    ↓
Lanza en PARALELO según capacidad:
  ├── coder     → implementa feature
  ├── reviewer  → aprueba/rechaza
  └── researcher → investiga si hay dudas
    ↓
Tracking: .hermes/progress/current.md
```

## Comandos

```bash
hermes              # Iniciar CLI interactivo
hermes gateway      # Iniciar gateway de mensajería
hermes model        # Seleccionar modelo
hermes tools        # Configurar tools activos
hermes logs         # Ver logs del agente
hermes config set   # Modificar configuración

# Profiles (gestión de instancias aisladas)
hermes profile list              # Listar todos los profiles
hermes profile use <nombre>     # Establecer profile por defecto
hermes profile create <nombre>  # Crear nuevo profile
hermes profile delete <nombre>  # Eliminar profile
hermes profile show <nombre>    # Ver detalles de un profile
hermes profile info <nombre>    # Ver distribución y versión de un profile
hermes profile describe <nombre> # Leer o establecer descripción del profile

# Kanban (tablero de tareas SQLite compartido entre profiles)
hermes kanban init                        # Crear kanban.db si no existe
hermes kanban boards                      # Gestionar tableros (proyectos/workstreams)
hermes kanban list                         # Listar tareas
hermes kanban create <título>             # Crear nueva tarea
hermes kanban show <id>                   # Ver tarea con comentarios y eventos
hermes kanban claim <id>                  # Reclamar atomicamente una tarea lista
hermes kanban assign <id> <profile>       # Asignar tarea a un profile
hermes kanban reassign <id> <profile>     # Reasignar tarea
hermes kanban reclaim <id>                # Liberar claim activo de una tarea en ejecución
hermes kanban link <parent_id> <child_id> # Añadir dependencia padre->hijo
hermes kanban unlink <parent_id> <child_id> # Remover dependencia
hermes kanban complete <id>               # Marcar tarea(s) como completada
hermes kanban block <id>                  # Marcar tarea(s) como bloqueada
hermes kanban unblock <id>                # Desbloquear tarea(s)
hermes kanban archive <id>                # Archivar tarea(s)
hermes kanban edit <id>                   # Editar campos de recuperación
hermes kanban comment <id> <texto>        # Añadir comentario
hermes kanban tail <id>                   # Seguir evento stream de tarea en vivo
hermes kanban stats                       # Estadísticas por estado y asignado
hermes kanban assignees                   # Listar profiles conocidos y sus cuentas
hermes kanban context <id>                # Ver contexto completo que ve un worker
hermes kanban specify <id>                 # Detallar tarea triage en spec concreto
hermes kanban decompose <id>              # Descomponer tarea triage en sub-tareas
hermes kanban dispatch                    # Una pasada del dispatcher: reclamar stale, promover ready, spawn workers
hermes kanban watch                       # Live-stream de eventos al terminal (Ctrl+C)
hermes kanban gc                          # Limpiar workspaces archivados, eventos y logs antiguos
hermes kanban --board <slug>              # Operar en tablero específico
```

## Skills Disponibles

- **browser-use**: Automatización de navegador
- **nuxt / nuxt-ui**: Desarrollo Nuxt 4+
- **prisma-cli / prisma-client-api**: Base de datos con Prisma
- **solid**: Calidad de código (SOLID, TDD)
- **vitest**: Testing con Vitest
- **vue**: Componentes Vue 3

## Orquestación Multi-Agente

```
1. Leader descompone tarea en features (feature_list.json)
2. Asigna según capacidad: coder | reviewer | researcher
3. Ejecutan en paralelo
4. Progress guardado en .hermes/progress/
```

**Reglas del Leader:**

- Nunca escribe código directamente
- Resultados de sub-agentes van a archivos en `.hermes/progress/`
- Solo delega, no implementa

**Reglas de Coder:**

- Una feature por sesión
- Incluye tests con cada implementación
- No marca `done` — lo hace tras approval del reviewer

**Reglas de Reviewer:**

- Compara contra `docs/*.md` y `CHECKPOINTS.md`
- Solo approve si tests pasan y no hay errores de lint/typecheck
- Nunca edita código del implementador

## Referencias

- [Documentación Hermes Agent](https://hermes-agent.nousresearch.com/docs/)
- [Skills Hub](https://agentskills.io)
- [Nous Research](https://nousresearch.com)
