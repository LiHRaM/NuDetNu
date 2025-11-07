
export def pretty_fzf [query?: string, --preview-cmd (-p): string] {
  let entries = (
  $in
    | uniq
    | str join "\n"
    )

  mut cmd = {}

  if  not ( $preview_cmd | is-empty)  {
    $cmd = (
      $entries
      | fzf --delimiter='\t' --with-nth 2 --layout=reverse --height 10 --select-1 --query $"($query)" --preview $"($preview_cmd) {1} --file-name={2}"
      | complete
      )
  } else {
    $cmd = (
      $entries
      | fzf --delimiter='\t' --with-nth 2 --layout=reverse --height 10 --select-1 --query $"($query)" 
      | complete
      )
  }

  let results = $cmd | complete

  if $results.exit_code != 0 {
      error make {msg: "No matches found" } -u
  }

  $results.stdout
    | split column "\t"
    | get column1
    | first
}
