def pretty_fzf [query?: string] {
  let results = $in
    | uniq
    | str join "\n"
    | fzf --delimiter='\t' --with-nth 2 --layout=reverse --height 10 --select-1 --query $"($query)"
    | complete

  if $results.exit_code != 0 {
      error make {msg: "No matches found" } -u
  }

  $results.stdout
    | split column "\t"
    | get column1
    | first
}
