[CmdletBinding()]
param(
    [switch]$Check,
    [string]$Updated = "2026-11-02"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$nl = [string][char]10
$utf8 = [System.Text.UTF8Encoding]::new($false)
$sectionIds = @{
    1 = "model"; 2 = "ssh"; 3 = "daily"; 4 = "branch"
    5 = "examples"; 6 = "team-demo"; 7 = "shared-branch"
    8 = "amend-message"; 9 = "force-with-lease"; 10 = "dates"
    11 = "recover"; 12 = "incidents"; 13 = "references"
}

foreach ($language in @("zh", "en")) {
    $english = $language -eq "en"
    $relativeSource = if ($english) { "knowledge-base/en/git.md" } else { "knowledge-base/git.md" }
    $relativeOutput = if ($english) { "knowledge-base/en/git/index.html" } else { "knowledge-base/git/index.html" }
    $source = Join-Path $repoRoot $relativeSource
    $output = Join-Path $repoRoot $relativeOutput
    $markdown = [System.IO.File]::ReadAllText($source)
    $html = (ConvertFrom-Markdown -InputObject $markdown).Html
    $html = [regex]::Replace($html, '(?s)^<h1\b.*?</h1>\s*', '')

    # Keep established topic anchors when the tutorial outline changes.
    $headings = [regex]::Matches($html, '<h([23]) id="[^"]*">(.*?)</h[23]>')
    $builder = [System.Text.StringBuilder]::new()
    $outline = [System.Collections.Generic.List[object]]::new()
    $offset = 0
    foreach ($heading in $headings) {
        $level = [int]$heading.Groups[1].Value
        $title = $heading.Groups[2].Value
        $number = [regex]::Match($title, '^(\d+)(?:\.(\d+))?\s')
        if (-not $number.Success) { throw "Missing numbered heading in $relativeSource : $title" }
        $main = [int]$number.Groups[1].Value
        $sub = $number.Groups[2].Value
        $id = if ($level -eq 2) { $sectionIds[$main] } elseif ($main -eq 5 -and $sub -eq "3") { "review" } else { "git-$main-$sub" }
        if (-not $id) { throw "Unknown section number: $title" }
        [void]$builder.Append($html.Substring($offset, $heading.Index - $offset))
        [void]$builder.Append('<h' + $level + ' id="' + $id + '">' + $title + '</h' + $level + '>')
        $outline.Add([pscustomobject]@{ Level = $level; Id = $id; Title = $title })
        $offset = $heading.Index + $heading.Length
    }
    [void]$builder.Append($html.Substring($offset))
    $html = $builder.ToString()
    if (@($outline | Where-Object Level -eq 2).Count -ne 13) { throw "Expected 13 main sections in $relativeSource" }

    $toc = [System.Text.StringBuilder]::new()
    $tocTitle = if ($english) { "Contents" } else { "目录" }
    [void]$toc.Append('<details class="git-toc" open><summary>' + $tocTitle + '</summary><nav aria-label="' + $tocTitle + '"><ul class="git-toc-list">')
    $mainOpen = $false
    $childrenOpen = $false
    foreach ($item in $outline) {
        if ($item.Level -eq 2) {
            if ($childrenOpen) { [void]$toc.Append('</ul>'); $childrenOpen = $false }
            if ($mainOpen) { [void]$toc.Append('</li>') }
            [void]$toc.Append('<li><a href="#' + $item.Id + '">' + $item.Title + '</a>')
            $mainOpen = $true
        } else {
            if (-not $childrenOpen) { [void]$toc.Append('<ul>'); $childrenOpen = $true }
            [void]$toc.Append('<li><a href="#' + $item.Id + '">' + $item.Title + '</a></li>')
        }
    }
    if ($childrenOpen) { [void]$toc.Append('</ul>') }
    if ($mainOpen) { [void]$toc.Append('</li>') }
    [void]$toc.Append('</ul></nav></details>')

    $codeLabels = if ($english) {
        @{ bash = "Git commands"; powershell = "PowerShell"; sshconfig = "SSH config"; text = "Text" }
    } else {
        @{ bash = "Git 命令"; powershell = "PowerShell"; sshconfig = "SSH 配置"; text = "文本" }
    }
    $html = [regex]::Replace($html, '(?s)<pre><code class="language-([^"]+)">(.*?)</code></pre>', {
        param($code)
        $syntax = $code.Groups[1].Value
        $caption = $codeLabels[$syntax]
        if (-not $caption) { $caption = $syntax }
        return '<figure class="git-command"><figcaption>' + $caption + '</figcaption><pre class="kb-code"><code class="language-' + $syntax + '">' + $code.Groups[2].Value + '</code></pre></figure>'
    })
    $html = $html.Replace('<table>', '<table class="kb-table">')
    $firstSection = $html.IndexOf('<h2')
    if ($firstSection -lt 0) { throw "No rendered sections in $relativeSource" }
    $intro = '<div class="kb-lead">' + $html.Substring(0, $firstSection) + '</div>'
    $parts = [regex]::Split($html.Substring($firstSection), '(?=<h2\b)') | Where-Object { $_.Trim() }
    $sections = foreach ($part in $parts) { '<section class="kb-section">' + $part + '</section>' }
    $content = '<div class="article-content keep-markdown-body git-tutorial">' + $nl + $intro + $nl + $toc.ToString() + $nl + ($sections -join $nl)

    $existing = [System.IO.File]::ReadAllText($output).Replace([string][char]13, "")
    $pagePattern = [regex]::new('(?s)<div class="article-content keep-markdown-body(?: git-tutorial)?">.*?(?=\n    </div>\n  </div></div></div></div>)')
    if ($pagePattern.Matches($existing).Count -ne 1) { throw "Article shell not found in $relativeOutput" }
    $page = $pagePattern.Replace($existing, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $content }, 1)
    $meta = if ($english) { "Updated $Updated · SSH / commits / collaboration / recovery" } else { "更新于 $Updated · SSH / 提交 / 团队协作 / 版本恢复" }
    $page = [regex]::new('<div class="kb-meta">.*?</div>').Replace($page, '<div class="kb-meta">' + $meta + '</div>', 1)
    $description = if ($english) { "Git tutorial with a numbered contents list, SSH setup, commits, team demos, conflict resolution, and recovery" } else { "Git 分级教程：SSH 配置、提交、分支、双人协作、冲突处理、提交信息与时间修改和版本恢复" }
    $page = [regex]::new('<meta name="description" content="[^"]*">').Replace($page, '<meta name="description" content="' + $description + '">', 1)
    if (-not $page.Contains('rel="canonical"')) {
        $canonical = if ($english) { "https://yanruihe.github.io/knowledge-base/en/git/" } else { "https://yanruihe.github.io/knowledge-base/git/" }
        $links = '<link rel="canonical" href="' + $canonical + '">' + $nl +
            '<link rel="alternate" hreflang="zh-CN" href="https://yanruihe.github.io/knowledge-base/git/">' + $nl +
            '<link rel="alternate" hreflang="en" href="https://yanruihe.github.io/knowledge-base/en/git/">'
        $page = $page.Replace('</head>', $links + $nl + '</head>')
    }
    if ($Check) {
        if ($page -cne $existing) { throw "Generated page is out of date: $relativeOutput" }
        Write-Output "$relativeOutput is up to date"
    } else {
        [System.IO.File]::WriteAllText($output, $page, $utf8)
        Write-Output "Rendered $relativeOutput"
    }
}
