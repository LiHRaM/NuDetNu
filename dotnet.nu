source fzf.nu 

def pick-csproj [query?: string] {
    glob **/*.csproj -d 5
    | filter {|file|
        let doc = try { open $file | from xml } catch { {} }   # ignore bad files

        let sdk      = try { $doc.attributes.Sdk? } catch { "" }
        let outType  = try { $doc.content.PropertyGroup.OutputType? } catch { "" }

        (($sdk | str contains 'Web') or                     # web SDK
        (($sdk | str contains 'Microsoft.NET.Sdk') and     # console SDK
         ($outType | str contains 'Exe')))
    }
    | each {|file| 
      let label = $file | path dirname | path basename  
      $"($file)\t($label)"
      }
    | pretty_fzf $query
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
