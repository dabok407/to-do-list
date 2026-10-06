const fs=require('node:fs');
const files=['app-core.js','calendar-ui.js','editor-ui.js','ux-ui.js'];
fs.writeFileSync('app.js',files.map(f=>fs.readFileSync(f,'utf8')).join('\n')+'\nrender();\n');
console.log('Built app.js (no external dependencies)');
