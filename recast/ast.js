
        import { transformSync, parseSync, printSync } from '@swc/core';
        import fs from 'fs';
        
        export async function runASTEdit(file, key, olamaFn) {
          const code = fs.readFileSync(file, 'utf8');
          const ast = parseSync(code, { syntax: 'ecmascript' });
          const suggestions = await olamaFn(ast, key);
          // Apply suggestions to AST (stub)
          // ...
          const newCode = printSync(ast).code;
          fs.writeFileSync(file, newCode, 'utf8');
          console.log('Code updated via AST!');
        }
    
