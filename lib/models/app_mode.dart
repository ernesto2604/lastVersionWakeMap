enum AppMode {
  commuter,
  traveller;

  String get displayName {
    switch (this) {
      case AppMode.commuter:
        return 'Commuter';
      case AppMode.traveller:
        return 'Traveller';
    }
  }
}
