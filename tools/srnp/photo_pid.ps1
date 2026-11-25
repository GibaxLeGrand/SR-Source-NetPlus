# Photo de la fenêtre principale d'un processus (ce qui est vraiment affiché), par PrintWindow.
#   photo_pid.ps1 -ProcessId <pid> -Png <fichier>
param([int]$ProcessId, [string]$Png)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Fen3 {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
}
"@
$p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
if (-not $p) { "pas de processus $ProcessId"; exit 1 }
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { "pas de fenêtre pour $ProcessId"; exit 1 }
$r = New-Object Fen3+RECT
[void][Fen3]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L; $hgt = $r.B - $r.T
if ($w -le 0 -or $hgt -le 0) { "fenêtre cachée ($ProcessId)"; exit 1 }
$bmp = New-Object System.Drawing.Bitmap $w, $hgt
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc()
$ok = [Fen3]::PrintWindow($h, $dc, 2)
$g.ReleaseHdc($dc)
$bmp.Save($Png, [System.Drawing.Imaging.ImageFormat]::Png)
"fenêtre $ProcessId ${w}x${hgt} -> $Png"
