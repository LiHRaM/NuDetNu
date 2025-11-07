export  def --wrapped tv-from-list [...rest]: list -> string {

  print ...$rest
  let result = $in | str join "\n" | tv ...$rest 

  if ( $result | is-empty ) {
      error make {msg: "No matches found" } -u
  }
  return $result
}

export-env {
  $env.config.keybindings ++= [
    {
      name: fuzzy_finder
      modifier: control
      keycode: char_p
      mode: [emacs, vi_normal, vi_insert]
      event: [
        {
          send: ExecuteHostCommand
          cmd: " do {
            let action = (tv list-channels | lines | filter { $in | str starts-with "\t"} | str join "\n" | tv)
            if ($action | is-empty) {
              return
            }
            let to_insert = (tv $action --no-preview)
            if ($to_insert | is-empty) {
              return
            }

            commandline edit --insert $to_insert
          }"
        }
      ]
    },
  ]
}
