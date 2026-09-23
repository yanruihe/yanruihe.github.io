# Alice/Bob collaboration demo. Requires PowerShell 7 and Git.
# Creates only a new directory under the current user's TEMP folder.
$ErrorActionPreference = "Stop"
$demoRoot = Join-Path $env:TEMP ("git-team-demo-" + [guid]::NewGuid().ToString("N"))
$remote = Join-Path $demoRoot "remote.git"
$alice = Join-Path $demoRoot "alice"
$bob = Join-Path $demoRoot "bob"
New-Item -ItemType Directory -Path $demoRoot | Out-Null

git init --bare $remote
git --git-dir=$remote symbolic-ref HEAD refs/heads/main
git clone $remote $alice
git -C $alice config user.name Alice
git -C $alice config user.email alice@example.test
Set-Content (Join-Path $alice "README.md") "Team notes"
git -C $alice add README.md
git -C $alice commit -m "docs: start team notes"
git -C $alice push -u origin main
if ($LASTEXITCODE -ne 0) { throw "Initial push failed" }

git clone $remote $bob
git -C $bob config user.name Bob
git -C $bob config user.email bob@example.test
git -C $alice switch -c docs/add-workflow
Add-Content (Join-Path $alice "README.md") "Review changes before merging."
git -C $alice add README.md
git -C $alice commit -m "docs: add review workflow"
git -C $alice push -u origin docs/add-workflow
if ($LASTEXITCODE -ne 0) { throw "Feature branch push failed" }

git -C $bob fetch origin
git -C $bob diff origin/main...origin/docs/add-workflow
git -C $bob log --oneline origin/main..origin/docs/add-workflow
git -C $bob switch main
git -C $bob merge --no-ff origin/docs/add-workflow -m "merge: add review workflow"
git -C $bob push origin main
if ($LASTEXITCODE -ne 0) { throw "Merge push failed" }

git -C $alice switch main
git -C $alice pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw "Alice sync failed" }
git -C $alice log --oneline --graph -4

$aliceHead = git -C $alice rev-parse main
$remoteHead = git --git-dir=$remote rev-parse main
$readme = Get-Content -LiteralPath (Join-Path $alice "README.md")
if ($aliceHead -ne $remoteHead -or $readme -notcontains "Review changes before merging.") {
    throw "Verification failed: Alice did not receive the merged change"
}
Write-Output "Demo succeeded. Inspect the temporary repositories at: $demoRoot"
