import Foundation

/// Command line options for `paperwindow`.
struct Options {
    var listOnly = false
    var windowID: CGWindowID?
    var appName: String?
    var hideOriginal = true
    var live = false
    var liveFPS: Double = 12
    var gravity = false
    var gridSpacing: Double = 22      // points between mesh vertices
    var stiffness: Double = 1.0       // multiplier on structural springs
    var springBack: Double = 1.0      // multiplier on the pull toward rest shape
    var shadow = true

    static let usage = """
    paperwindow — turn any macOS window into a sheet of paper you can pull, stretch and jiggle.

    USAGE
      paperwindow [options]

    OPTIONS
      -l, --list              List capturable windows and exit.
      -w, --window <id>       Skip the picker, use this window id (see --list).
      -a, --app <name>        Skip the picker, use the frontmost window of this app.
          --keep-original     Do not move the real window out of the way.
          --live [fps]        Keep re-capturing the window so the paper stays live.
          --gravity           Start with gravity on (the sheet sags and flaps).
          --grid <points>     Mesh spacing in points (default 22, smaller = smoother).
          --stiffness <x>     Structural stiffness multiplier (default 1.0).
          --spring-back <x>   How hard it snaps back to shape (default 1.0, 0 = stays deformed).
          --no-shadow         Do not draw the drop shadow under the sheet.
      -h, --help              Show this help.

    CONTROLS
      drag a corner           Pull / stretch the sheet from that corner.
      drag anywhere else      Grab the sheet at that point.
      flick and release       Let go mid-motion to send it wobbling.
      space                   Give the sheet a random impulse (a flap).
      g                       Toggle gravity.
      r                       Snap back to the rest shape immediately.
      esc                     Put the window back to normal and quit.
    """

    static func parse(_ argv: [String]) throws -> Options {
        var o = Options()
        var i = 0
        func next(_ flag: String) throws -> String {
            i += 1
            guard i < argv.count else { throw OptionError("\(flag) needs a value") }
            return argv[i]
        }
        while i < argv.count {
            let arg = argv[i]
            switch arg {
            case "-h", "--help":
                print(usage)
                exit(0)
            case "-l", "--list":
                o.listOnly = true
            case "-w", "--window":
                guard let id = UInt32(try next(arg)) else { throw OptionError("--window needs a numeric window id") }
                o.windowID = CGWindowID(id)
            case "-a", "--app":
                o.appName = try next(arg)
            case "--keep-original":
                o.hideOriginal = false
            case "--live":
                o.live = true
                // optional numeric argument
                if i + 1 < argv.count, let fps = Double(argv[i + 1]) {
                    o.liveFPS = max(1, min(60, fps))
                    i += 1
                }
            case "--gravity":
                o.gravity = true
            case "--grid":
                guard let v = Double(try next(arg)), v >= 6, v <= 120 else { throw OptionError("--grid wants 6...120") }
                o.gridSpacing = v
            case "--stiffness":
                guard let v = Double(try next(arg)), v > 0 else { throw OptionError("--stiffness wants a positive number") }
                o.stiffness = v
            case "--spring-back":
                guard let v = Double(try next(arg)), v >= 0 else { throw OptionError("--spring-back wants a number >= 0") }
                o.springBack = v
            case "--no-shadow":
                o.shadow = false
            default:
                throw OptionError("unknown option: \(arg)")
            }
            i += 1
        }
        return o
    }
}

struct OptionError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
