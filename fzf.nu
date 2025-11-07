
export def pretty_fzf [query?: string, --preview-cmd (-p): string] {
  let entries = (
  $in
    | uniq
    | str join "\n"
    )

  mut results = {}

  if  not ( $preview_cmd | is-empty)  {
    $results = (
      $entries
      | fzf --delimiter='\t' --with-nth 2 --layout=reverse --height 10 --select-1 --query $"($query)" --preview $"($preview_cmd)"
      | complete
      )
  } else {
    $results = (
      $entries
      | fzf --delimiter='\t' --with-nth 2 --layout=reverse --height 10 --select-1 --query $"($query)" 
      | complete
      )
  }


  if $results.exit_code != 0 {
      error make {msg: "No matches found" } -u
  }

  $results.stdout
    | split column "\t"
    | get column1
    | first
}
