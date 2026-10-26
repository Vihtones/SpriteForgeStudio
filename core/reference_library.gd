extends RefCounted
const STATES = ["imported", "analyzed", "review", "approved", "partial", "archived", "rejected"]

func normalize(reference: Dictionary) -> Dictionary:
	var r := reference.duplicate(true)
	if not r.has("id"): r.id = str(r.sha256).left(24)
	if not r.has("state"): r.state = "imported"
	if not r.has("features"): r.features = {"palette": "pending", "lighting": "pending", "anatomy": "pending", "materials": "pending"}
	if not r.has("license"): r.license = "não informada"
	if not r.has("source"): r.source = r.get("provenance", "não informada")
	if not r.has("confidence"): r.confidence = 0.0
	if not r.has("dependents"): r.dependents = []
	return r

func transition(doc: RefCounted, index: int, state: String, feature: String = "") -> Array:
	if doc.art.locked or index < 0 or index >= doc.art.references.size() or not STATES.has(state): return []
	doc.checkpoint()
	var r: Dictionary = normalize(doc.art.references[index])
	r.state = state
	if feature != "" and r.features.has(feature): r.features[feature] = "approved" if state in ["approved", "partial"] else "rejected"
	if state == "approved":
		for key in r.features: r.features[key] = "approved"
	if state == "rejected":
		for key in r.features: r.features[key] = "rejected"
		for candidate in doc.art.candidates:
			if candidate.get("references", []).has(r.id): candidate.status = "invalidated"
		for rule in doc.art.memory:
			if rule.get("references", []).has(r.id): rule.status = "invalidated"
		for relation in doc.manifest.dependencies:
			if relation.get("source") == r.id: relation["stale"] = true
	doc.art.references[index] = r
	return r.dependents.duplicate()

func eligible(doc: RefCounted, feature: String) -> Array:
	var selected: Array = []
	for reference in doc.art.references:
		var r := normalize(reference)
		if r.state in ["approved", "partial"] and r.features.get(feature) == "approved": selected.append(r)
	return selected

func link(doc: RefCounted, index: int) -> bool:
	if doc.art.locked or index < 0 or index >= doc.art.references.size(): return false
	var r: Dictionary = normalize(doc.art.references[index])
	if r.state not in ["approved", "partial"]: return false
	doc.checkpoint()
	if not r.dependents.has(doc.manifest.id): r.dependents.append(doc.manifest.id)
	doc.art.references[index] = r
	for relation in doc.manifest.dependencies:
		if relation.source == r.id and relation.target == doc.manifest.id: relation.stale = false; return true
	doc.manifest.dependencies.append({"source": r.id, "target": doc.manifest.id, "stale": false})
	return true
