# doMail Installer Setup

This directory contains the Inno Setup script for creating a Windows installer for doMail.

## Prerequisites

1. **Download and Install Inno Setup**
   - Download from: https://jrsoftware.org/isdl.php
   - Install Inno Setup 6.2 or later
   - Choose the default installation options

2. **Build the Flutter App**
   ```bash
   flutter build windows --release
   ```

## Creating the Installer

### Method 1: Using Inno Setup IDE (GUI)

1. Open Inno Setup Compiler
2. Click `File` → `Open` and select `app_setup.iss`
3. Click `Build` → `Compile` (or press F9)
4. The installer will be created in `build\installer\doMail-Setup-1.0.0.exe`

### Method 2: Using Command Line

```powershell
# Compile the installer from command line
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\app_setup.iss
```

Or add this to your PowerShell profile for easier access:

```powershell
# Run from project root
.\build_installer.ps1
```

## Customization

Before building, you may want to customize:

1. **App Version** (line 6): Change `#define MyAppVersion "1.0.0"`
2. **App Publisher** (line 7): Change `#define MyAppPublisher "doMail"`
3. **App URL** (line 8): Change to your actual website
4. **App ID** (line 10): Generate a new GUID (Tools → Generate GUID in Inno Setup)

## Output

The installer will be created at:
```
build\installer\doMail-Setup-1.0.0.exe
```

## What the Installer Does

1. Installs doMail to `C:\Program Files\doMail\` (or user's choice)
2. Creates Start Menu shortcut
3. Optionally creates Desktop shortcut
4. Checks for WebView2 Runtime and prompts to install if missing
5. Creates an uninstaller

## Testing

After building the installer:

1. Run the installer on a clean Windows machine (or VM)
2. Verify the app launches correctly
3. Test the uninstaller works properly

## Notes

- The installer requires the app to be built in Release mode first
- All DLLs and the `data` folder are automatically included
- The installer checks for WebView2 Runtime (required for email viewing)
- Users can install without admin rights (installs to AppData)
- To update branding (product name, installer name, etc.) edit `branding/brand_config.yaml` and run `dart run tool/update_branding.dart`.

