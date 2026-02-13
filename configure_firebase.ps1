$env:Path = "C:\Users\kanda\AppData\Roaming\npm;" + $env:Path
Write-Host "Added npm to PATH temporarily."
Write-Host "Running flutterfire configure..."
& "C:\src\flutter\bin\flutter.bat" pub global run flutterfire_cli:flutterfire configure
Read-Host -Prompt "Press Enter to exit"
