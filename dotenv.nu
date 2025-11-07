source tv.nu 

def relative_pwd [file] {
  $file | path expand | path relative-to (pwd | path expand)
}

export def --env dotenv [query?: string] {
  let file = (
      glob **/*.env*
      | each {|file| 
        relative_pwd $file
        }
      | str join "\n"
      | tv --input $"($query)" --select-1 --preview "bat -n --color=always {}" --custom-header "Select .env")
  open $file | from toml | load-env
  print $"Loaded (ansi blue_italic)(relative_pwd $file)(ansi reset)"
}
