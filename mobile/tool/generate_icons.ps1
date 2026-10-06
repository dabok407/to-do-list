$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$taskRoot=Split-Path -Parent $PSScriptRoot
function Write-BrandIcon([string]$destination,[int]$size){
  $bitmap=[System.Drawing.Bitmap]::new($size,$size)
  $graphics=[System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.Clear([System.Drawing.Color]::FromArgb(32,36,43))
  $graphics.ScaleTransform($size/1024.0,$size/1024.0)
  $pen=[System.Drawing.Pen]::new([System.Drawing.Color]::White,96)
  $pen.StartCap=[System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap=[System.Drawing.Drawing2D.LineCap]::Round
  $pen.LineJoin=[System.Drawing.Drawing2D.LineJoin]::Round
  $graphics.DrawLine($pen,300,710,724,286)
  $points=[System.Drawing.PointF[]]@([System.Drawing.PointF]::new(384,286),[System.Drawing.PointF]::new(724,286),[System.Drawing.PointF]::new(724,626))
  $graphics.DrawLines($pen,$points)
  $bitmap.Save($destination,[System.Drawing.Imaging.ImageFormat]::Png)
  $pen.Dispose();$graphics.Dispose();$bitmap.Dispose()
}
$iconRoot=Join-Path $taskRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
$contents=Get-Content (Join-Path $iconRoot 'Contents.json') -Raw | ConvertFrom-Json
foreach($icon in $contents.images){
  $dimension=[double]($icon.size.Split('x')[0])*[int]($icon.scale.Replace('x',''))
  Write-BrandIcon (Join-Path $iconRoot $icon.filename) ([int]$dimension)
}
$densities=@{'mdpi'=48;'hdpi'=72;'xhdpi'=96;'xxhdpi'=144;'xxxhdpi'=192}
foreach($density in $densities.GetEnumerator()){
  Write-BrandIcon (Join-Path $taskRoot "android/app/src/main/res/mipmap-$($density.Key)/ic_launcher.png") $density.Value
}
