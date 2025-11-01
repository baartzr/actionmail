import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

/// Service for fetching domain icons/favicons
/// Uses Google's favicon service as primary, with Clearbit as fallback
class DomainIconService {
  static final DomainIconService _instance = DomainIconService._internal();
  factory DomainIconService() => _instance;
  DomainIconService._internal();

  // Cache for loaded icons
  final Map<String, ImageProvider?> _cache = {};
  final Map<String, Completer<ImageProvider?>> _loadingCompleters = {};

  /// Extract domain from email address
  String extractDomain(String email) {
    final at = email.indexOf('@');
    if (at == -1) return '';
    return email.substring(at + 1).toLowerCase();
  }

  /// Get icon for a domain
  /// Returns null if no icon is available (fallback to letter avatar)
  Future<ImageProvider?> getDomainIcon(String email) async {
    final domain = extractDomain(email);
    if (domain.isEmpty) return null;

    // Check cache first
    if (_cache.containsKey(domain)) {
      return _cache[domain];
    }

    // Check if already loading
    if (_loadingCompleters.containsKey(domain)) {
      return _loadingCompleters[domain]!.future;
    }

    // Start loading
    final completer = Completer<ImageProvider?>();
    _loadingCompleters[domain] = completer;

    try {
      // Try Google's favicon service first (most reliable)
      ImageProvider? provider = await _tryLoadFavicon(
        'https://www.google.com/s2/favicons?domain=$domain&sz=64',
        domain,
      );

      // Fallback to Clearbit if Google fails
      provider ??= await _tryLoadFavicon(
        'https://logo.clearbit.com/$domain',
        domain,
      );

      // Cache the result (even if null)
      _cache[domain] = provider;
      completer.complete(provider);
    } catch (e) {
      debugPrint('[DomainIcon] Error loading icon for $domain: $e');
      _cache[domain] = null;
      completer.complete(null);
    } finally {
      _loadingCompleters.remove(domain);
    }

    return completer.future;
  }

  Future<ImageProvider?> _tryLoadFavicon(String url, String domain) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          throw TimeoutException('Favicon load timeout for $domain');
        },
      );

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        // Check if it's actually an image (not an error page)
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.startsWith('image/')) {
          return MemoryImage(response.bodyBytes);
        }
      }
    } catch (e) {
      debugPrint('[DomainIcon] Failed to load $url: $e');
    }
    return null;
  }

  /// Clear the cache (useful for testing or memory management)
  void clearCache() {
    _cache.clear();
    _loadingCompleters.clear();
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => message;
}

