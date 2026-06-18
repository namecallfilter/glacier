param(
  [string]$Device = '49200DLAQ001HG'
)

$ErrorActionPreference = 'Stop'

adb -s $Device shell setprop log.tag.r.glacier.debug S
adb -s $Device shell am force-stop com.namecallfilter.glacier.debug 2>$null

flutter run -d $Device --dart-define-from-file=.env
