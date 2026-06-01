#!/usr/bin/env tclsh
# gen.tcl - TCL script to generate project files for olama-ast-cli

set files {
    package.json {
        {
            "name": "olama-ast-cli",
            "version": "0.1.0",
            "description": "CLI tool for AST-based code editing with OLAMA agent integration",
            "main": "cli.js",
            "type": "module",
            "scripts": {
                "start": "node cli.js"
            },
            "dependencies": {
                "commander": "^11.0.0",
                "chalk": "^5.3.0",
                "@swc/core": "^1.3.92",
                "dotenv": "^16.4.5",
                "axios": "^1.6.8"
            }
        }
    }
    cli.js {
        #!/usr/bin/env node
        import { Command } from 'commander';
        import chalk from 'chalk';
        import { runASTEdit } from './ast.js';
        import { getKey } from './key.js';
        import { callOlama } from './olama.js';
        import dotenv from 'dotenv';
        dotenv.config();
        
        const program = new Command();
        program
          .name('olama-ast-cli')
          .description('CLI for AST-based code editing with OLAMA agent')
          .version('0.1.0');
        
        program
          .command('edit <file>')
          .description('Edit code using AST and OLAMA agent')
          .action(async (file) => {
            const key = getKey();
            await runASTEdit(file, key, callOlama);
          });
        
        program.parse(process.argv);
    }
    ast.js {
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
    }
    olama.js {
        import axios from 'axios';
        
        export async function callOlama(ast, key) {
          // Call local OLAMA agent with AST
          // Replace with actual endpoint/config
          const response = await axios.post('http://localhost:11434/api/ast', { ast }, {
            headers: { 'Authorization': `Bearer ${key}` }
          });
          return response.data.suggestions;
        }
    }
    key.js {
        import dotenv from 'dotenv';
        dotenv.config();
        
        export function getKey() {
          return process.env.OLAMA_API_KEY || '';
        }
    }
    .env.example {
        # OLAMA API Key
        OLAMA_API_KEY=your_key_here
    }
    README.md {
        # olama-ast-cli
        
        A high-performance CLI tool for AST-based code editing using a local OLAMA agent.
        
        ## Features
        - Beautiful CLI interface
        - AST-based code manipulation (using swc)
        - Integration with OLAMA agent
        - Key management via .env
        
        ## Usage
        1. Copy .env.example to .env and set your OLAMA_API_KEY
        2. Run `npm install`
        3. Run `node gen.js` to generate files
        4. Use `node cli.js edit <file>` to edit code
    }
}

foreach {filename content} $files {
    set f [open $filename w]
    puts $f $content
    close $f
}

puts "Project files generated!"
