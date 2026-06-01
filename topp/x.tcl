# TCL script to create Go source files and compile the module

puts "--- Starting Go TUI Builder Script ---"

# --- Create main.go ---
puts "Creating main.go..."
set go_file [open "main.go" w]

# The content of main.go is placed within curly braces to handle it as a single literal string
puts $go_file {package main

import (
	"fmt"
	"log"
	"math/rand"
	"os"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Sample data from the user's top output
const topOutput = `
Processes: 665 total, 77 running, 1 stuck, 587 sleeping, 4414 threads                                  14:10:30
Load Avg: 126.18, 129.62, 84.46  CPU usage: 55.74% user, 35.55% sys, 8.69% idle
SharedLibs: 428M resident, 84M data, 53M linkedit. MemRegions: 0 total, 0B resident, 0B private, 1995M shared.
PhysMem: 15G used (4004M wired, 6946M compressor), 266M unused.
VM: 338T vsize, 5709M framework vsize, 106326916(1399) swapins, 110692298(432) swapouts.
Networks: packets: 55083730/61G in, 18838694/4415M out. Disks: 87216268/2906G read, 42424094/1971G written.

PID    COMMAND      %CPU      TIME     #TH    #WQ  #PORT MEM    PURG   CMPRS  PGRP  PPID  STATE
38840  ffmpeg       146.2     21:58.07 30/8   0    53    604M+  0B     163M+  35743 35743 running
22002  Code Helper  91.2      02:46.11 19/1   1    92    171M+  0B     101M+  21899 21899 running
0      kernel_task  88.0      11:52:25 576/10 0    0     63M    0B     0B     0     0     running
63839  iTerm2       72.0      10:07.65 12/1   9    406   283M-  48M    73M-   63839 1     running
38126  QEMULauncher 67.0      22:39.41 22/2   1    50    1233M  0B     1140M- 38126 38124 running
379    WindowServer 37.0      07:37:18 27/1   10   5315+ 1121M- 39M+   275M+  379   1     running
16670  contactsd    24.5      21:52.73 11/1   10/1 891+  55M+   0B-    50M+   16670 1     running
313    fseventsd    17.5      09:04.74 17     1    250   6001K+ 0B     2336K- 313   1     sleeping
39534  top          16.6      00:34.31 1/1    0    63    11M+   0B     3824K- 39534 39416 running
39573  AddressBookM 12.4      00:07.79 3      2    174   63M+   0B     58M+   39573 1     sleeping
26286  Messages     10.4      05:46.81 5      2    675   78M    0B     64M    26286 1     sleeping
830    CleanMyMac_5 9.8       15:03.69 9      2    249   72M+   0B     56M-   830   1     sleeping
83210  Google Chrom 9.3       06:09.10 23/1   1    325   433M+  0B     241M-  1198  1198  running
763    Bartender 5  9.1       06:55.69 12     9    357+  40M-   0B     20M-   763   1     sleeping
36309  Private Inte 8.5       03:45.51 15     8    273   139M-  0B     122M-  36309 1     sleeping
38376  Kap Helper ( 8.0       01:08.19 22/1   1    204-  230M+  0B     177M-  35743 35743 running
394    coreaudiod   7.2       57:08.35 9      2    3111  54M    0B     41M+   394   1     sleeping
35769  Kap Helper ( 6.2       01:02.46 11/1   2    237   387M+  0B     36M-   35743 35743 running
38972  aperture     6.1       00:30.69 14/2   6/2  207+  202M-  0B     13M+   35743 35743 running
1198   Google Chrom 6.1       02:43:51 54/2   7    2248+ 1312M+ 0B     1145M- 1198  1     running
`

type process struct {
	pid     string
	command string
	cpu     string
	mem     string
	ppid    string
}

type model struct {
	processes    []process
	header       string
	viewport     viewport.Model
	viewIndex    int
	views        []string
	width        int
	height       int
	keymap       KeyMap
	processTree  map[string][]process
}

type KeyMap struct {
	NextView key.Binding
	PrevView key.Binding
	Quit     key.Binding
}

var DefaultKeyMap = KeyMap{
	NextView: key.NewBinding(
		key.WithKeys(">", "right", "l"),
		key.WithHelp(">", "next view"),
	),
	PrevView: key.NewBinding(
		key.WithKeys("<", "left", "h"),
		key.WithHelp("<", "prev view"),
	),
	Quit: key.NewBinding(
		key.WithKeys("q", "ctrl+c"),
		key.WithHelp("q", "quit"),
	),
}

func parseTopOutput(output string) (string, []process) {
	lines := strings.Split(output, "\n")
	var headerLines []string
	var processLines []string
	inHeader := true

	for _, line := range lines {
		if strings.TrimSpace(line) == "" {
			continue
		}
		if inHeader && strings.HasPrefix(strings.TrimSpace(line), "PID") {
			inHeader = false
		}
		if inHeader {
			headerLines = append(headerLines, line)
		} else {
			if !strings.HasPrefix(strings.TrimSpace(line), "PID") {
				processLines = append(processLines, line)
			}
		}
	}

	header := strings.Join(headerLines, "\n")
	var processes []process

	for _, line := range processLines {
		fields := strings.Fields(line)
		if len(fields) >= 12 {
			proc := process{
				pid:     fields[0],
				command: fields[1],
				cpu:     fields[2],
				mem:     fields[7],
				ppid:    fields[11],
			}
			processes = append(processes, proc)
		}
	}

	return header, processes
}

func buildProcessTree(processes []process) map[string][]process {
	tree := make(map[string][]process)
	for _, p := range processes {
		tree[p.ppid] = append(tree[p.ppid], p)
	}
	return tree
}

func initialModel() model {
	header, processes := parseTopOutput(topOutput)
	processTree := buildProcessTree(processes)

	return model{
		processes:    processes,
		header:       header,
		views:        []string{"CPU", "Memory", "Energy", "Disk", "Network"},
		viewIndex:    0,
		keymap:       DefaultKeyMap,
		processTree:  processTree,
	}
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var (
		cmd  tea.Cmd
		cmds []tea.Cmd
	)

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		headerHeight := lipgloss.Height(m.headerView())
		m.viewport = viewport.New(msg.Width, msg.Height-headerHeight)
		m.viewport.SetContent(m.renderProcessView())
	
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, m.keymap.Quit):
			return m, tea.Quit
		case key.Matches(msg, m.keymap.NextView):
			m.viewIndex = (m.viewIndex + 1) % len(m.views)
			m.viewport.SetContent(m.renderProcessView())
		case key.Matches(msg, m.keymap.PrevView):
			m.viewIndex = (m.viewIndex - 1 + len(m.views)) % len(m.views)
			m.viewport.SetContent(m.renderProcessView())
		}
	}

	m.viewport, cmd = m.viewport.Update(msg)
	cmds = append(cmds, cmd)

	return m, tea.Batch(cmds...)
}

func (m model) headerView() string {
	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#FAFAFA"))
	headerStyle := lipgloss.NewStyle().Padding(1,2)

	return headerStyle.Render(titleStyle.Render("System Processes") + "\n" + m.header)
}

func (m model) renderProcessView() string {
	var b strings.Builder

	// We'll create a simple grid for now.
	// A more sophisticated layout (like treemap) would be needed for a true "full area" visualization.
	
	style := lipgloss.NewStyle().
		Width(15).
		Height(5).
		Margin(1).
		Padding(1).
		Border(lipgloss.RoundedBorder())

	var content []string

	// Seed for consistent "random" colors per process
	rand.Seed(time.Now().UnixNano())

	// Simple recursive function to draw the tree
	var drawNode func(ppid string, depth int)
	drawNode = func(ppid string, depth int) {
		if children, ok := m.processTree[ppid]; ok {
			for _, p := range children {
				r := rand.Intn(256)
				g := rand.Intn(256)
				b := rand.Intn(256)
				
				metric := ""
				switch m.views[m.viewIndex] {
				case "CPU":
					metric = p.cpu + "%"
				case "Memory":
					metric = p.mem
				default:
					// Placeholder for other metrics
					metric = fmt.Sprintf("%.1f", rand.Float64()*100)
				}


				block := style.
					BorderForeground(lipgloss.Color(fmt.Sprintf("#%02x%02x%02x", r, g, b))).
					Render(fmt.Sprintf("%s\n%s\n%s", p.command, p.pid, metric))
				
				indentedBlock := lipgloss.NewStyle().PaddingLeft(depth * 4).Render(block)
				content = append(content, indentedBlock)
				drawNode(p.pid, depth+1)
			}
		}
	}

	// Start drawing from the root process (PID 0)
	drawNode("0", 0)
	
	// A more grid-like layout
	var gridContent []string
	row := ""
	for i, block := range content {
		row = lipgloss.JoinHorizontal(lipgloss.Top, row, block)
		if (i+1)% (m.width/20) == 0 { // Adjust number of items per row based on width
			gridContent = append(gridContent, row)
			row = ""
		}
	}
	if row != "" {
		gridContent = append(gridContent, row)
	}

	fmt.Fprintln(&b, lipgloss.JoinVertical(lipgloss.Left, gridContent...))
	return b.String()
}


func (m model) footerView() string {
	helpStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	
	views := make([]string, len(m.views))
	for i, v := range m.views {
		if i == m.viewIndex {
			views[i] = lipgloss.NewStyle().Foreground(lipgloss.Color("#B583E7")).Bold(true).Render(v)
		} else {
			views[i] = v
		}
	}


	viewStr := strings.Join(views, " | ")
	help := fmt.Sprintf("%s  %s  %s", m.keymap.PrevView.Help().Key, m.keymap.NextView.Help().Key, m.keymap.Quit.Help().Key)
	
	return helpStyle.Render(lipgloss.JoinHorizontal(lipgloss.Center, viewStr, "  ", help))
}


func (m model) View() string {
	if m.width == 0 {
		return "loading..."
	}

	return fmt.Sprintf("%s\n%s\n%s", m.headerView(), m.viewport.View(), m.footerView())
}

func main() {
	if f, err := tea.LogToFile("debug.log", "debug"); err != nil {
		fmt.Println("couldn't open a file for logging:", err)
		os.Exit(1)
	} else {
		defer func() {
			if err = f.Close(); err != nil {
				log.Fatal(err)
			}
		}()
	}


	p := tea.NewProgram(
		initialModel(),
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
	)

	if _, err := p.Run(); err != nil {
		fmt.Println("Error running program:", err)
		os.Exit(1)
	}
}
}
close $go_file
puts "main.go created successfully."

# --- Create go.mod ---
puts "\nCreating go.mod..."
set mod_file [open "go.mod" w]

puts $mod_file {module github.com/example/top-tui

go 1.18

require (
	github.com/charmbracelet/bubbles v0.18.0
	github.com/charmbracelet/bubbletea v0.26.4
	github.com/charmbracelet/lipgloss v0.11.0
)

require (
	github.com/atotto/clipboard v0.1.4 // indirect
	github.com/aymanbagabas/go-osc52/v2 v2.0.1 // indirect
	github.com/charmbracelet/x/ansi v0.1.1 // indirect
	github.com/charmbracelet/x/input v0.1.0 // indirect
	github.com/charmbracelet/x/term v0.1.0 // indirect
	github.com/charmbracelet/x/windows v0.1.0 // indirect
	github.com/erikgeiser/coninput v0.0.0-20211004153227-1c3628e74d0f // indirect
	github.com/lucasb-eyer/go-colorful v1.2.0 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/mattn/go-localereader v0.0.1 // indirect
	github.com/mattn/go-runewidth v0.0.15 // indirect
	github.com/muesli/ansi v0.0.0-20230316100256-276c6243b2f6 // indirect
	github.com/muesli/cancelreader v0.2.2 // indirect
	github.com/muesli/reflow v0.3.0 // indirect
	github.com/muesli/termenv v0.15.2 // indirect
	github.com/rivo/uniseg v0.4.7 // indirect
	github.com/sahilm/fuzzy v0.1.1-0.20230530133925-c48e322e268f // indirect
	github.com/xo/terminfo v0.0.0-20220910002029-abceb7e1c41e // indirect
	golang.org/x/sync v0.7.0 // indirect
	golang.org/x/sys v0.20.0 // indirect
	golang.org/x/term v0.20.0 // indirect
	golang.org/x/text v0.3.8 // indirect
)
}
close $mod_file
puts "go.mod created successfully."


# --- Compile the Go module ---
puts "\n--- Compiling the Go module ---"
# Use a try-catch block to handle potential errors during compilation
if {[catch {
    puts "Running 'go mod tidy' to fetch dependencies..."
    exec go mod tidy
    puts "Dependencies are up to date."

    puts "\nRunning 'go build' to compile..."
    # The 'exec' command will run the go build command.
    # We specify the output binary name with '-o top-tui'.
    exec go build -o top-tui
} result]} {
    puts "\nAn error occurred during compilation:"
    puts $result
} else {
    puts "\nCompilation successful!"
    puts "Executable 'top-tui' has been created in the current directory."
}

puts "\n--- Script Finished ---"

