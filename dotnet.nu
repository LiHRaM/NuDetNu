def pick-csproj [query?: string] {
    let options = (glob **/*.csproj -d 5
    | where {|file|
        let doc = try { open $file | from xml } catch { {} }   # ignore bad files

        let sdk      = try { $doc.attributes.Sdk? } catch { "" }
        let outType  = try { (($doc.content | where {|e| $e.tag == 'PropertyGroup'}|first).content | where {|e| $e.tag == 'OutputType'}).content | each {|e| $e.content} | first | first } catch { "" }

        (($sdk | str contains 'Web') or                     # web SDK
        (($sdk | str contains 'Microsoft.NET.Sdk') and     # console SDK
         ($outType | str contains 'Exe')))
    })

    # ideally we could ensure that such a channel exists but it's a bit of a hail mary to ensure.
    let project = (
      $options
       | each { |f| $"($f | path parse | get stem)|($f)" }
       | str join (char newline)
       | tv -p "bat --style=numbers,grid --color=always {split:|:1}" --source-display="{split:|:0}" --source-output="{split:|:1}" --input $"($query)" --select-1
    )
 
    return $project;
}
alias dn = dotnet

def "dn w" [query? :string, ...rest: string] {
  let project = pick-csproj $query
  dotnet watch --project $project ...$rest
}

def "dn r" [query? :string, ...rest: string] {
  let project = pick-csproj $query
  dotnet run --project $project ...$rest
}

alias "dn b" = dotnet build
