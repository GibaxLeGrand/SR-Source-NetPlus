# Photo de la fenêtre d'un processus (ce qui est vraiment affiché, interface comprise), par PrintWindow.
#   capture_fenetre.ps1 -Motif <texte de la ligne de commande> -Png <fichier>
param([string]$Motif, [string]$Png)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Fen {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
}
"@
$p = Get-CimInstance Win32_Process -Filter "name='moderngekko-run.exe'" | Where-Object { $_.CommandLine -like "*$Motif*" } | Select-Object -First 1
if (-not $p) { "pas de processus pour $Motif"; exit 1 }
$h = (Get-Process -Id $p.ProcessId).MainWindowHandle
if ($h -eq [IntPtr]::Zero) { "pas de fenêtre pour $($p.ProcessId)"; exit 1 }
$r = New-Object Fen+RECT
[void][Fen]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L; $hgt = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $hgt
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc()
$ok = [Fen]::PrintWindow($h, $dc, 2)
$g.ReleaseHdc($dc)
$bmp.Save($Png, [System.Drawing.Imaging.ImageFormat]::Png)
"fenêtre $($p.ProcessId) ${w}x${hgt} PrintWindow=$ok -> $Png"
