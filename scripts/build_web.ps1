# Builds the production web app with the business branding (Windows).
#   .\scripts\build_web.ps1 [config\local.json]
param([string]$Config = "config/local.json")
$ErrorActionPreference = "Stop"
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter build web --release --dart-define-from-file=$Config
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
dart run tool/apply_brand.dart $Config build/web
exit $LASTEXITCODE
