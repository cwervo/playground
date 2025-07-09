# Folk CLI

This is a command-line interface for FolkComputer.

## Usage

You can run Folk commands using `npx`:

```bash
npx folk <command>
```

Replace `<command>` with the desired FolkComputer command (e.g., `start`, `stop`, `restart`).

## Development

This CLI wraps the `folk.tcl` script. To make changes:

1.  Modify `folk.tcl` with the desired Tcl script logic.
2.  The `index.js` file is the entry point for the `folk` command and executes `folk.tcl`.
3.  Update `package.json` if you change file names or add dependencies.

## Publishing

To publish this package to npm:

1.  Ensure you have an npm account and are logged in (`npm login`).
2.  Increment the version number in `package.json`.
3.  Run `npm publish`.
