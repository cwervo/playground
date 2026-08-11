#!/usr/bin/env python3
import os
import re
import ast
import argparse
from pathlib import Path

# Common directory ignore patterns
DEFAULT_IGNORE_DIRS = {
    '.git', 'node_modules', '__pycache__', 'venv', '.venv', 'env', '.env',
    'dist', 'build', 'target', 'bin', 'obj', '.pytest_cache', '.eggs',
    '*.egg-info', '.mypy_cache', '.DS_Store', '.idea', '.vscode'
}

# Common file ignore patterns (binaries, assets, etc.)
DEFAULT_IGNORE_EXTS = {
    '.png', '.jpg', '.jpeg', '.gif', '.ico', '.svg', '.mp4', '.mp3', '.wav',
    '.pdf', '.zip', '.tar', '.gz', '.rar', '.7z', '.exe', '.dll', '.so', '.dylib',
    '.pyc', '.pyo', '.db', '.sqlite', '.sqlite3', '.woff', '.woff2', '.eot', '.ttf'
}

class FileNode:
    def __init__(self, rel_path, abs_path):
        self.rel_path = rel_path.replace('\\', '/')
        self.abs_path = abs_path
        self.extension = os.path.splitext(rel_path)[1].lower()
        self.imports = []  # list of tuples or strings depending on language
        self.resolved_deps = set()  # set of relative paths of other nodes
        self.node_type = "default"  # entry, config, util, default
        self._detect_node_type()

    def _detect_node_type(self):
        basename = os.path.basename(self.rel_path).lower()
        # Entry points
        if basename in {
            'main.py', 'app.py', 'server.py', 'run.py', 'manage.py',
            'index.js', 'index.ts', 'main.js', 'main.ts', 'app.js', 'app.ts', 'server.js', 'server.ts',
            'main.go', 'main.rs', 'lib.rs'
        }:
            self.node_type = "entry"
        # Configs
        elif any(k in basename for k in ['config', 'settings', 'env', 'setup', 'manifest', 'toml', 'yaml', 'yml', 'json']):
            self.node_type = "config"
        # Utils
        elif any(k in basename for k in ['util', 'helper', 'common', 'tool', 'shared', 'lib']):
            self.node_type = "util"

class DirectoryNode:
    def __init__(self, name, full_rel_path):
        self.name = name
        self.full_rel_path = full_rel_path.replace('\\', '/')
        self.subdirs = {}  # name -> DirectoryNode
        self.files = []  # list of FileNode

def parse_go_mod(root_dir):
    """Find and parse go.mod file to get the Go module name."""
    go_mod_path = os.path.join(root_dir, 'go.mod')
    if os.path.exists(go_mod_path):
        try:
            with open(go_mod_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                match = re.search(r'^\s*module\s+(\S+)', content, re.MULTILINE)
                if match:
                    return match.group(1)
        except Exception:
            pass
    return None

# ==========================================
# PARSERS FOR DIFFERENT LANGUAGES
# ==========================================

def extract_python_imports(content):
    imports = []
    try:
        tree = ast.parse(content)
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for name in node.names:
                    imports.append((name.name, 0))
            elif isinstance(node, ast.ImportFrom):
                if node.module:
                    imports.append((node.module, node.level))
                else:
                    imports.append(("", node.level))
    except Exception:
        # Fallback to regex if ast parsing fails
        for match in re.finditer(r'^\s*import\s+([\w\.,\s]+)', content, re.MULTILINE):
            for part in match.group(1).split(','):
                imports.append((part.strip(), 0))
        for match in re.finditer(r'^\s*from\s+([\w\.]+)\s+import', content, re.MULTILINE):
            imports.append((match.group(1).strip(), 0))
    return imports

def extract_jsts_imports(content):
    imports = []
    pattern1 = r'(?:import|export)\s+.*?from\s+[\'"]([^\'\"]+)[\'"]'
    pattern2 = r'import\s+[\'"]([^\'\"]+)[\'"]'
    pattern3 = r'require\s*\(\s*[\'"]([^\'\"]+)[\'"]\s*\)'
    pattern4 = r'import\s*\(\s*[\'"]([^\'\"]+)[\'"]\s*\)'

    for p in [pattern1, pattern2, pattern3, pattern4]:
        for match in re.finditer(p, content):
            imports.append(match.group(1))
    return list(set(imports))

def extract_go_imports(content):
    imports = []
    block_pattern = r'import\s*\((.*?)\)'
    for block_match in re.finditer(block_pattern, content, re.DOTALL):
        block_content = block_match.group(1)
        for line_match in re.finditer(r'[\'"]([^\'\"]+)[\'"]', block_content):
            imports.append(line_match.group(1))
    
    single_pattern = r'^\s*import\s+[\'"]([^\'\"]+)[\'"]'
    for match in re.finditer(single_pattern, content, re.MULTILINE):
        imports.append(match.group(1))
    return list(set(imports))

def extract_rust_imports(content):
    imports = []
    # mod name;
    for match in re.finditer(r'^\s*(?:pub\s+)?mod\s+(\w+)\s*;', content, re.MULTILINE):
        imports.append(("mod", match.group(1)))
    # use path::to::mod;
    for match in re.finditer(r'^\s*(?:pub\s+)?use\s+([^;]+);', content, re.MULTILINE):
        imports.append(("use", match.group(1).strip()))
    return imports

def extract_generic_imports(content):
    imports = []
    for match in re.finditer(r'[\'"](\.[./\w_-]+)[\'"]', content):
        imports.append(match.group(1))
    return list(set(imports))

# ==========================================
# IMPORT RESOLVERS
# ==========================================

def resolve_python_import(import_name, level, file_rel_path, all_files):
    file_dir = os.path.dirname(file_rel_path)
    parts = file_dir.split('/') if file_dir else []
    
    if level > 0:
        if level <= len(parts) + 1:
            base_parts = parts[:len(parts) - level + 1]
            base_dir = '/'.join(base_parts)
        else:
            base_dir = ""
    else:
        base_dir = file_dir

    search_dirs = [base_dir]
    if base_dir != "":
        search_dirs.append("")  # Check project root

    import_parts = import_name.split('.') if import_name else []
    
    for s_dir in search_dirs:
        candidate_parts = []
        if s_dir:
            candidate_parts.extend(s_dir.split('/'))
        candidate_parts.extend(import_parts)
        
        cand_path_file = '/'.join(candidate_parts) + '.py'
        cand_path_init = '/'.join(candidate_parts) + '/__init__.py'
        
        if cand_path_file in all_files:
            return [cand_path_file]
        if cand_path_init in all_files:
            return [cand_path_init]
    return []

def resolve_jsts_import(import_path, file_rel_path, all_files):
    file_dir = os.path.dirname(file_rel_path)
    
    if import_path.startswith('@/') or import_path.startswith('~/'):
        clean_path = import_path[2:]
        candidates = [clean_path, 'src/' + clean_path]
    elif import_path.startswith('./') or import_path.startswith('../'):
        cand = os.path.normpath(os.path.join(file_dir, import_path))
        candidates = [cand]
    else:
        candidates = [import_path, 'src/' + import_path]

    extensions = ['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '/index.ts', '/index.tsx', '/index.js', '/index.jsx']
    for cand in candidates:
        cand = cand.replace('\\', '/')
        if cand.startswith('./'):
            cand = cand[2:]
        
        if cand in all_files:
            return [cand]
        for ext in extensions:
            if (cand + ext) in all_files:
                return [cand + ext]
    return []

def resolve_go_import(import_path, all_files, go_module_name=None):
    if go_module_name and import_path.startswith(go_module_name + '/'):
        rel_dir = import_path[len(go_module_name) + 1:]
    else:
        parts = import_path.split('/')
        rel_dir = None
        for i in range(len(parts)):
            candidate = '/'.join(parts[i:])
            if any(f.startswith(candidate + '/') for f in all_files):
                rel_dir = candidate
                break
                
    if not rel_dir:
        return []
        
    # Map to all files in that directory
    matching_files = [f for f in all_files if f.startswith(rel_dir + '/')]
    return matching_files

def resolve_rust_import(import_type, import_val, file_rel_path, all_files):
    file_dir = os.path.dirname(file_rel_path)
    
    candidates = []
    if import_type == "mod":
        candidates.append(os.path.join(file_dir, f"{import_val}.rs"))
        candidates.append(os.path.join(file_dir, import_val, "mod.rs"))
    elif import_type == "use":
        val = import_val.split('{')[0].strip()
        parts = [p.strip() for p in val.split('::') if p.strip()]
        if not parts:
            return []
            
        first = parts[0]
        if first == "crate":
            path_parts = file_dir.split('/')
            src_idx = -1
            for idx, part in enumerate(path_parts):
                if part == "src":
                    src_idx = idx
                    break
            if src_idx != -1:
                base_dir = '/'.join(path_parts[:src_idx + 1])
            else:
                base_dir = "src" if "src" in all_files else ""
            
            sub_path = '/'.join(parts[1:])
            candidates.append(os.path.join(base_dir, f"{sub_path}.rs"))
            candidates.append(os.path.join(base_dir, sub_path, "mod.rs"))
        elif first == "super":
            parent_dir = os.path.dirname(file_dir)
            sub_path = '/'.join(parts[1:])
            candidates.append(os.path.join(parent_dir, f"{sub_path}.rs"))
            candidates.append(os.path.join(parent_dir, sub_path, "mod.rs"))
        elif first == "self":
            sub_path = '/'.join(parts[1:])
            candidates.append(os.path.join(file_dir, f"{sub_path}.rs"))
            candidates.append(os.path.join(file_dir, sub_path, "mod.rs"))
        else:
            sub_path = '/'.join(parts)
            candidates.append(os.path.join("src", f"{sub_path}.rs"))
            candidates.append(os.path.join("src", sub_path, "mod.rs"))
            candidates.append(os.path.join(file_dir, f"{sub_path}.rs"))
            candidates.append(os.path.join(file_dir, sub_path, "mod.rs"))
            
    resolved = []
    for cand in candidates:
        cand = os.path.normpath(cand).replace('\\', '/')
        if cand in all_files:
            resolved.append(cand)
    return resolved

# ==========================================
# MAIN ANALYZER CLASS
# ==========================================

class CodebaseAnalyzer:
    def __init__(self, root_dir, max_depth=5, excludes=None):
        self.root_dir = os.path.abspath(root_dir)
        self.max_depth = max_depth
        self.excludes = set(excludes) if excludes else set()
        self.files = {}  # rel_path -> FileNode
        self.dir_tree = DirectoryNode("root", "")
        self.go_module_name = parse_go_mod(self.root_dir)

    def should_ignore(self, path):
        parts = Path(path).parts
        # Check if any path segment matches ignore patterns
        for part in parts:
            if part in DEFAULT_IGNORE_DIRS or part in self.excludes:
                return True
            # Glob check
            for pattern in self.excludes:
                if re.match(pattern.replace('*', '.*'), part):
                    return True
        return False

    def scan(self):
        for root, dirs, filenames in os.walk(self.root_dir):
            # Compute relative path of the folder
            rel_folder = os.path.relpath(root, self.root_dir)
            if rel_folder == '.':
                rel_folder = ""

            # Apply ignore filters to directories
            if self.should_ignore(rel_folder) if rel_folder else False:
                dirs[:] = []  # don't walk down
                continue

            # Limit depth
            depth = len(rel_folder.split('/')) if rel_folder else 0
            if depth >= self.max_depth:
                dirs[:] = []
                continue

            for filename in filenames:
                ext = os.path.splitext(filename)[1].lower()
                if ext in DEFAULT_IGNORE_EXTS:
                    continue

                abs_path = os.path.join(root, filename)
                rel_path = os.path.relpath(abs_path, self.root_dir).replace('\\', '/')

                if self.should_ignore(rel_path):
                    continue

                node = FileNode(rel_path, abs_path)
                self.files[rel_path] = node
                self._add_to_dir_tree(node)

    def _add_to_dir_tree(self, file_node):
        parts = file_node.rel_path.split('/')
        file_name = parts[-1]
        dir_parts = parts[:-1]

        current = self.dir_tree
        accumulated_path = []
        for d in dir_parts:
            accumulated_path.append(d)
            full_path = '/'.join(accumulated_path)
            if d not in current.subdirs:
                current.subdirs[d] = DirectoryNode(d, full_path)
            current = current.subdirs[d]
        current.files.append(file_node)

    def analyze_dependencies(self):
        for rel_path, node in self.files.items():
            try:
                with open(node.abs_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
            except Exception:
                continue

            # Run parser based on extension
            if node.extension == '.py':
                node.imports = extract_python_imports(content)
            elif node.extension in ['.js', '.jsx', '.ts', '.tsx', '.mjs', '.cjs']:
                node.imports = extract_jsts_imports(content)
            elif node.extension == '.go':
                node.imports = extract_go_imports(content)
            elif node.extension == '.rs':
                node.imports = extract_rust_imports(content)
            else:
                node.imports = extract_generic_imports(content)

        # Resolve imports
        for rel_path, node in self.files.items():
            for imp in node.imports:
                resolved_paths = []
                if node.extension == '.py':
                    resolved_paths = resolve_python_import(imp[0], imp[1], rel_path, self.files)
                elif node.extension in ['.js', '.jsx', '.ts', '.tsx', '.mjs', '.cjs']:
                    resolved_paths = resolve_jsts_import(imp, rel_path, self.files)
                elif node.extension == '.go':
                    resolved_paths = resolve_go_import(imp, self.files, self.go_module_name)
                elif node.extension == '.rs':
                    resolved_paths = resolve_rust_import(imp[0], imp[1], rel_path, self.files)
                else:
                    resolved_paths = resolve_generic_import(imp, rel_path, self.files)

                for r_path in resolved_paths:
                    if r_path != rel_path:  # avoid self-dependency
                        node.resolved_deps.add(r_path)

    def generate_mermaid(self, direction="TB"):
        lines = [
            "flowchart " + direction,
            "  %% Node Styles & Classes"
        ]
        
        # Styles for nodes
        styles = [
            "  classDef default fill:#1f2937,stroke:#4b5563,stroke-width:1px,color:#f3f4f6;",
            "  classDef entry fill:#064e3b,stroke:#059669,stroke-width:2px,color:#34d399;",
            "  classDef util fill:#1e3a8a,stroke:#3b82f6,stroke-width:1px,color:#93c5fd;",
            "  classDef config fill:#78350f,stroke:#d97706,stroke-width:1px,color:#fcd34d;"
        ]
        lines.extend(styles)
        lines.append("")

        def clean_id(rel_path):
            return "node_" + rel_path.replace('/', '_').replace('.', '_').replace('-', '_')

        def build_subgraphs(dir_node, indent="  "):
            sub_lines = []
            is_root = dir_node.full_rel_path == ""
            if not is_root:
                sub_id = "dir_" + dir_node.full_rel_path.replace('/', '_').replace('.', '_').replace('-', '_')
                sub_lines.append(f'{indent}subgraph {sub_id} [" {dir_node.name} "]')
                indent += "  "

            # Files
            for f in dir_node.files:
                f_id = clean_id(f.rel_path)
                display_name = os.path.basename(f.rel_path)
                sub_lines.append(f'{indent}{f_id}["{display_name}"]')
                # Assign class based on node type
                if f.node_type != "default":
                    sub_lines.append(f'{indent}class {f_id} {f.node_type};')

            # Subdirs
            for subdir in dir_node.subdirs.values():
                sub_lines.extend(build_subgraphs(subdir, indent))

            if not is_root:
                indent = indent[:-2]
                sub_lines.append(f'{indent}end')
            return sub_lines

        # Output subgraphs
        lines.extend(build_subgraphs(self.dir_tree))
        lines.append("")
        lines.append("  %% Dependencies")

        # Output connections
        edges = []
        for rel_path, node in self.files.items():
            from_id = clean_id(rel_path)
            for dep in node.resolved_deps:
                to_id = clean_id(dep)
                edges.append(f"  {from_id} --> {to_id}")
        
        lines.extend(sorted(edges))
        return '\n'.join(lines)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Codebase Architecture to Mermaid Diagram Generator")
    parser.add_argument("path", help="Directory path of the project to analyze")
    parser.add_argument("-o", "--output", default="architecture.md", help="Output path for Mermaid markdown file")
    parser.add_argument("-d", "--depth", type=int, default=5, help="Max directory depth (default: 5)")
    parser.add_argument("-e", "--exclude", action="append", default=[], help="Directories/files to exclude")
    parser.add_argument("--direction", default="TB", choices=["TB", "BT", "LR", "RL"], help="Flowchart direction (default: TB)")
    args = parser.parse_args()

    if not os.path.isdir(args.path):
        print(f"Error: {args.path} is not a valid directory.")
        exit(1)

    print(f"Scanning {args.path}...")
    analyzer = CodebaseAnalyzer(args.path, max_depth=args.depth, excludes=args.exclude)
    analyzer.scan()
    print(f"Found {len(analyzer.files)} files. Analyzing dependencies...")
    analyzer.analyze_dependencies()
    print("Generating Mermaid flowchart...")
    mermaid_markup = analyzer.generate_mermaid(direction=args.direction)

    output_content = f"# Architecture Diagram\n\n```mermaid\n{mermaid_markup}\n```\n"

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(output_content)

    print(f"Successfully generated architecture diagram at: {args.output}")
