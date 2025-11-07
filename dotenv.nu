source fzf.nu 

def relative_pwd [file] {
  $file | path expand | path relative-to (pwd | path expand)
}

export def --env dotenv [query?: string] {
  let file = (
      glob **/*.env*
      | each {|file| 
        let label = relative_pwd $file
        $"($file)\t($label)"
        }
      | pretty_fzf $query  --preview-cmd="bat --color=always")
  open $file | from toml | load-env
  print $"Loaded (ansi blue_italic)(relative_pwd $file)(ansi reset)"
}
