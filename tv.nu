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
            let to_insert = (tv $action --no-preview)
            commandline edit --insert $to_insert
          }"
        }
      ]
    },
  ]
}
