-- Server -> client visual effects. The server decides *what* happened; every
-- client draws smoke, tracers, grenades and cannonballs locally.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FX = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local effectRemote = remotes:WaitForChild("Effect") :: RemoteEvent
local announceRemote = remotes:WaitForChild("Announce") :: RemoteEvent

-- One musket discharge: smoke at the muzzle plus a tracer to each ball's end.
function FX.Shot(from: Vector3, ends: { Vector3 }, team: string)
	effectRemote:FireAllClients("Shot", from, ends, team)
end

function FX.Hit(pos: Vector3, isFlesh: boolean)
	effectRemote:FireAllClients("Hit", pos, isFlesh)
end

function FX.Grenade(from: Vector3, to: Vector3, duration: number)
	effectRemote:FireAllClients("Grenade", from, to, duration)
end

function FX.Explosion(pos: Vector3, radius: number)
	effectRemote:FireAllClients("Explosion", pos, radius)
end

function FX.CannonWarn(from: Vector3, to: Vector3, duration: number)
	effectRemote:FireAllClients("CannonWarn", from, to, duration)
end

-- Red danger circle on the ground (where a grenade will land).
function FX.Marker(pos: Vector3, radius: number, duration: number)
	effectRemote:FireAllClients("Marker", pos, radius, duration)
end

function FX.Cannonball(from: Vector3, to: Vector3, duration: number)
	effectRemote:FireAllClients("Cannonball", from, to, duration)
end

function FX.Slash(pos: Vector3, dir: Vector3)
	effectRemote:FireAllClients("Slash", pos, dir)
end

function FX.Announce(text: string, color: Color3?, target: Player?)
	if target then
		announceRemote:FireClient(target, text, color)
	else
		announceRemote:FireAllClients(text, color)
	end
end

return FX
