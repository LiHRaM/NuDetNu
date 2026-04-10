# dotest.nu – Pretty wrapper for dotnet test
#
# Usage:
#   source dotest.nu
#
#   dotest                       # run all tests
#   dotest "PartialName"         # filter: FullyQualifiedName~PartialName
#   dotest -v                    # verbose: show passed/skipped in a tree too
#   dotest "PartialName" -v
 
# ── XML helpers ──────────────────────────────────────────────────────────────
 
# Join text from a list of TRX XML content nodes (text nodes have tag == null)
def xml-text []: list -> string {
    where tag == null | each {|n| $n.content} | str join "\n"
}
 
# ── formatting ───────────────────────────────────────────────────────────────
 
# "HH:MM:SS.NNNNNNN" → "18ms" / "1.2s" / "1m 5s"
def fmt-dur []: string -> string {
    let hms_frac = ($in | split row ".")
    let hms = ($hms_frac | get 0 | split row ":")
    let h   = ($hms | get 0 | into int)
    let m   = ($hms | get 1 | into int)
    let s   = ($hms | get 2 | into int)
    let ms  = if ($hms_frac | length) > 1 {
        ($hms_frac | get 1 | str substring 0..2 | into int)
    } else { 0 }
    let total_ms = ($h * 3600000 + $m * 60000 + $s * 1000 + $ms)
 
    if $total_ms == 0 {
        "< 1ms"
    } else if $total_ms < 1000 {
        $"($total_ms)ms"
    } else if $total_ms < 60000 {
        if ($total_ms mod 1000 / 100 | into int) == 0 {
            $"($total_ms / 1000 | into int)s"
        } else {
            $"($total_ms / 1000 | into int).($total_ms mod 1000 / 100 | into int)s"
        }
    } else {
        $"($total_ms / 60000 | into int)m ($total_ms mod 60000 / 1000 | into int)s"
    }
}
 
# Colorize a single stack-frame line:
#   "   at Method() in /path/File.cs:line 42"  →  grey method, cyan path, yellow :line N
def colorize-stack-line []: string -> string {
    let raw = ($in | str trim)
    if not ($raw | str starts-with "at ") { return $"   ($raw)" }
 
    # Try to match the "in <file>:line N" part
    let m = ($raw | parse --regex '^at (.+?) in (.+?):\s*line (\d+)\s*$')
    if ($m | is-empty) { return $"   (ansi dark_gray)($raw)(ansi reset)" }
 
    let r = ($m | first)
    $"   (ansi dark_gray)at ($r.capture0)(ansi reset) in (ansi cyan)($r.capture1)(ansi reset)(ansi yellow):line ($r.capture2)(ansi reset)"
}
 
# ── TRX parsing ──────────────────────────────────────────────────────────────
 
# Parse every *.trx in $dir into a flat table of test records
def parse-trx-dir [dir: string]: nothing -> table {
    let files = (glob $"($dir)/*.trx")
    if ($files | is-empty) { return [] }
 
    $files | each {|f|
        let doc = (open $f | from xml)
 
        let results_el = ($doc.content | where tag == "Results")
        if ($results_el | is-empty) { return [] }
        let results = ($results_el | first).content | where tag == "UnitTestResult"
 
        let defs_el = ($doc.content | where tag == "TestDefinitions")
        let defs = if ($defs_el | is-empty) { [] } else {
            ($defs_el | first).content | where tag == "UnitTest"
        }
 
        $results | each {|r|
            let attr      = $r.attributes
            let test_id   = $attr.testId
            let test_name = $attr.testName
            let outcome   = $attr.outcome
            let duration  = $attr.duration
 
            # Resolve full class name from TestDefinitions (testId lookup)
            let def_match = ($defs | where {|d| $d.attributes.id == $test_id})
            let methods = if ($def_match | is-empty) { [] } else {
                ($def_match | first).content | where tag == "TestMethod"
            }
            let class_name = if ($methods | is-empty) { "" } else {
                ($methods | first).attributes.className
            }
            let full_name = if ($class_name | is-not-empty) { $"($class_name).($test_name)" } else { $test_name }
 
            # Extract output sections (only populated when something was captured)
            mut error_msg   = ""
            mut stack_trace = ""
            mut std_out     = ""
 
            let out_els = ($r.content | where tag == "Output")
            if ($out_els | is-not-empty) {
                let out = ($out_els | first).content
 
                let so_els = ($out | where tag == "StdOut")
                if ($so_els | is-not-empty) { $std_out = (($so_els | first).content | xml-text) }
 
                let ei_els = ($out | where tag == "ErrorInfo")
                if ($ei_els | is-not-empty) {
                    let ei = ($ei_els | first).content
                    let msg_els = ($ei | where tag == "Message")
                    if ($msg_els | is-not-empty) { $error_msg = (($msg_els | first).content | xml-text) }
                    let st_els = ($ei | where tag == "StackTrace")
                    if ($st_els | is-not-empty) { $stack_trace = (($st_els | first).content | xml-text) }
                }
            }
 
            {
                class_name:  $class_name
                name:        $test_name
                full_name:   $full_name
                outcome:     (match $outcome {
                    "Passed" => "Passed"
                    "Failed" => "Failed"
                    _ => "Skipped"
                })
                duration:    $duration
                error_msg:   $error_msg
                stack_trace: $stack_trace
                std_out:     $std_out
            }
        }
    } | flatten
}
 
# ── rendering ────────────────────────────────────────────────────────────────
 
# Print a failed test inside a unicode box with title embedded in the top border
def render-failure [t: record] {
    let width = (try { [(term size).columns 100] | math min } catch { 80 })
    let inner = ($width - 2)   # chars between ┏ and ┓
 
    let dur     = ($t.duration | fmt-dur)
    let badge   = $" failed after ($dur) "   # plain text for width calc
    let title   = $" ($t.full_name) "         # plain text for width calc
 
    # Truncate title if needed so border always fits
    let max_title_w = ($inner - ($badge | str length) - 3)   # 3 = "━" + two spaces
    let title_str = if ($title | str length) > $max_title_w {
        $" ($t.full_name | str substring 0..($max_title_w - 4))… "
    } else { $title }
 
    let right_w = ([($inner - ($title_str | str length) - ($badge | str length) - 1) 0] | math max)
    let right_hr = ("━" | fill -c '━' -w $right_w)
    let hr       = ("━" | fill -c '━' -w $inner)
    let div      = ("─" | fill -c '─' -w $inner)
 
    # Top border with embedded title and badge
    print $"(ansi red)┏━(ansi reset)(ansi red_bold)($title_str)(ansi reset)(ansi red_bold)($badge)(ansi red)($right_hr)┓(ansi reset)"
 
    if ($t.error_msg | str trim | is-not-empty) {
        print $"(ansi red)┃(ansi reset)"
        print $"(ansi red)┃(ansi reset) (ansi yellow_bold)Error(ansi reset)"
        for line in ($t.error_msg | str trim | lines) {
            print $"(ansi red)┃(ansi reset)   ($line)"
        }
    }
 
    if ($t.std_out | str trim | is-not-empty) {
        print $"(ansi red)┠($div)┨(ansi reset)"
        print $"(ansi red)┃(ansi reset) (ansi cyan_bold)Output(ansi reset)"
        for line in ($t.std_out | str trim | lines) {
            print $"(ansi red)┃(ansi reset)   (ansi dark_gray)($line)(ansi reset)"
        }
    }
 
    if ($t.stack_trace | str trim | is-not-empty) {
        print $"(ansi red)┠($div)┨(ansi reset)"
        print $"(ansi red)┃(ansi reset) (ansi magenta_bold)Stack Trace(ansi reset)"
        for line in ($t.stack_trace | str trim | lines) {
            print $"(ansi red)┃(ansi reset)($line | colorize-stack-line)"
        }
    }
 
    print $"(ansi red)┗($hr)┛(ansi reset)"
}
 
# Print a tree of test results grouped by class name
def render-tree [tests: list] {
    $tests
    | group-by class_name
    | transpose key items
    | each {|g|
        let cls = if ($g.key | is-empty) { "(unknown)" } else { $g.key }
        print $"  (ansi cyan)($cls)(ansi reset)"
        for t in $g.items {
            let icon = match $t.outcome {
                "Passed"  => $"(ansi green)✓(ansi reset)"
                "Failed"  => $"(ansi red)✗(ansi reset)"
                "Skipped" => $"(ansi yellow)○(ansi reset)"
                _         => "·"
            }
            print $"    ($icon) ($t.name) (ansi dark_gray)[($t.duration | fmt-dur)](ansi reset)"
            if ($t.std_out | str trim | is-not-empty) {
                for line in ($t.std_out | str trim | lines) {
                    print $"         (ansi dark_gray)│ ($line)(ansi reset)"
                }
            }
        }
    }
    | ignore
}
 
# ── main command ─────────────────────────────────────────────────────────────
 
# Run dotnet test with a live progress line, pretty failure boxes, and a summary.
#
# Examples:
#   dotest
#   dotest "Portland.Worker.Test"
#   dotest "CreateBacktest111" -v
export def dotest [
    filter?: string   # Partial name matched via FullyQualifiedName~<filter>
    --verbose (-v)    # Show passed/skipped tests in a tree after failure boxes
] {
    let trx_dir = (mktemp -d)
 
    mut args = [
        "test" "--nologo"
        "--results-directory" $trx_dir
        "--logger" "trx;LogFilePrefix=res"
    ]
    if $filter != null {
        $args = ($args | append ["--filter" $"FullyQualifiedName~($filter)"])
    }
 
    let t0 = (date now)
 
    # ── live progress ────────────────────────────────────────────────────────
    # Stream every stdout line from dotnet; count Passed/Failed as they appear
    # (NUnit adapter emits these at default verbosity).  On every line we
    # overwrite the terminal line with updated counts + elapsed time.
    try {
        dotnet ...$args | lines | reduce --fold { n: 0, f: 0 } {|line, acc|
            let trimmed  = ($line | str trim)
            let is_pass  = ($trimmed | str starts-with "Passed ")
            let is_fail  = ($trimmed | str starts-with "Failed ")
            let n = $acc.n + (if $is_pass or $is_fail { 1 } else { 0 })
            let f = $acc.f + (if $is_fail { 1 } else { 0 })
 
            let secs      = (((date now) - $t0 | into int) / 1_000_000_000 | into int)
            let count_str = if $n > 0 { $"($n) tests" } else { "building…" }
            let fail_str  = if $f > 0 { $"  (ansi red)($f) failed(ansi reset)" } else { "" }
 
            print -n $"(ansi -e '2K')(char cr)(ansi cyan)⏳(ansi reset) ($count_str)(ansi dark_gray) ($secs)s(ansi reset)($fail_str)"
            { n: $n, f: $f }
        } | ignore
    } catch { }
 
    print -n $"(ansi -e '2K')(char cr)"   # erase the progress line
 
    # ── parse results ────────────────────────────────────────────────────────
    let elapsed_ms = (((date now) - $t0 | into int) / 1_000_000 | into int)
    let tests      = (parse-trx-dir $trx_dir)
    rm -rf $trx_dir
 
    if ($tests | is-empty) {
        print $"(ansi yellow)No test results found.(ansi reset) Build may have failed – run (ansi cyan)dotnet test(ansi reset) for details."
        return
    }
 
    let passed  = ($tests | where outcome == "Passed")
    let failed  = ($tests | where outcome == "Failed")
    let skipped = ($tests | where outcome == "Skipped")
 
    # ── failure boxes ────────────────────────────────────────────────────────
    for t in $failed { print ""; render-failure $t }
 
    # ── verbose tree ─────────────────────────────────────────────────────────
    if $verbose {
        if ($passed  | is-not-empty) { print $"\n(ansi green_bold)Passed(ansi reset)";  render-tree $passed  }
        if ($skipped | is-not-empty) { print $"\n(ansi yellow_bold)Skipped(ansi reset)"; render-tree $skipped }
        if ($failed  | is-not-empty) { print $"\n(ansi red_bold)Failed(ansi reset)";    render-tree $failed  }
        print ""
    }
 
    # ── summary line ─────────────────────────────────────────────────────────
    let elapsed_str = if $elapsed_ms < 1000 {
        $"($elapsed_ms)ms"
    } else if $elapsed_ms < 60000 {
        $"($elapsed_ms / 1000 | into int).($elapsed_ms mod 1000 / 100 | into int)s"
    } else {
        $"($elapsed_ms / 60000 | into int)m ($elapsed_ms mod 60000 / 1000 | into int)s"
    }
 
    mut parts = []
    if ($passed  | is-not-empty) { $parts = ($parts | append $"(ansi green)($passed  | length) passed(ansi reset)") }
    if ($failed  | is-not-empty) { $parts = ($parts | append $"(ansi red)($failed  | length) failed(ansi reset)") }
    if ($skipped | is-not-empty) { $parts = ($parts | append $"(ansi yellow)($skipped | length) skipped(ansi reset)") }
 
    let icon = if ($failed | is-not-empty) { $"(ansi red_bold)FAIL(ansi reset)" } else { $"(ansi green_bold)PASS(ansi reset)" }
    print $"\n($icon)  ($parts | str join ', ')  (ansi dark_gray)($elapsed_str)(ansi reset)"
}
