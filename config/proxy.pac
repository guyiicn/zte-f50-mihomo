function FindProxyForURL(url, host) {
  if (isPlainHostName(host) || shExpMatch(host, "*.local") ||
      shExpMatch(host, "192.168.*") || shExpMatch(host, "10.*") ||
      shExpMatch(host, "127.*") || host == "localhost")
    return "DIRECT";
  return "PROXY 192.168.0.1:7890; DIRECT";
}
