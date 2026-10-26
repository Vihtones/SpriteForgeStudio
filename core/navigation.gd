extends RefCounted
const World = preload("res://core/world_data.gd")

func analyze_project(project: Dictionary) -> Dictionary:
	World.sync_active_room(project)
	var adjacency: Dictionary = {}
	for room in project.rooms:
		var data: Dictionary = room.data
		var width := int(data.width)
		for index in width * int(data.height):
			if data.collision[index]: continue
			var key: String = str(room.id) + ":" + str(index)
			adjacency[key] = []
		for index in width * int(data.height):
			var key: String = str(room.id) + ":" + str(index)
			if not adjacency.has(key): continue
			var p := Vector2i(index % width, int(index / width))
			for delta in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var q: Vector2i = p + delta
				if World.inside(data, q):
					var next: String = str(room.id) + ":" + str(q.y * width + q.x)
					if adjacency.has(next): adjacency[key].append(next)
		for door in data.get("doors", []):
			var a: String = str(room.id) + ":" + str(int(door.a[1]) * width + int(door.a[0]))
			var b: String = str(room.id) + ":" + str(int(door.b[1]) * width + int(door.b[0]))
			if adjacency.has(a) and adjacency.has(b): adjacency[a].append(b); adjacency[b].append(a)
	for connection in project.get("connections", []):
		var room_a: Dictionary = project.rooms.filter(func(r): return r.id == connection.a.room)[0]
		var room_b: Dictionary = project.rooms.filter(func(r): return r.id == connection.b.room)[0]
		var width_a := int(room_a.data.width)
		var width_b := int(room_b.data.width)
		var a_point: Array = connection.a.point
		var b_point: Array = connection.b.point
		var a: String = str(room_a.id) + ":" + str(int(a_point[1]) * width_a + int(a_point[0]))
		var b: String = str(room_b.id) + ":" + str(int(b_point[1]) * width_b + int(b_point[0]))
		if adjacency.has(a) and adjacency.has(b): adjacency[a].append(b); adjacency[b].append(a)
	var visited := {}
	var components: Array = []
	for start in adjacency.keys():
		if visited.has(start): continue
		var pending: Array = [start]
		visited[start] = true
		var count := 0
		while not pending.is_empty():
			var current: String = pending.pop_back()
			count += 1
			for next in adjacency[current]:
				if not visited.has(next): visited[next] = true; pending.append(next)
		components.append(count)
	components.sort()
	components.reverse()
	return {"rooms": project.rooms.size(), "walkable": adjacency.size(), "components": components, "connected": components.size() == 1}

func analyze(map: Dictionary) -> Dictionary:
	var visited := {}
	var components: Array = []
	var width := int(map.width)
	var height := int(map.height)
	var door_links := {}
	for door in map.get("doors", []):
		var a := int(door.a[1]) * width + int(door.a[0])
		var b := int(door.b[1]) * width + int(door.b[0])
		door_links[a] = b
		door_links[b] = a
	for start in width * height:
		if map.collision[start] or visited.has(start): continue
		var pending: Array = [start]
		visited[start] = true
		var count: int = 0
		while not pending.is_empty():
			var index: int = int(pending.pop_back())
			count += 1
			var p := Vector2i(index % width, int(index / width))
			for delta in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var q: Vector2i = p + delta
				if q.x < 0 or q.x >= width or q.y < 0 or q.y >= height: continue
				var next: int = q.y * width + q.x
				if not map.collision[next] and not visited.has(next): visited[next] = true; pending.append(next)
			if door_links.has(index):
				var destination: int = int(door_links[index])
				if not map.collision[destination] and not visited.has(destination): visited[destination] = true; pending.append(destination)
		components.append(count)
	components.sort()
	components.reverse()
	return {"walkable": visited.size(), "components": components, "connected": components.size() == 1, "isolated_cells": components.filter(func(count): return count == 1).size()}

func polygon(map: Dictionary) -> NavigationPolygon:
	var polygon := NavigationPolygon.new()
	polygon.agent_radius = 0
	var vertices := PackedVector2Array()
	var indices := {}
	var polygons: Array = []
	for y in int(map.height):
		for x in int(map.width):
			if map.collision[y * int(map.width) + x]: continue
			var corners := PackedInt32Array()
			for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var key: Vector2i = Vector2i(x, y) + offset
				if not indices.has(key): indices[key] = vertices.size(); vertices.append(Vector2(key) * 24)
				corners.append(indices[key])
			polygons.append(corners)
	polygon.vertices = vertices
	for corners in polygons: polygon.add_polygon(corners)
	return polygon
