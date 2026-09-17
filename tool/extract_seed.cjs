// 从原始清单提取静态任务，保留阶段、难度和说明。
const fs = require('fs');
const vm = require('vm');
const html = fs.readFileSync('../project-progress.html', 'utf8');
const source = html.match(/const phases = (\[[\s\S]*?\n\]);/)[1];
const phases = vm.runInNewContext(source);
fs.mkdirSync('assets', {recursive: true});
fs.writeFileSync('assets/seed.json', JSON.stringify(phases, null, 2));
