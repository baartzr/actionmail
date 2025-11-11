# Branding Configuration

The app name and platform-specific resources are controlled via `brand_config.yaml`.

## Changing the Product Name

1. Update `branding/brand_config.yaml` with your desired values.
2. Run the branding update script:
   ```bash
   dart run tool/update_branding.dart
   ```
3. Rebuild your Flutter targets / installers as needed.

This regenerates:
- `lib/constants/app_brand.dart`
- Android app name string
- Windows runner resources and window title
- Installer script metadata
- Installer documentation

When adding new files that reference the product name, consider updating the script so future renames only require changing the YAML file.
