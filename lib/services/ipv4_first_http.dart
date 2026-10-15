import 'dart:io';

/// Connects to servers over IPv4 when they have an IPv4 address.
///
/// Some home connections (seen on PLDT fiber) hand out IPv6 that doesn't
/// actually reach the internet: a request to a server with an IPv6 address
/// then hangs until it times out (12 s+ for the walking-route server, while
/// IPv4 answered in 1.6 s). Dart tries the addresses in the order DNS gives
/// them, so these servers never answered on such a connection. Installed
/// once at startup, this covers every request made from Dart (routing,
/// place search, weather, Supabase); Firebase and the map have their own
/// native networking.
class Ipv4FirstHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (proxyHost != null && proxyPort != null) {
        // Through a proxy, as HttpClient would connect itself.
        return Socket.startConnect(proxyHost, proxyPort);
      }
      final address = await _pickAddress(uri.host);
      if (uri.scheme == 'https') {
        // The address keeps the host name, which the certificate is
        // checked against.
        return SecureSocket.startConnect(address, uri.port, context: context);
      }
      return Socket.startConnect(address, uri.port);
    };
    return client;
  }

  static Future<InternetAddress> _pickAddress(String host) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return literal;
    final addresses = await InternetAddress.lookup(host);
    return addresses.firstWhere(
      (a) => a.type == InternetAddressType.IPv4,
      orElse: () => addresses.first,
    );
  }
}
