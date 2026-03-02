# Lua Scripting Fields Schema

Define exposed fields on your returned script table using a `Fields` table.

```lua
Rotate = {}

Rotate.Fields = {
  Speed = { type = "float", default = 45.0, min = 0.0, max = 720.0, step = 1.0, tooltip = "Degrees per second" },
  Axis = { type = "vec3", default = {0, 1, 0} },
  Local = { type = "bool", default = true },
  TargetEntity = { type = "entity", default = nil },
  TargetPrefab = { type = "prefab", default = nil }
}

return Rotate
```

Supported types:
- `bool`
- `int`
- `float`
- `vec2`
- `vec3`
- `color3`
- `string`
- `entity`
- `prefab`

Ordering:
- Array form is preferred for stable ordering.
- Keyed table supports optional `__order = { "FieldA", "FieldB" }`.

Persistence:
- Script field values are persisted in `ScriptComponent.fieldData` blob v1.
- Values are keyed by field name and remap by name when schema order changes.
- Missing blob entries fall back to schema defaults.
