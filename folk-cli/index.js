#!/usr/bin/env node

const { spawn } = require('child_process');
const path = require('path');

const tclScriptPath = path.join(__dirname, 'folk.tcl');
const args = process.argv.slice(2);

const child = spawn('tclsh', [tclScriptPath, ...args], { stdio: 'inherit' });

child.on('error', (err) => {
  console.error('Failed to start subprocess.', err);
});

child.on('exit', (code, signal) => {
  if (code !== null) {
    process.exitCode = code;
  } else if (signal !== null) {
    console.error(`Subprocess killed with signal ${signal}`);
    process.exit(1);
  }
});
