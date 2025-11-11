import 'dart:io';

import 'package:yaml/yaml.dart';

void main(List<String> args) {
  final configFile = File('branding/brand_config.yaml');
  if (!configFile.existsSync()) {
    stderr.writeln('branding/brand_config.yaml not found.');
    exit(1);
  }

  final yaml = loadYaml(configFile.readAsStringSync()) as YamlMap;
  final productName = _readString(yaml, 'product_name');
  final productNameLower = _readString(yaml, 'product_name_lower', fallback: productName.toLowerCase());
  final installerBase = _readString(yaml, 'installer_base_filename', fallback: '$productName-Setup');
  final windowsExeBase = _readString(yaml, 'windows_executable_name', fallback: productNameLower);
  final windowsExeName = '$windowsExeBase.exe';

  _updateAppBrandDart(productName, productNameLower, installerBase);
  _replaceInFile(
    'android/app/src/main/res/values/strings.xml',
    RegExp(r'<string name="app_name">.*?</string>'),
    '<string name="app_name">$productName</string>',
  );
  _replaceInFile(
    'windows/runner/main.cpp',
    RegExp(r'window.Create\(L".*?"'),
    'window.Create(L"$productName"',
  );
  _replaceInFile(
    'windows/runner/Runner.rc',
    RegExp(r'VALUE "FileDescription", ".*?" \\0'),
    'VALUE "FileDescription", "$productName" "\\0"',
  );
  _replaceInFile(
    'windows/runner/Runner.rc',
    RegExp(r'VALUE "InternalName", ".*?" \\0'),
    'VALUE "InternalName", "$productName" "\\0"',
  );
  _replaceInFile(
    'windows/runner/Runner.rc',
    RegExp(r'VALUE "ProductName", ".*?" \\0'),
    'VALUE "ProductName", "$productName" "\\0"',
  );
  _replaceInFile(
    'installer/app_setup.iss',
    RegExp(r'#define MyAppName ".*?"'),
    '#define MyAppName "$productName"',
  );
  _replaceInFile(
    'installer/app_setup.iss',
    RegExp(r'#define MyAppExeName ".*?"'),
    '#define MyAppExeName "$windowsExeName"',
  );
  _replaceInFile(
    'installer/app_setup.iss',
    RegExp(r'OutputBaseFilename=.*'),
    'OutputBaseFilename=$installerBase-{#MyAppVersion}',
  );
  _replaceInFile(
    'installer/README.md',
    RegExp(r'# .* Installer Setup'),
    '# $productName Installer Setup',
  );
  _replaceInFile(
    'installer/README.md',
    RegExp(r'creating a Windows installer for .*\.'),
    'creating a Windows installer for $productName.',
  );
  _replaceInFile(
    'installer/README.md',
    RegExp(r'build\\installer\\.*-Setup-1\.0\.0\.exe'),
    'build\\installer\\$installerBase-1.0.0.exe',
  );

  stdout.writeln('Branding updated to "$productName".');
}

String _readString(YamlMap map, String key, {String? fallback}) {
  final value = map[key];
  if (value is String) return value;
  if (fallback != null) return fallback;
  throw StateError('Missing "$key" in branding config.');
}

void _updateAppBrandDart(String productName, String lower, String installerBase) {
  final file = File('lib/constants/app_brand.dart');
  file.writeAsStringSync('''class AppBrand {
  const AppBrand._();

  static const String productName = '$productName';
  static const String productNameLower = '$lower';
  static const String installerBaseFilename = '$installerBase';
}
''');
}

void _replaceInFile(String path, RegExp pattern, String replacement) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Skipping $path (not found)');
    return;
  }
  final content = file.readAsStringSync();
  final updated = content.replaceFirst(pattern, replacement);
  if (updated == content) {
    stderr.writeln('Warning: pattern not found in $path');
    return;
  }
  file.writeAsStringSync(updated);
}
