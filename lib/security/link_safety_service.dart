import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/link_safety_result.dart';

class LinkSafetyService {
  static const String _blocklistKey = 'transit_shield_blocklist';
  static const String _allowlistKey = 'transit_shield_allowlist';

  // Configurable suspicious TLDs
  static const List<String> suspiciousTlds = [
    '.xyz',
    '.top',
    '.online',
    '.club',
    '.site',
    '.info',
    '.biz',
  ];

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<LinkSafetyResult> evaluateUrl(String url) async {
    await init();

    // Normalize URL: prepend https:// if no scheme
    String normalizedUrl = url;
    if (!url.contains('://')) {
      normalizedUrl = 'https://$url';
    }

    Uri? uri;
    try {
      uri = Uri.parse(normalizedUrl);
    } catch (e) {
      return LinkSafetyResult(
        isBlocked: true,
        riskScore: 10,
        reasons: ['Invalid URL format'],
        normalizedUrl: normalizedUrl,
        host: '',
      );
    }

    String host = uri.host.toLowerCase();
    int riskScore = 0;
    List<String> reasons = [];

    // Rule: http:// = +2 risk
    if (uri.scheme == 'http') {
      riskScore += 2;
      reasons.add('Uses HTTP instead of HTTPS');
    }

    // Rule: punycode host contains xn-- = +3 risk
    if (host.contains('xn--')) {
      riskScore += 3;
      reasons.add('Contains punycode (xn--) in host');
    }

    // Rule: IP address host = +3 risk
    RegExp ipRegex = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
    if (ipRegex.hasMatch(host)) {
      riskScore += 3;
      reasons.add('Host is an IP address');
    }

    // Rule: too many subdomains (>3) = +1 risk
    List<String> parts = host.split('.');
    if (parts.length > 4) { // e.g., a.b.c.d.com has 5 parts
      riskScore += 1;
      reasons.add('Too many subdomains (>3)');
    }

    // Rule: suspicious TLD list = +1 risk
    if (parts.isNotEmpty) {
      String tld = '.' + parts.last;
      if (suspiciousTlds.contains(tld)) {
        riskScore += 1;
        reasons.add('Suspicious TLD: $tld');
      }
    }

    // Check blocklist
    List<String> blocklist = _prefs?.getStringList(_blocklistKey) ?? [];
    bool inBlocklist = blocklist.contains(host);

    // Check allowlist
    List<String> allowlist = _prefs?.getStringList(_allowlistKey) ?? [];
    bool inAllowlist = allowlist.contains(host);

    bool isBlocked = inBlocklist || (riskScore >= 5 && !inAllowlist); // Threshold for blocking

    if (inBlocklist) {
      reasons.add('Host is in blocklist');
    }
    if (inAllowlist) {
      reasons.add('Host is in allowlist');
      isBlocked = false; // Allowlist overrides
    }

    return LinkSafetyResult(
      isBlocked: isBlocked,
      riskScore: riskScore,
      reasons: reasons,
      normalizedUrl: normalizedUrl,
      host: host,
    );
  }

  static Future<void> openSafeUrl(BuildContext context, String url) async {
    LinkSafetyResult result = await evaluateUrl(url);

    if (result.isBlocked) {
      // Show blocked dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('URL Blocked'),
          content: Text('This URL is blocked for security reasons.\n\nReasons:\n${result.reasons.join('\n')}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else if (result.riskScore > 0) {
      // Show warning interstitial
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Risky URL Warning'),
          content: Text('This URL may be risky.\n\nRisk Score: ${result.riskScore}\nReasons:\n${result.reasons.join('\n')}\n\nDo you want to continue?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await launchUrl(Uri.parse(result.normalizedUrl), mode: LaunchMode.externalApplication);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to open URL: $e')),
                  );
                }
              },
              child: const Text('Continue Anyway'),
            ),
          ],
        ),
      );
    } else {
      // Safe, open directly
      try {
        final uri = Uri.parse(result.normalizedUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot launch this URL')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open URL: $e')),
        );
      }
    }
  }

  // Utility methods for managing lists
  static Future<void> addToBlocklist(String host) async {
    await init();
    List<String> blocklist = _prefs?.getStringList(_blocklistKey) ?? [];
    if (!blocklist.contains(host)) {
      blocklist.add(host);
      await _prefs?.setStringList(_blocklistKey, blocklist);
    }
  }

  static Future<void> addToAllowlist(String host) async {
    await init();
    List<String> allowlist = _prefs?.getStringList(_allowlistKey) ?? [];
    if (!allowlist.contains(host)) {
      allowlist.add(host);
      await _prefs?.setStringList(_allowlistKey, allowlist);
    }
  }

  static Future<List<String>> getBlocklist() async {
    await init();
    return _prefs?.getStringList(_blocklistKey) ?? [];
  }

  static Future<List<String>> getAllowlist() async {
    await init();
    return _prefs?.getStringList(_allowlistKey) ?? [];
  }
}
