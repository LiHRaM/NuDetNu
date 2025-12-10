
export def --wrapped "gt go" [query?: string, ...rest] {
  let branch = tv git-branch --input $"($query)" --select-1 --preview "bat -n --color=always {}" --custom-header "Select branch"

  git switch $branch ...$rest
}
