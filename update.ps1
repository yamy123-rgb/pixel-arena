$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

$feeds = @(
    @{ Name = "Dexerto Fortnite"; Url = "https://www.dexerto.com/fortnite/feed/"; Tag = "FORTNITE" },
    @{ Name = "Dexerto";          Url = "https://www.dexerto.com/feed/";         Tag = "ESPORTS"  },
    @{ Name = "Dot Esports";      Url = "https://dotesports.com/feed";           Tag = "ESPORTS"  },
    @{ Name = "IGN";              Url = "http://feeds.feedburner.com/ign/all";   Tag = "GAMING"   },
    @{ Name = "PC Gamer";         Url = "https://www.pcgamer.com/rss/";          Tag = "PC"       },
    @{ Name = "GameSpot";         Url = "https://www.gamespot.com/feeds/news/";  Tag = "GAMING"   },
    @{ Name = "Polygon";          Url = "https://www.polygon.com/rss/index.xml"; Tag = "GAMING"   }
)

function Clean-Html([string]$s) {
    if (-not $s) { return "" }
    $s = $s -replace '<[^>]+>', ''
    $s = [System.Net.WebUtility]::HtmlDecode($s)
    $s = $s -replace '\s+', ' '
    return $s.Trim()
}

function Get-FirstImage([string]$html) {
    if (-not $html) { return $null }
    $m = [regex]::Match($html, '<img[^>]+src=["'']([^"'']+)["'']', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Html-Encode([string]$s) {
    if (-not $s) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($s)
}

$allItems = New-Object System.Collections.ArrayList

foreach ($feed in $feeds) {
    try {
        Write-Host "Fetching $($feed.Name)..."
        $raw = (Invoke-WebRequest -Uri $feed.Url -UseBasicParsing -TimeoutSec 20 -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) pixel-arena/1.0").Content
        [xml]$xml = $raw

        $items = $xml.rss.channel.item
        if (-not $items) { continue }

        foreach ($item in $items) {
            $title = if ($item.title.'#cdata-section') { $item.title.'#cdata-section' } elseif ($item.title.InnerText) { $item.title.InnerText } else { [string]$item.title }
            $link  = if ($item.link.'#cdata-section')  { $item.link.'#cdata-section' }  elseif ($item.link.InnerText)  { $item.link.InnerText }  else { [string]$item.link }
            $desc  = if ($item.description.'#cdata-section') { $item.description.'#cdata-section' } elseif ($item.description.InnerText) { $item.description.InnerText } else { [string]$item.description }

            $encodedContent = $null
            foreach ($child in $item.ChildNodes) {
                if ($child.LocalName -eq "encoded") { $encodedContent = $child.InnerText; break }
            }

            $pubRaw = [string]$item.pubDate
            $pubDate = $null
            try { $pubDate = [datetime]::Parse($pubRaw) } catch { $pubDate = Get-Date }

            # Extract image
            $image = $null
            foreach ($child in $item.ChildNodes) {
                if ($child.LocalName -eq "thumbnail" -and $child.Attributes["url"]) { $image = $child.Attributes["url"].Value; break }
                if ($child.LocalName -eq "content"   -and $child.Attributes["url"]) {
                    $t = $child.Attributes["type"]; if (-not $t -or $t.Value -like "image/*") { $image = $child.Attributes["url"].Value; break }
                }
            }
            if (-not $image -and $item.enclosure -and $item.enclosure.type -and $item.enclosure.type -like "image/*") {
                $image = $item.enclosure.url
            }
            if (-not $image -and $encodedContent) { $image = Get-FirstImage $encodedContent }
            if (-not $image) { $image = Get-FirstImage $desc }

            $cleanDesc = Clean-Html $desc
            if ($cleanDesc.Length -gt 200) { $cleanDesc = $cleanDesc.Substring(0, 200).TrimEnd() + "..." }

            [void]$allItems.Add([PSCustomObject]@{
                Title = (Clean-Html $title)
                Link = $link.Trim()
                Description = $cleanDesc
                PubDate = $pubDate
                Source = $feed.Name
                Tag = $feed.Tag
                Image = $image
            })
        }
    } catch {
        Write-Host "  Failed: $($feed.Name) - $($_.Exception.Message)"
    }
}

if ($allItems.Count -eq 0) {
    Write-Host "No items fetched. Aborting."
    exit 1
}

# Dedup by title (case-insensitive)
$seen = @{}
$unique = New-Object System.Collections.ArrayList
foreach ($it in ($allItems | Sort-Object -Property PubDate -Descending)) {
    $k = $it.Title.ToLowerInvariant()
    if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; [void]$unique.Add($it) }
}

$top = $unique | Select-Object -First 31
$featured = $top[0]
$rest = $top | Select-Object -Skip 1

function Time-Ago([datetime]$d) {
    $span = (Get-Date) - $d
    if ($span.TotalMinutes -lt 60) { return ("{0}m ago" -f [int]$span.TotalMinutes) }
    if ($span.TotalHours   -lt 24) { return ("{0}h ago" -f [int]$span.TotalHours) }
    if ($span.TotalDays    -lt 7)  { return ("{0}d ago" -f [int]$span.TotalDays) }
    return $d.ToString("MMM d")
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append(@'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>PIXEL ARENA — Gaming & Esports News</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Orbitron:wght@600;800;900&family=Rajdhani:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  :root {
    --bg: #05060a;
    --bg-2: #0b0d16;
    --card: #11131f;
    --card-hover: #171a2b;
    --border: #1e2236;
    --text: #e7e9f3;
    --muted: #8a8fa8;
    --cyan: #00f0ff;
    --magenta: #ff2e93;
    --green: #39ff14;
    --yellow: #ffe81a;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { background: var(--bg); color: var(--text); font-family: "Rajdhani", system-ui, sans-serif; min-height: 100vh; }
  body {
    background-image:
      radial-gradient(circle at 10% 10%, rgba(0,240,255,0.08), transparent 40%),
      radial-gradient(circle at 90% 20%, rgba(255,46,147,0.08), transparent 40%),
      linear-gradient(180deg, #05060a, #090b14 60%, #05060a);
    background-attachment: fixed;
  }
  body::before {
    content: "";
    position: fixed; inset: 0;
    background-image:
      linear-gradient(rgba(255,255,255,0.015) 1px, transparent 1px),
      linear-gradient(90deg, rgba(255,255,255,0.015) 1px, transparent 1px);
    background-size: 40px 40px;
    pointer-events: none;
    z-index: 0;
  }
  a { color: inherit; text-decoration: none; }

  .wrap { max-width: 1280px; margin: 0 auto; padding: 24px 20px 80px; position: relative; z-index: 1; }

  header.top {
    display: flex; align-items: center; justify-content: space-between;
    padding: 18px 22px; margin-bottom: 28px;
    background: linear-gradient(90deg, rgba(17,19,31,0.9), rgba(17,19,31,0.6));
    border: 1px solid var(--border);
    border-left: 4px solid var(--cyan);
    clip-path: polygon(0 0, 100% 0, 100% calc(100% - 12px), calc(100% - 12px) 100%, 0 100%);
    backdrop-filter: blur(6px);
  }
  .logo {
    font-family: "Orbitron", sans-serif; font-weight: 900;
    font-size: 28px; letter-spacing: 3px;
    background: linear-gradient(90deg, var(--cyan), var(--magenta));
    -webkit-background-clip: text; background-clip: text; color: transparent;
    text-shadow: 0 0 20px rgba(0,240,255,0.35);
  }
  .logo span.dot { color: var(--green); -webkit-text-fill-color: var(--green); }
  .meta { font-size: 13px; color: var(--muted); text-align: right; letter-spacing: 1px; text-transform: uppercase; }
  .meta .live { color: var(--green); font-weight: 700; }
  .meta .live::before { content: "● "; animation: pulse 1.4s infinite; }
  @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.3; } }

  .hero {
    position: relative;
    display: grid; grid-template-columns: 1.3fr 1fr; gap: 0;
    margin-bottom: 36px;
    background: var(--card);
    border: 1px solid var(--border);
    overflow: hidden;
    min-height: 380px;
  }
  .hero::before {
    content: ""; position: absolute; top: 0; left: 0; width: 4px; height: 100%;
    background: linear-gradient(180deg, var(--magenta), var(--cyan));
  }
  .hero-img {
    background-size: cover; background-position: center;
    background-color: #0a0c18;
    position: relative; min-height: 280px;
  }
  .hero-img::after {
    content: ""; position: absolute; inset: 0;
    background: linear-gradient(90deg, transparent 40%, rgba(17,19,31,0.95) 100%);
  }
  .hero-img.nofeatured {
    background-image: linear-gradient(135deg, #1a1040 0%, #3a0d4a 40%, #0d2a4a 100%);
  }
  .hero-body { padding: 36px 36px; display: flex; flex-direction: column; justify-content: center; gap: 18px; }
  .hero .tag { align-self: flex-start; }
  .hero h1 {
    font-family: "Orbitron", sans-serif; font-weight: 800;
    font-size: 34px; line-height: 1.12; letter-spacing: 0.5px;
    color: #fff;
  }
  .hero h1 a:hover { color: var(--cyan); }
  .hero p { color: var(--muted); font-size: 17px; line-height: 1.55; }
  .hero .byline { color: var(--muted); font-size: 13px; letter-spacing: 1.5px; text-transform: uppercase; }
  .hero .byline b { color: var(--green); font-weight: 700; }

  .tag {
    display: inline-block;
    font-family: "Orbitron", sans-serif; font-weight: 700;
    font-size: 11px; letter-spacing: 2.5px;
    padding: 6px 12px;
    background: rgba(0,240,255,0.08);
    border: 1px solid var(--cyan);
    color: var(--cyan);
    clip-path: polygon(8px 0, 100% 0, calc(100% - 8px) 100%, 0 100%);
  }
  .tag.fortnite  { background: rgba(255,232,26,0.08); border-color: var(--yellow);   color: var(--yellow);   }
  .tag.esports   { background: rgba(255,46,147,0.08); border-color: var(--magenta);  color: var(--magenta);  }
  .tag.gaming    { background: rgba(0,240,255,0.08);  border-color: var(--cyan);     color: var(--cyan);     }
  .tag.pc        { background: rgba(57,255,20,0.08);  border-color: var(--green);    color: var(--green);    }

  .section-title {
    font-family: "Orbitron", sans-serif; font-weight: 800;
    font-size: 18px; letter-spacing: 3px;
    color: #fff;
    margin: 28px 0 18px; padding-bottom: 10px;
    border-bottom: 1px solid var(--border);
    display: flex; align-items: center; gap: 14px;
  }
  .section-title::before {
    content: ""; width: 10px; height: 18px; background: var(--cyan); display: inline-block;
    box-shadow: 0 0 8px var(--cyan);
  }

  .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 18px; }
  .card {
    background: var(--card);
    border: 1px solid var(--border);
    overflow: hidden;
    display: flex; flex-direction: column;
    transition: transform 0.18s, border-color 0.18s, box-shadow 0.18s;
    position: relative;
  }
  .card:hover {
    transform: translateY(-4px);
    border-color: var(--cyan);
    box-shadow: 0 10px 40px rgba(0,240,255,0.18);
  }
  .card:hover .card-img { transform: scale(1.04); }
  .card-img-wrap { aspect-ratio: 16/9; overflow: hidden; background: #0a0c18; position: relative; }
  .card-img {
    width: 100%; height: 100%;
    background-size: cover; background-position: center;
    transition: transform 0.4s;
  }
  .card-img.placeholder {
    background-image: linear-gradient(135deg, #141a35 0%, #2a1040 100%);
  }
  .card-img.placeholder::after {
    content: "◆ PIXEL ARENA ◆";
    position: absolute; inset: 0;
    display: flex; align-items: center; justify-content: center;
    font-family: "Orbitron", sans-serif; font-weight: 800;
    color: rgba(255,255,255,0.1); letter-spacing: 3px; font-size: 14px;
  }
  .card-body { padding: 16px 18px 20px; flex: 1; display: flex; flex-direction: column; gap: 10px; }
  .card h3 {
    font-family: "Orbitron", sans-serif; font-weight: 700;
    font-size: 16px; line-height: 1.3; color: #fff;
  }
  .card:hover h3 { color: var(--cyan); }
  .card p { color: var(--muted); font-size: 14px; line-height: 1.5; flex: 1; }
  .card-footer {
    display: flex; justify-content: space-between; align-items: center;
    font-size: 12px; color: var(--muted); letter-spacing: 1px; text-transform: uppercase;
    padding-top: 6px; border-top: 1px solid var(--border);
  }
  .card-footer b { color: var(--text); font-weight: 600; }

  footer.bottom {
    margin-top: 50px; padding: 24px 20px; text-align: center;
    color: var(--muted); font-size: 13px; letter-spacing: 1.5px;
    border-top: 1px solid var(--border);
  }
  footer.bottom span { color: var(--cyan); }

  @media (max-width: 900px) {
    .hero { grid-template-columns: 1fr; }
    .hero-img { min-height: 200px; }
    .hero h1 { font-size: 26px; }
    .grid { grid-template-columns: repeat(2, 1fr); }
  }
  @media (max-width: 560px) {
    .logo { font-size: 20px; letter-spacing: 2px; }
    .meta { font-size: 11px; }
    .grid { grid-template-columns: 1fr; }
    .hero-body { padding: 22px; }
  }
</style>
</head>
<body>
<div class="wrap">
  <header class="top">
    <div class="logo">PIXEL<span class="dot">/</span>ARENA</div>
    <div class="meta">
      <div class="live">LIVE FEED</div>
      <div>UPDATED __UPDATED__</div>
    </div>
  </header>
'@)

# Hero
$fTag = $featured.Tag
$fClass = "tag " + $fTag.ToLower()
if ($featured.Source -like "*Fortnite*") { $fClass = "tag fortnite"; $fTag = "FORTNITE" }

$heroImgStyle = if ($featured.Image) { "style=`"background-image:url('$([System.Net.WebUtility]::HtmlEncode($featured.Image))')`"" } else { "" }
$heroImgClass = if ($featured.Image) { "hero-img" } else { "hero-img nofeatured" }

[void]$sb.Append(@"
  <section class="hero">
    <div class="$heroImgClass" $heroImgStyle></div>
    <div class="hero-body">
      <span class="$fClass">$fTag</span>
      <h1><a href="$([System.Net.WebUtility]::HtmlEncode($featured.Link))" target="_blank" rel="noopener">$([System.Net.WebUtility]::HtmlEncode($featured.Title))</a></h1>
      <p>$([System.Net.WebUtility]::HtmlEncode($featured.Description))</p>
      <div class="byline"><b>$([System.Net.WebUtility]::HtmlEncode($featured.Source))</b> · $(Time-Ago $featured.PubDate)</div>
    </div>
  </section>

  <div class="section-title">LATEST DROPS</div>
  <div class="grid">
"@)

foreach ($item in $rest) {
    $cTag = $item.Tag
    $cClass = "tag " + $cTag.ToLower()
    if ($item.Source -like "*Fortnite*") { $cClass = "tag fortnite"; $cTag = "FORTNITE" }

    if ($item.Image) {
        $imgHtml = "<div class=`"card-img`" style=`"background-image:url('$([System.Net.WebUtility]::HtmlEncode($item.Image))')`"></div>"
    } else {
        $imgHtml = "<div class=`"card-img placeholder`"></div>"
    }

    [void]$sb.Append(@"
    <a class="card" href="$([System.Net.WebUtility]::HtmlEncode($item.Link))" target="_blank" rel="noopener">
      <div class="card-img-wrap">$imgHtml</div>
      <div class="card-body">
        <span class="$cClass">$cTag</span>
        <h3>$([System.Net.WebUtility]::HtmlEncode($item.Title))</h3>
        <p>$([System.Net.WebUtility]::HtmlEncode($item.Description))</p>
        <div class="card-footer"><b>$([System.Net.WebUtility]::HtmlEncode($item.Source))</b><span>$(Time-Ago $item.PubDate)</span></div>
      </div>
    </a>
"@)
}

[void]$sb.Append(@'
  </div>
  <footer class="bottom">
    <span>◆</span> PIXEL ARENA · Auto-aggregated from IGN, Dexerto, Dot Esports, PC Gamer, GameSpot, Polygon <span>◆</span>
  </footer>
</div>
</body>
</html>
'@)

$now = Get-Date -Format "dddd, MMM d · HH:mm"
$html = $sb.ToString().Replace("__UPDATED__", $now.ToUpper())

$outPath = Join-Path $scriptDir "index.html"
[System.IO.File]::WriteAllText($outPath, $html, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "Generated: $outPath"
Write-Host "Articles: $($top.Count) (1 featured + $($rest.Count) cards)"
