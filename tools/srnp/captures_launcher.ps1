param([string]$Exe, [string]$Lad, [string]$Out)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Fen2 {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
}
"@
$noms = @('play','settings','controls','gamefiles','mods','screenshots','credits')
$env:LOCALAPPDATA = $Lad
for ($i = 0; $i -lt 7; $i++) {
  $env:MODERNGEKKO_LAUNCHER_PAGE = "$i"
  $p = Start-Process -FilePath $Exe -PassThru
  Start-Sleep -Seconds 9
  $p.Refresh()
  $h = $p.MainWindowHandle
  if ($h -eq [IntPtr]::Zero) { "page $i : pas de fenêtre" } else {
    $r = New-Object Fen2+RECT
    [void][Fen2]::GetWindowRect($h, [ref]$r)
    $w = $r.R - $r.L; $hg = $r.B - $r.T
    $bmp = New-Object System.Drawing.Bitmap $w, $hg
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $dc = $g.GetHdc(); $ok = [Fen2]::PrintWindow($h, $dc, 2); $g.ReleaseHdc($dc)
    $f = Join-Path $Out ("launcher_{0}_{1}.png" -f $i, $noms[$i])
    $bmp.Save($f, [System.Drawing.Imaging.ImageFormat]::Png)
    "page $i ${w}x${hg} -> $f"
  }
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 1
}
