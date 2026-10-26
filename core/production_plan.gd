extends RefCounted
## Deterministic dependency graph. Unknown production is never invented.
func plan(request: String, approved_available: bool = false) -> Dictionary:
	return {"schema": 1, "request": request, "route": "reuse" if approved_available else "deterministic", "tasks": [
		{"id": "inspect", "skill": "SFS-02", "dependencies": [], "status": "queued"},
		{"id": "compose", "skill": "SFS-06", "dependencies": ["inspect"], "status": "queued"},
		{"id": "validate", "skill": "SFS-12", "dependencies": ["compose"], "status": "queued"},
		{"id": "approve", "skill": "SFS-12", "dependencies": ["validate"], "status": "awaiting_approval"},
		{"id": "export", "skill": "SFS-16", "dependencies": ["approve"], "status": "queued"}]}

func validate(tasks: Array) -> Array[String]:
	var errors: Array[String] = []
	var nodes := {}
	for task in tasks:
		if not task is Dictionary or not task.has_all(["id", "dependencies", "status"]): errors.append("Tarefa inválida"); return errors
		if nodes.has(task.id): errors.append("ID duplicado: " + task.id)
		nodes[task.id] = task
	for task in tasks:
		for dependency in task.dependencies:
			if not nodes.has(dependency): errors.append("Dependência ausente: " + dependency)
	var visited := {}
	var active := {}
	for id in nodes:
		if _cycle(id, nodes, visited, active): errors.append("Ciclo de dependências"); break
	return errors

func _cycle(id: String, nodes: Dictionary, visited: Dictionary, active: Dictionary) -> bool:
	if active.has(id): return true
	if visited.has(id) or not nodes.has(id): return false
	active[id] = true
	for dependency in nodes[id].dependencies:
		if _cycle(dependency, nodes, visited, active): return true
	active.erase(id)
	visited[id] = true
	return false

func ready(tasks: Array) -> Array:
	if not validate(tasks).is_empty(): return []
	var completed := {}
	for task in tasks:
		if task.status == "completed": completed[task.id] = true
	return tasks.filter(func(task): return task.status == "queued" and task.dependencies.all(func(id): return completed.has(id)))
