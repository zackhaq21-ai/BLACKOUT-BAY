import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=f=>fs.readFileSync(path.join(root,'tests',f),'utf8');
const luaString=s=>'[====['+s+']====]';
const counts=process.argv.slice(2).map(Number); if(!counts.length)counts.push(1);
if(counts.some(n=>!Number.isInteger(n)||n<1||n>5))throw Error('Crew counts must be 1–5');
const script = [
 'assert(game:GetService("RunService"):IsStudio())',
 'if not game:GetService("RunService"):IsEdit() then while task.wait(5) do end end',
 'local testService=game:GetService("StudioTestService")',
 'local server=game.ServerScriptService.GlasshouseServer',
 'server.Main.Source = server.Main.Source .. "\\n" .. '+luaString(read('engine_hooks.luau')),
 'server.World.Source = server.World.Source:gsub("local World = {}", "local World = {_engineCallbacks = {}}", 1)',
 'local before = '+luaString('prompt.Parent = p; prompt.Triggered:Connect(function(player) callback(player, p, duration, prompt) end)'),
 'local after = '+luaString('prompt.Parent = p; local handler = function(player) callback(player, p, duration, prompt) end; World._engineCallbacks[prompt] = handler; prompt.Triggered:Connect(handler)'),
 'local source=server.World.Source; local startAt,endAt=source:find(before,1,true); assert(startAt,"Prompt patch anchor missing")',
 'server.World.Source = source:sub(1,startAt-1)..after..source:sub(endAt+1)',
 'local control=Instance.new("RemoteEvent");control.Name="EngineControl";control.Parent=game.ReplicatedStorage.Glasshouse',
 'local driver=Instance.new("Script");driver.Name="EngineDriver";driver.Source='+luaString(read('engine_driver.server.luau'))+';driver.Parent=game.ServerScriptService',
 'local client=Instance.new("LocalScript");client.Name="EngineDriver";client.Source='+luaString(read('engine_driver.client.luau'))+';client.Parent=game.StarterPlayer.StarterPlayerScripts',
 'for _, count in ipairs({'+counts.join(',')+'}) do',
 'print("GLASSHOUSE_ENGINE_BEGIN",count)',
 'local result = count == 1 and testService:ExecutePlayModeAsync({glasshouse=true,count=count}) or testService:ExecuteMultiplayerTestAsync(count,{glasshouse=true,count=count})',
 'print("GLASSHOUSE_ENGINE_RESULT",game.HttpService:JSONEncode(result))',
 'assert(type(result)=="table" and result.ok, "Engine scenario failed")',
 'end',
 'print("GLASSHOUSE_ENGINE_ALL_PASSED")'
].join('\n');
fs.writeFileSync(path.join(root,'tests','engine_runner.generated.luau'),script);
fs.copyFileSync(path.join(root,'dist','BlackoutBay.rbxlx'),path.join(root,'dist','BlackoutBay-EngineTest.rbxlx'));
console.log('Built isolated Studio integration tests for '+counts.join(',')+' players.');
