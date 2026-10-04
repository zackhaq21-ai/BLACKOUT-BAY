import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
let ref = 0;
const escape = value => String(value).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
const prop = (type, name, value) => '<'+type+' name="'+name+'">'+escape(value)+'</'+type+'>';
const item = (type, name, properties = '', children = '') => '<Item class="'+type+'" referent="RBX'+(++ref)+'"><Properties>'+prop('string','Name',name)+properties+'</Properties>'+children+'</Item>';
const sourceFile = (folder, filename) => fs.readFileSync(path.join(root, 'src', folder, filename), 'utf8');
function script(folder, file, type, name) {
  return item(type, name, prop('ProtectedString', 'Source', sourceFile(folder, file)));
}
const shared = item('ReplicatedStorage', 'ReplicatedStorage', '', item('Folder', 'Glasshouse', '',
  script('shared','Config.luau','ModuleScript','Config') + script('shared','Rules.luau','ModuleScript','Rules')));
const serverFiles = fs.readdirSync(path.join(root,'src','server')).sort();
const server = item('ServerScriptService','ServerScriptService','',item('Folder','GlasshouseServer','',
  serverFiles.map(file => script('server',file,file.endsWith('.server.luau') ? 'Script':'ModuleScript',file.replace(/(\.server)?\.luau$/,''))).join('')));
const starter = item('StarterPlayer','StarterPlayer',
  prop('float','CameraMaxZoomDistance',45)+prop('float','CameraMinZoomDistance',5),
  item('StarterPlayerScripts','StarterPlayerScripts','',script('client','HUD.client.luau','LocalScript','HUD')));
const vector = (name,x,y,z) => '<Vector3 name="'+name+'"><X>'+x+'</X><Y>'+y+'</Y><Z>'+z+'</Z></Vector3>';
const cf = (x,y,z) => '<CoordinateFrame name="CFrame"><X>'+x+'</X><Y>'+y+'</Y><Z>'+z+'</Z><R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>';
const color = '<Color3 name="Color"><R>0.08</R><G>0.16</G><B>0.21</B></Color3>';
const preview = item('Model','GlasshouseWorld','',item('Part','PRESS PLAY — GLASSHOUSE BUILDS HERE',
  prop('bool','Anchored','true')+vector('size',120,1,120)+cf(0,0,0)+color));
const workspace = item('Workspace','Workspace',prop('float','Gravity',196.2),preview);
const xml = '<?xml version="1.0" encoding="utf-8"?>\n<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4"><External>null</External><External>nil</External>'+workspace+shared+server+starter+item('Lighting','Lighting',prop('float','ClockTime',18.4))+'</roblox>\n';
fs.mkdirSync(path.join(root,'dist'),{recursive:true});
fs.writeFileSync(path.join(root,'dist','BlackoutBay.rbxlx'),xml);
const files = [];
for(const folder of ['shared','server','client']) for(const file of fs.readdirSync(path.join(root,'src',folder))) {
  const data=fs.readFileSync(path.join(root,'src',folder,file));
  files.push({file:'src/'+folder+'/'+file,bytes:data.length,sha256:crypto.createHash('sha256').update(data).digest('hex')});
}
fs.writeFileSync(path.join(root,'dist','manifest.json'),JSON.stringify({name:'Blackout Bay: Aurora Exchange',players:'1-5',commerceEnabled:false,dataStoresEnabled:false,place:'BlackoutBay.rbxlx',bytes:Buffer.byteLength(xml),files},null,2)+'\n');
console.log('Built dist/BlackoutBay.rbxlx ('+Buffer.byteLength(xml)+' bytes, '+files.length+' native Luau scripts).');
