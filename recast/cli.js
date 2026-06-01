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
    
